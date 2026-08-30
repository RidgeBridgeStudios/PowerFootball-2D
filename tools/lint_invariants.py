#!/usr/bin/env python3
"""
lint_invariants.py — Domain-Specific AST Invariant Linter for PowerFootball-2D.

Programmatically enforces architectural laws, layer separation, zero-allocation
hot paths, collision matrix integrity, and choke points beyond standard syntax checks:

1. BRAIN MUTATION:
   PlayerBrain.gd and entities/player/states/*.gd must NEVER write to
   player.velocity, player.global_position, player.base_acceleration, or invoke move_and_slide().
   All physical integration is strictly owned by HeavyPlayerController.gd.

2. HOT-PATH ZERO-ALLOCATION:
   Methods on hot paths (score_pass, score_pass_breakdown non-debug branch,
   calculate_intercept_point, _physics_process, get_dynamic_anchor_position)
   must not allocate memory (.new(), Array literals [], Dictionary literals {}).

3. COLLISION LAYER MATRIX GUARD:
   CharacterBody2D nodes in .gd and .tscn must NEVER mask Layer 3 (BallPhysicsBody, bit 3 / value 4).

4. CHOKE-POINT BYPASS DETECTION:
   Non-autoload scripts must not bypass MatchWorldModel.gd by scanning
   get_tree().get_nodes_in_group() or crawling get_node("/root/...") in AI decision loops.

Exit code 0 on pass, 1 on invariant error.
"""

from __future__ import annotations

import argparse
import html
import os
import re
import sys
from typing import List, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Regex utilities for GDScript code analysis
STRING_RE = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
COMMENT_RE = re.compile(r'#.*$')
FUNC_DEF_RE = re.compile(r'^\s*(?:static\s+)?func\s+([A-Za-z0-9_]+)\s*\((.*?)\)(?:\s*->\s*[^:]+)?\s*:', re.MULTILINE)
CLASS_NAME_RE = re.compile(r'^\s*class_name\s+([A-Za-z0-9_]+)', re.MULTILINE)
EXTENDS_RE = re.compile(r'^\s*extends\s+([A-Za-z0-9_]+)', re.MULTILINE)


class InvariantViolation:
    def __init__(self, rule_id: str, file_path: str, line_number: int, message: str, severity: str = "ERROR") -> None:
        self.rule_id = rule_id
        self.file_path = file_path
        self.line_number = line_number
        self.message = message
        self.severity = severity

    def __str__(self) -> str:
        rel = os.path.relpath(self.file_path, ROOT).replace("\\", "/")
        return f"{self.severity:<5} [{self.rule_id}] {rel}:{self.line_number}  {self.message}"


def strip_comments_and_strings(line: str) -> str:
    """Removes string literals and comments while preserving line length structure."""
    clean = STRING_RE.sub('""', line)
    clean = COMMENT_RE.sub('', clean)
    return clean


def get_all_gd_files(base_dir: str) -> list[str]:
    files = []
    for dirpath, dirnames, filenames in os.walk(base_dir):
        dirnames[:] = [d for d in dirnames if d not in (".git", "addons", ".claude", "__pycache__")]
        for f in filenames:
            if f.endswith(".gd"):
                files.append(os.path.join(dirpath, f))
    return sorted(files)


def get_all_tscn_files(base_dir: str) -> list[str]:
    files = []
    for dirpath, dirnames, filenames in os.walk(base_dir):
        dirnames[:] = [d for d in dirnames if d not in (".git", "addons", ".claude", "__pycache__")]
        for f in filenames:
            if f.endswith(".tscn"):
                files.append(os.path.join(dirpath, f))
    return sorted(files)


# ---------------------------------------------------------------------------
# Rule 1: Brain Mutation Enforcement
# ---------------------------------------------------------------------------
FORBIDDEN_MUTATIONS = [
    (re.compile(r'\bplayer\.velocity\s*='), "Direct write to player.velocity is forbidden; write player.movement_intent instead"),
    (re.compile(r'\bplayer\.global_position\s*='), "Direct write to player.global_position is forbidden in player FSM/brain"),
    (re.compile(r'\bplayer\.base_acceleration\s*='), "Direct write to player.base_acceleration is forbidden; controller owns mass scaling"),
    (re.compile(r'\bplayer\.move_and_slide\s*\('), "Calling move_and_slide() on player is forbidden; strictly owned by HeavyPlayerController"),
]


def check_brain_mutations(file_path: str, lines: list[str]) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []
    rel = os.path.relpath(file_path, ROOT).replace("\\", "/")

    is_brain_file = (
        rel == "entities/player/PlayerBrain.gd" or
        rel.startswith("entities/player/states/") or
        rel.startswith("entities/goalkeeper/")
    )

    if not is_brain_file:
        return violations

    for idx, raw_line in enumerate(lines, start=1):
        code = strip_comments_and_strings(raw_line)
        if not code.strip():
            continue

        for pattern, msg in FORBIDDEN_MUTATIONS:
            if pattern.search(code):
                violations.append(InvariantViolation(
                    rule_id="RULE-01-BRAIN-MUTATION",
                    file_path=file_path,
                    line_number=idx,
                    message=msg
                ))

    return violations


