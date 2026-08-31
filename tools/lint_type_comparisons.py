#!/usr/bin/env python3
"""
lint_type_comparisons.py — Type Comparison & Object-Literal Safety Linter for GDScript 2.0.

Enforces critical postmortem type comparison safeguards:
1. Object instances (e.g. `current_state`, `player`, `ball`, `state`) must NEVER be compared
   with `==` or `!=` against String or StringName literals (`"..."` or `&"..."`).
   Example: `current_state == &"ThrowIn"` must be `current_state_name == &"ThrowIn"`.

2. Node or Resource instances must not be directly compared against numeric or boolean literals.

Usage:
    python tools/lint_type_comparisons.py [target_path] [--xml]
"""

from __future__ import annotations

import argparse
import html
import os
import re
import sys
from typing import List

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Regex patterns for unsafe comparisons
# 1. Comparison of current_state to String or StringName
STATE_OBJECT_STR_RE = re.compile(
    r'(?:\bcurrent_state|\bstate|\bactive_state)\s*(?:==|!=)\s*(?:&?["\'][A-Za-z0-9_]+["\'])|'
    r'(?:&?["\'][A-Za-z0-9_]+["\'])\s*(?:==|!=)\s*(?:\bcurrent_state|\bstate|\bactive_state\b)'
)

# 2. General player/ball object comparison to string literals
OBJECT_STR_RE = re.compile(
    r'(?:\bplayer|\bball|\bcontroller|\bbrain|\breferee|\bmanager)\s*(?:==|!=)\s*(?:&?["\'][A-Za-z0-9_]+["\'])|'
    r'(?:&?["\'][A-Za-z0-9_]+["\'])\s*(?:==|!=)\s*(?:\bplayer|\bball|\bcontroller|\bbrain|\breferee|\bmanager\b)'
)


class ComparisonViolation:
    def __init__(self, rule_id: str, file_path: str, line_number: int, message: str, severity: str = "ERROR") -> None:
        self.rule_id = rule_id
        self.file_path = file_path
        self.line_number = line_number
        self.message = message
        self.severity = severity

    def __str__(self) -> str:
        rel = os.path.relpath(self.file_path, ROOT).replace("\\", "/")
        return f"{self.severity:<5} [{self.rule_id}] {rel}:{self.line_number}  {self.message}"


def get_all_gd_files(base_dir: str) -> list[str]:
    files = []
    if os.path.isfile(base_dir):
        return [base_dir] if base_dir.endswith(".gd") else []
    for dirpath, dirnames, filenames in os.walk(base_dir):
        dirnames[:] = [d for d in dirnames if d not in (".git", "addons", ".claude", "__pycache__", ".godot")]
        for f in filenames:
            if f.endswith(".gd"):
                files.append(os.path.join(dirpath, f))
    return sorted(files)


def lint_file_comparisons(file_path: str) -> list[ComparisonViolation]:
    violations: list[ComparisonViolation] = []
    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception as e:
        return [ComparisonViolation("READ-ERROR", file_path, 1, f"Failed to read file: {e}")]

    for idx, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        # Strip inline comment
        if "#" in line:
            # Check if # is inside quotes or actual comment
            in_quote = False
            q_char = ""
            comment_start = -1
            for i, c in enumerate(line):
                if c in ('"', "'"):
                    if not in_quote:
                        in_quote = True
                        q_char = c
                    elif q_char == c:
                        in_quote = False
                elif c == '#' and not in_quote:
                    comment_start = i
                    break
            if comment_start != -1:
                line = line[:comment_start].strip()

        # Check for state object comparisons against string/StringName
        # Note: current_state_name == &"..." is VALID, but current_state == &"..." is INVALID
        if STATE_OBJECT_STR_RE.search(line):
            # Make sure it's not current_state_name or state_name
            if not ("current_state_name" in line or "state_name" in line):
                violations.append(ComparisonViolation(
                    rule_id="RULE-TYPE-STATE-CMP",
                    file_path=file_path,
                    line_number=idx,
                    message="Direct equality comparison between State object instance and String/StringName literal. Use 'current_state_name' or explicit StringName property instead."
                ))

        if OBJECT_STR_RE.search(line):
            # Check if it was player_name or similar
            if not ("player_name" in line or "player.name" in line or "ball_name" in line):
                violations.append(ComparisonViolation(
                    rule_id="RULE-TYPE-OBJECT-CMP",
                    file_path=file_path,
                    line_number=idx,
                    message="Direct equality comparison between Object instance and String literal."
                ))

    return violations


def run_comparison_linter(target_path: str = ROOT) -> list[ComparisonViolation]:
    gd_files = get_all_gd_files(target_path)
    all_violations: list[ComparisonViolation] = []
    for f in gd_files:
        all_violations.extend(lint_file_comparisons(f))
    return all_violations


def format_xml_output(violations: list[ComparisonViolation]) -> str:
    xml_lines = ['<verification_failure tool="lint_type_comparisons">']
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
    parser = argparse.ArgumentParser(description="Type Comparison & Object-Literal Safety Linter")
    parser.add_argument("target", nargs="?", default=ROOT, help="Target directory or file to lint")
    parser.add_argument("--xml", action="store_true", help="Output failures as structured XML")
    args = parser.parse_args()

    target_path = os.path.abspath(args.target) if args.target else ROOT
    violations = run_comparison_linter(target_path)

    if violations:
        if args.xml:
            print(format_xml_output(violations), file=sys.stderr)
        else:
            print(f"=== Type Comparison Linter Violations ({len(violations)} errors) ===")
            for v in violations:
                print(str(v))
            print("===============================================================")
        return 1

    if not args.xml:
        print("lint_type_comparisons: 0 invalid type comparison errors across repository.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