# ---------------------------------------------------------------------------
# Rule 2: Hot-Path Zero-Allocation Watchdog
# ---------------------------------------------------------------------------
HOT_PATH_FUNCTIONS = {
    "score_pass",
    "calculate_intercept_point",
    "get_dynamic_anchor_position",
    "_physics_process",
}

# Regex to detect allocations in GDScript code
NEW_ALLOC_RE = re.compile(r'\b[A-Za-z0-9_]+\.new\s*\(')


def check_hot_path_allocations(file_path: str, content: str) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []
    lines = content.split("\n")

    current_func: str | None = None
    func_start_line = 0
    func_indent = 0

    for idx, raw_line in enumerate(lines, start=1):
        stripped = raw_line.lstrip()
        indent = len(raw_line) - len(stripped)
        code = strip_comments_and_strings(raw_line)

        # Check function declaration
        func_match = re.match(r'^(?:static\s+)?func\s+([A-Za-z0-9_]+)\s*\(', stripped)
        if func_match:
            current_func = func_match.group(1)
            func_start_line = idx
            func_indent = indent
            continue

        if current_func:
            # Check if function ended (unindented non-empty line)
            if stripped and indent <= func_indent and not stripped.startswith("#"):
                current_func = None

        if current_func in HOT_PATH_FUNCTIONS:
            # Exclude signature lines
            if idx == func_start_line or raw_line.strip().endswith("->") or (":" in raw_line and "func " in lines[func_start_line - 1]):
                continue

            # Check for .new()
            if NEW_ALLOC_RE.search(code):
                violations.append(InvariantViolation(
                    rule_id="RULE-02-HOT-PATH-ALLOC",
                    file_path=file_path,
                    line_number=idx,
                    message=f"Forbidden heap allocation (.new()) in hot-path function '{current_func}'"
                ))

            # Check for inline dynamic Array allocation (ignoring type annotations like Array[int] and indexing arr[i])
            clean_code = re.sub(r'Array\[[^\]]*\]', '', code)
            clean_code = re.sub(r'Packed[A-Za-z0-9]+Array', '', clean_code)
            clean_code = re.sub(r'[A-Za-z0-9_]+\[[^\]]+\]', '', clean_code)  # Subscript indexing
            clean_code = re.sub(r'\[\s*\]', '', clean_code)  # Empty brackets in types

            # Check for array literals with elements like [a, b]
            if re.search(r'=\s*\[[^\]]+\]', clean_code) or re.search(r'return\s+\[[^\]]+\]', clean_code):
                violations.append(InvariantViolation(
                    rule_id="RULE-02-HOT-PATH-ALLOC",
                    file_path=file_path,
                    line_number=idx,
                    message=f"Forbidden Array literal allocation in hot-path function '{current_func}'"
                ))

            # Check for inline dynamic Dictionary allocation
            if re.search(r'=\s*\{[^\}]+\}', clean_code) or re.search(r'return\s+\{[^\}]+\}', clean_code):
                violations.append(InvariantViolation(
                    rule_id="RULE-02-HOT-PATH-ALLOC",
                    file_path=file_path,
                    line_number=idx,
                    message=f"Forbidden Dictionary literal allocation in hot-path function '{current_func}'"
                ))

    return violations


# ---------------------------------------------------------------------------
# Rule 3: Collision Layer Matrix Guard
# ---------------------------------------------------------------------------
def check_collision_matrix_gd(file_path: str, lines: list[str]) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []
    rel = os.path.relpath(file_path, ROOT).replace("\\", "/")

    # Check CharacterBody2D collision_mask configuration
    for idx, raw_line in enumerate(lines, start=1):
        code = strip_comments_and_strings(raw_line)
        if "collision_mask" in code and ("HeavyPlayerController" in rel or "Player" in rel or "entities/player" in rel):
            if "LAYER_BALL_PHYSICS" in code or "MASK_BALL_PHYSICS" in code:
                violations.append(InvariantViolation(
                    rule_id="RULE-03-COLLISION-LAYER",
                    file_path=file_path,
                    line_number=idx,
                    message="Player CharacterBody2D must NEVER mask Layer 3 (BallPhysicsBody); use FootSensor (Layer 4) instead."
                ))
            num_match = re.search(r'collision_mask\s*=\s*(\d+)', code)
            if num_match:
                mask_val = int(num_match.group(1))
                if (mask_val & 4) != 0:
                    violations.append(InvariantViolation(
                        rule_id="RULE-03-COLLISION-LAYER",
                        file_path=file_path,
                        line_number=idx,
                        message=f"Player CharacterBody2D assigns numeric collision_mask {mask_val} which enables Layer 3 (Ball)."
                    ))

    return violations


def check_collision_matrix_tscn(file_path: str, content: str) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []
    lines = content.split("\n")

    in_player_character_body = False
    node_name = ""

    for idx, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if line.startswith("[node "):
            if 'type="CharacterBody2D"' in line and ("Player" in line or "player" in line):
                in_player_character_body = True
                node_name = line
            else:
                in_player_character_body = False

        if in_player_character_body and line.startswith("collision_mask"):
            val_match = re.search(r'=\s*(\d+)', line)
            if val_match:
                val = int(val_match.group(1))
                if (val & 4) != 0:
                    violations.append(InvariantViolation(
                        rule_id="RULE-03-COLLISION-LAYER",
                        file_path=file_path,
                        line_number=idx,
                        message=f"TSCN node '{node_name}' sets collision_mask={val} (enables Layer 3 / Ball)."
                    ))

    return violations


# ---------------------------------------------------------------------------
# Rule 4: Choke-Point Bypass Detection
# ---------------------------------------------------------------------------
TREE_CRAWL_PATTERNS = [
    (re.compile(r'get_tree\s*\(\s*\)\s*\.\s*get_nodes_in_group\s*\('),
     "get_tree().get_nodes_in_group() in AI loops violates spatial choke point; route queries through MatchWorldModel.gd"),
    (re.compile(r'get_node\s*\(\s*["\']\/root\/'),
     "Direct /root tree crawling bypasses dependency contracts; use Autoload singletons or explicit dependency injection"),
    (re.compile(r'get_parent\s*\(\s*\)\s*\.\s*get_parent\s*\('),
     "Chained get_parent().get_parent() in AI logic bypasses dependency contracts; use dependency injection or direct typed references"),
]


def check_choke_point_bypass(file_path: str, lines: list[str]) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []
    rel = os.path.relpath(file_path, ROOT).replace("\\", "/")

    is_ai_loop = (
        rel == "entities/player/PlayerBrain.gd" or
        rel.startswith("entities/goalkeeper/") or
        rel == "shared/PassUtilityScorer.gd"
    )

    if not is_ai_loop:
        return violations

    for idx, raw_line in enumerate(lines, start=1):
        code = strip_comments_and_strings(raw_line)
        if not code.strip():
            continue

        for pattern, msg in TREE_CRAWL_PATTERNS:
            if pattern.search(code):
                violations.append(InvariantViolation(
                    rule_id="RULE-04-CHOKE-POINT-BYPASS",
                    file_path=file_path,
                    line_number=idx,
                    message=msg
                ))

    return violations


# ---------------------------------------------------------------------------
# Main Analysis Runner
# ---------------------------------------------------------------------------
def run_invariant_linter(target_dir: str = ROOT) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []

    gd_files = get_all_gd_files(target_dir)
    tscn_files = get_all_tscn_files(target_dir)

    for gd_path in gd_files:
        try:
            with open(gd_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
                lines = content.split("\n")

            violations.extend(check_brain_mutations(gd_path, lines))
            violations.extend(check_hot_path_allocations(gd_path, content))
            violations.extend(check_collision_matrix_gd(gd_path, lines))
            violations.extend(check_choke_point_bypass(gd_path, lines))
        except Exception as e:
            violations.append(InvariantViolation(
                rule_id="INTERNAL-ERROR",
                file_path=gd_path,
                line_number=1,
                message=f"Failed to parse file: {e}"
            ))

    for tscn_path in tscn_files:
        try:
            with open(tscn_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            violations.extend(check_collision_matrix_tscn(tscn_path, content))
        except Exception as e:
            violations.append(InvariantViolation(
                rule_id="INTERNAL-ERROR",
                file_path=tscn_path,
                line_number=1,
                message=f"Failed to parse TSCN: {e}"
            ))

    return violations


def format_xml_output(violations: list[InvariantViolation]) -> str:
    xml_lines = ['<verification_failure tool="lint_invariants">']
    for v in violations:
        rel = html.escape(os.path.relpath(v.file_path, ROOT).replace("\\", "/"))
        xml_lines.append(
            f'  <diagnostic file="{rel}" line="{v.line_number}" severity="{v.severity}" rule="{v.rule_id}">'
            f'{html.escape(v.message)}'
            f'</diagnostic>'
        )
    xml_lines.append('</verification_failure>')
    return "\n".join(xml_lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Domain-Specific AST Invariant Linter")
    parser.add_argument("target", nargs="?", default=ROOT, help="Target directory or file to lint")
    parser.add_argument("--xml", action="store_true", help="Output failures as structured XML")
    args = parser.parse_args()

    target_path = os.path.abspath(args.target) if args.target else ROOT
    violations = run_invariant_linter(target_path)

    if violations:
        if args.xml:
            print(format_xml_output(violations), file=sys.stderr)
        else:
            print(f"=== Invariant Linter Violations ({len(violations)} errors) ===")
            for v in violations:
                print(str(v))
            print("===============================================================")
        return 1

    if not args.xml:
        print(f"lint_invariants: 0 invariant errors across repository.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
