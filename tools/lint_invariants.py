#!/usr/bin/env python3
"""
lint_invariants.py — Domain-Specific AST Invariant Linter for PowerFootball-2D.

Enforces the post-pivot, manager-only architecture described in AGENTS.md §9 and
docs/agent-errata/architecture-pivot.md: the 3-layer simulation stack, its live
choke points, and the zero-allocation hot-path rule. Every rule below is scoped
to files that exist at a live path; legacy/ is skipped by the directory walk
(and the linter fails loudly if that walk ever discovers no live file at all).

SIMULATION STACK (3 layers)
  Layer 1 — Career World
      autoloads/CareerManager.gd + DataLoader/ManagerLoader/RefereeLoader/StaffLoader,
      shared/career/*, shared/*Data.gd, shared/TeamManagementData.gd,
      shared/CareerProgressionEngine.gd.
  Layer 2 — Quick-Sim Match
      shared/QuickSimEngine.gd, shared/PlayerRatingCalculator.gd,
      shared/UtilityMath.gd, autoloads/MatchStatsTracker.gd, with GameManager as
      the scoreboard boundary the simulated result is published through.
  Layer 3 — Narrative & Presentation
      autoloads/WorldEventLog.gd, entities/manager/PressOffice.gd, ui/manager_mode/*,
      ui/MainMenu.gd, ui/OptionsMenu.gd, ui/MatchStatsUI.gd, ui/QuickSimModal.gd.

RULES ENFORCED
  RULE-01-HOT-PATH-ALLOC ....... no heap allocation inside the live UtilityMath
                                solvers that run per-candidate on hot paths.
  RULE-02-SCENE-TREE-CRAWL ..... no get_tree().get_nodes_in_group() polling,
                                no get_node("/root/...") crawling, no chained
                                get_parent() wiring in live code.
  RULE-03-SIGNAL-BUS-SURFACE ... autoloads/GameEvents.gd carries exactly its 11
                                post-pivot signals, no more and no fewer.
  RULE-04-PUBLISH-OWNERSHIP .... QuickSimEngine.apply_to_match_stats_tracker() is
                                the only writer of GameManager match state and of
                                the MatchStatsTracker container.
  RULE-05-GAMEMANAGER-SHELL .... GameManager stays the thin scoreboard shell; no
                                phase machine, clock, set-piece state or signals
                                may be reintroduced there.
  RULE-06-STATE-OWNERSHIP ...... CareerManager owns the only live CareerSaveData
                                (constructed only by its factory/serializer) and
                                DataLoader owns the league object.

RETIRED WITH THE REAL-TIME MATCH LAYER (now archived under legacy/)
  The archived files are excluded from Godot via legacy/.gdignore and skipped by
  this linter, so the pre-pivot rules could only ever pass vacuously — they were
  deleted rather than left in place:
    * Brain mutation contract — PlayerBrain.gd and entities/player/states/*.gd
      writes to player.velocity / global_position / base_acceleration, plus
      move_and_slide() ownership by HeavyPlayerController.gd.
    * Collision layer matrix guard — CharacterBody2D masking Layer 3
      (BallPhysicsBody) and shared/CollisionLayers.gd, in .gd and .tscn. Live
      scene integrity is covered by tools/tscn_linter.py.
    * Spatial-cache choke point — MatchWorldModel.gd query routing, the 15-frame
      decision stagger, and the archived AI-loop file scope
      (entities/goalkeeper/, shared/PassUtilityScorer.gd). The surviving half of
      that rule — do not wire systems by crawling the scene tree — is RULE-02.
  There is no player control, ball physics, per-frame AI or match clock left to
  lint: matches are resolved statistically by shared/QuickSimEngine.gd.

Exit code 0 on pass, 1 on invariant error.
"""

from __future__ import annotations

import argparse
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Directories that are never live game code.
SKIP_DIRS = (".git", "addons", ".claude", "__pycache__", "legacy")

# Regex utilities for GDScript code analysis
STRING_RE = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
COMMENT_RE = re.compile(r'#.*$')
FUNC_DECL_RE = re.compile(r'^(?P<indent>[ \t]*)(?:static\s+)?func\s+(?P<name>[A-Za-z0-9_]+)\s*\(')
NEW_ALLOC_RE = re.compile(r'\b[A-Za-z0-9_]+\.new\s*\(')
SIGNAL_DECL_RE = re.compile(r'^\s*signal\s+([A-Za-z_][A-Za-z0-9_]*)')


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


def repo_rel(file_path: str) -> str:
    return os.path.relpath(file_path, ROOT).replace("\\", "/")


def get_all_gd_files(base_dir: str) -> list[str]:
    files = []
    for dirpath, dirnames, filenames in os.walk(base_dir):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            if f.endswith(".gd"):
                files.append(os.path.join(dirpath, f))
    return sorted(files)


def iter_function_bodies(lines: list[str]):
    """Yields (function_name, declaration_line, [(line_number, raw_line), ...]).

    Handles multi-line GDScript signatures, and only the declaration's own body
    lines are yielded (a line at or below the declaration indent ends it).
    """
    i = 0
    total = len(lines)
    while i < total:
        match = FUNC_DECL_RE.match(lines[i])
        if not match:
            i += 1
            continue

        name = match.group("name")
        indent = len(match.group("indent").expandtabs(4))

        # Walk the (possibly multi-line) signature to its closing ':'.
        depth = 0
        j = i
        while j < total:
            sig_code = strip_comments_and_strings(lines[j])
            depth += sig_code.count("(") - sig_code.count(")")
            if depth <= 0 and sig_code.rstrip().endswith(":"):
                break
            j += 1

        body: list[tuple[int, str]] = []
        k = j + 1
        while k < total:
            raw = lines[k]
            stripped = raw.lstrip()
            if stripped:
                line_indent = len(raw) - len(stripped)
                if line_indent <= indent and not stripped.startswith("#"):
                    break
            body.append((k + 1, raw))
            k += 1

        yield name, i + 1, body
        i += 1


# ---------------------------------------------------------------------------
# Rule 1: Hot-Path Zero-Allocation Watchdog (Rule 2 pre-pivot, re-pointed)
# ---------------------------------------------------------------------------
# Live allocation-free solvers in shared/UtilityMath.gd. The retired per-frame
# names (score_pass, get_dynamic_anchor_position, _physics_process) belonged to
# the archived match engine and no longer exist at a live path.
HOT_PATH_FUNCTIONS = {
    # Bisection intercept solver, called once per candidate pass/shot.
    "calculate_intercept_point",
    # Closed-form pass lead solver, called once per pass option.
    "solve_pass_intercept",
    # Geometry primitives the solvers above are built from.
    "closest_point_on_segment",
    "distance_squared_to_segment",
    "distance_to_segment",
}


def check_hot_path_allocations(file_path: str, lines: list[str]) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []

    for func_name, _decl_line, body in iter_function_bodies(lines):
        if func_name not in HOT_PATH_FUNCTIONS:
            continue

        for lineno, raw_line in body:
            code = strip_comments_and_strings(raw_line)
            if not code.strip():
                continue

            if NEW_ALLOC_RE.search(code):
                violations.append(InvariantViolation(
                    rule_id="RULE-01-HOT-PATH-ALLOC",
                    file_path=file_path,
                    line_number=lineno,
                    message=f"Forbidden heap allocation (.new()) in hot-path solver '{func_name}'"
                ))

            # Strip type annotations, packed arrays and subscript indexing before
            # looking for dynamic Array literals.
            clean_code = re.sub(r'Array\[[^\]]*\]', '', code)
            clean_code = re.sub(r'Packed[A-Za-z0-9]+Array', '', clean_code)
            clean_code = re.sub(r'[A-Za-z0-9_]+\[[^\]]+\]', '', clean_code)
            clean_code = re.sub(r'\[\s*\]', '', clean_code)

            if re.search(r'=\s*\[[^\]]+\]', clean_code) or re.search(r'return\s+\[[^\]]+\]', clean_code):
                violations.append(InvariantViolation(
                    rule_id="RULE-01-HOT-PATH-ALLOC",
                    file_path=file_path,
                    line_number=lineno,
                    message=f"Forbidden Array literal allocation in hot-path solver '{func_name}'"
                ))

            if re.search(r'=\s*\{[^\}]+\}', clean_code) or re.search(r'return\s+\{[^\}]+\}', clean_code):
                violations.append(InvariantViolation(
                    rule_id="RULE-01-HOT-PATH-ALLOC",
                    file_path=file_path,
                    line_number=lineno,
                    message=f"Forbidden Dictionary literal allocation in hot-path solver '{func_name}'"
                ))

    return violations


# ---------------------------------------------------------------------------
# Rule 2: Scene-Tree Crawl Guard (Rule 4 pre-pivot, re-pointed)
# ---------------------------------------------------------------------------
# Pre-pivot this enforced the MatchWorldModel spatial cache. The cache is
# archived; what remains true is that live systems are wired through autoloads,
# explicit references and GameEvents — not by polling or crawling the tree.
TREE_CRAWL_PATTERNS = [
    (re.compile(r'get_tree\s*\(\s*\)\s*\.\s*get_nodes_in_group\s*\('),
     "Scene-tree polling (get_tree().get_nodes_in_group()) bypasses the autoload/signal-bus contracts; hold an explicit reference or react to a GameEvents signal"),
    (re.compile(r'get_parent\s*\(\s*\)\s*\.\s*get_parent\s*\('),
     "Chained get_parent().get_parent() couples a script to a scene layout; pass the dependency in or use an autoload"),
]

# This pattern lives inside the node path string, so it must be matched against
# the comment-stripped line BEFORE strip_comments_and_strings blanks the literal.
ROOT_CRAWL_RE = re.compile(r'get_node(?:_or_null)?\s*\(\s*["\']\/root\/')
ROOT_CRAWL_MESSAGE = (
    "Crawling get_node(\"/root/...\") bypasses dependency injection; use the autoload singleton directly or pass the dependency in"
)


def check_scene_tree_crawl(file_path: str, lines: list[str]) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []

    for idx, raw_line in enumerate(lines, start=1):
        comment_stripped = COMMENT_RE.sub('', raw_line)
        if not comment_stripped.strip():
            continue

        if ROOT_CRAWL_RE.search(comment_stripped):
            violations.append(InvariantViolation(
                rule_id="RULE-02-SCENE-TREE-CRAWL",
                file_path=file_path,
                line_number=idx,
                message=ROOT_CRAWL_MESSAGE
            ))

        code = strip_comments_and_strings(raw_line)
        if not code.strip():
            continue

        for pattern, msg in TREE_CRAWL_PATTERNS:
            if pattern.search(code):
                violations.append(InvariantViolation(
                    rule_id="RULE-02-SCENE-TREE-CRAWL",
                    file_path=file_path,
                    line_number=idx,
                    message=msg
                ))

    return violations


# ---------------------------------------------------------------------------
# Rule 3: Signal Bus Surface Guard
# ---------------------------------------------------------------------------
GAME_EVENTS_PATH = "autoloads/GameEvents.gd"
GAME_EVENTS_SIGNALS = (
    "formation_changed",
    "lineup_changed",
    "career_started",
    "career_day_advanced",
    "career_advance_halted",
    "career_continue_started",
    "career_continue_stopped",
    "career_speed_changed",
    "career_inbox_changed",
    "career_match_ready",
    "career_result_recorded",
    "career_season_ended",
    "career_manager_sacked",
    "world_event_logged",
)


def check_signal_bus_surface(file_path: str, lines: list[str]) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []

    if repo_rel(file_path) != GAME_EVENTS_PATH:
        return violations

    declared: dict[str, int] = {}
    for idx, raw_line in enumerate(lines, start=1):
        match = SIGNAL_DECL_RE.match(strip_comments_and_strings(raw_line))
        if match:
            declared[match.group(1)] = idx

    for name, lineno in sorted(declared.items(), key=lambda item: item[1]):
        if name not in GAME_EVENTS_SIGNALS:
            violations.append(InvariantViolation(
                rule_id="RULE-03-SIGNAL-BUS-SURFACE",
                file_path=file_path,
                line_number=lineno,
                message=(
                    f"'{name}' is not part of the post-pivot GameEvents contract. Match-engine signals were "
                    "retired with the real-time layer; append a career/presentation signal deliberately and "
                    "update the canonical 11-signal list with it."
                )
            ))

    for name in GAME_EVENTS_SIGNALS:
        if name not in declared:
            violations.append(InvariantViolation(
                rule_id="RULE-03-SIGNAL-BUS-SURFACE",
                file_path=file_path,
                line_number=1,
                message=f"GameEvents lost the required signal '{name}'; the signal bus is a fixed cross-layer contract.",
            ))

    return violations


# ---------------------------------------------------------------------------
# Rule 4: Quick-Sim Publishing Ownership
# ---------------------------------------------------------------------------
QUICK_SIM_ENGINE_PATH = "shared/QuickSimEngine.gd"
MATCH_STATS_TRACKER_PATH = "autoloads/MatchStatsTracker.gd"
GAME_MANAGER_PATH = "autoloads/GameManager.gd"

GAME_MANAGER_MATCH_FIELDS = (
    "score",
    "current_phase",
    "match_time",
    "match_duration",
    "half_duration_real_sec",
    "simulated_match_time",
)
GAME_MANAGER_STATE_WRITE_RE = re.compile(
    r'\bGameManager\.(?:' + "|".join(GAME_MANAGER_MATCH_FIELDS) + r')\s*(?:\[[^\]]*\]\s*)?(?:[+\-*/%|]?=)(?!=)'
)
MATCH_STATS_WRITE_RE = re.compile(
    r'\bMatchStatsTracker\.[A-Za-z_][A-Za-z0-9_]*\s*(?:\[[^\]]*\]\s*)?(?:[+\-*/%|]?=)(?!=)'
)
MATCH_STATS_MUTATOR_RE = re.compile(r'\bMatchStatsTracker\.(?:reset|stop_possession_sampling)\s*\(')


def check_publish_ownership(file_path: str, lines: list[str]) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []
    rel = repo_rel(file_path)

    may_write_game_manager = rel in (QUICK_SIM_ENGINE_PATH, GAME_MANAGER_PATH)
    may_write_match_stats = rel in (QUICK_SIM_ENGINE_PATH, MATCH_STATS_TRACKER_PATH)

    for idx, raw_line in enumerate(lines, start=1):
        code = strip_comments_and_strings(raw_line)
        if not code.strip():
            continue

        if not may_write_game_manager and GAME_MANAGER_STATE_WRITE_RE.search(code):
            violations.append(InvariantViolation(
                rule_id="RULE-04-PUBLISH-OWNERSHIP",
                file_path=file_path,
                line_number=idx,
                message=(
                    "Only QuickSimEngine.apply_to_match_stats_tracker() may publish a simulated result into "
                    "GameManager (score / current_phase / match_time / simulated_match_time)."
                )
            ))

        if not may_write_match_stats and (
            MATCH_STATS_WRITE_RE.search(code) or MATCH_STATS_MUTATOR_RE.search(code)
        ):
            violations.append(InvariantViolation(
                rule_id="RULE-04-PUBLISH-OWNERSHIP",
                file_path=file_path,
                line_number=idx,
                message=(
                    "MatchStatsTracker is a passive container: only QuickSimEngine.apply_to_match_stats_tracker() "
                    "writes a simulated result into it. Presentation code reads it back."
                )
            ))

    return violations


# ---------------------------------------------------------------------------
# Rule 5: GameManager Thin-Shell Guard
# ---------------------------------------------------------------------------
GAME_MANAGER_ALLOWED_CONSTS = {"TEAM_A", "TEAM_B", "SIMULATED_MATCH_DURATION"}
GAME_MANAGER_ALLOWED_VARS = {
    "current_phase",
    "score",
    "match_time",
    "half_duration_real_sec",
    "match_duration",
    "simulated_match_time",
}
GAME_MANAGER_ALLOWED_FUNCS = {"set_half_duration"}
GAME_MANAGER_ALLOWED_ENUMS = {"MatchPhase": ("PREGAME", "FULL_TIME")}

GM_VAR_RE = re.compile(r'^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*var\s+([A-Za-z_][A-Za-z0-9_]*)')
GM_CONST_RE = re.compile(r'^\s*const\s+([A-Za-z_][A-Za-z0-9_]*)')
GM_FUNC_RE = re.compile(r'^\s*(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(')
GM_SIGNAL_RE = re.compile(r'^\s*signal\s+([A-Za-z_][A-Za-z0-9_]*)')
GM_ENUM_RE = re.compile(r'^\s*enum\s+([A-Za-z_][A-Za-z0-9_]*)')
ENUM_BLOCK_RE = re.compile(r'\benum\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{([^}]*)\}', re.DOTALL)


def _enum_members(body: str) -> list[str]:
    members: list[str] = []
    for segment in body.split(","):
        match = re.match(r'\s*([A-Za-z_][A-Za-z0-9_]*)', segment)
        if match:
            members.append(match.group(1))
    return members


def check_game_manager_thin_shell(file_path: str, lines: list[str]) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []

    if repo_rel(file_path) != GAME_MANAGER_PATH:
        return violations

    for idx, raw_line in enumerate(lines, start=1):
        code = strip_comments_and_strings(raw_line)
        if not code.strip():
            continue

        match = GM_SIGNAL_RE.match(code)
        if match:
            violations.append(InvariantViolation(
                rule_id="RULE-05-GAMEMANAGER-SHELL",
                file_path=file_path,
                line_number=idx,
                message=(
                    f"GameManager must not declare signals ('{match.group(1)}'): cross-system events belong on "
                    "GameEvents, the single signal bus."
                )
            ))
            continue

        match = GM_VAR_RE.match(code)
        if match and match.group(1) not in GAME_MANAGER_ALLOWED_VARS:
            violations.append(InvariantViolation(
                rule_id="RULE-05-GAMEMANAGER-SHELL",
                file_path=file_path,
                line_number=idx,
                message=(
                    f"'{match.group(1)}' is outside the GameManager thin-shell surface. The retired per-frame "
                    "match machinery (clock, set-piece state, phase machine) must not come back here; put live "
                    "match state in QuickSimEngine/MatchStatsTracker."
                )
            ))
            continue

        match = GM_CONST_RE.match(code)
        if match and match.group(1) not in GAME_MANAGER_ALLOWED_CONSTS:
            violations.append(InvariantViolation(
                rule_id="RULE-05-GAMEMANAGER-SHELL",
                file_path=file_path,
                line_number=idx,
                message=f"'{match.group(1)}' is outside the GameManager thin-shell surface."
            ))
            continue

        match = GM_FUNC_RE.match(code)
        if match and match.group(1) not in GAME_MANAGER_ALLOWED_FUNCS:
            violations.append(InvariantViolation(
                rule_id="RULE-05-GAMEMANAGER-SHELL",
                file_path=file_path,
                line_number=idx,
                message=(
                    f"'{match.group(1)}()' is outside the GameManager thin-shell surface. Only "
                    "set_half_duration() survives; match behaviour belongs to QuickSimEngine."
                )
            ))
            continue

        match = GM_ENUM_RE.match(code)
        if match and match.group(1) not in GAME_MANAGER_ALLOWED_ENUMS:
            violations.append(InvariantViolation(
                rule_id="RULE-05-GAMEMANAGER-SHELL",
                file_path=file_path,
                line_number=idx,
                message=(
                    f"enum '{match.group(1)}' is outside the GameManager thin-shell surface; the only surviving "
                    "phase model is enum MatchPhase { PREGAME, FULL_TIME }."
                )
            ))

    # MatchPhase must keep exactly its two post-pivot states.
    cleaned = "\n".join(strip_comments_and_strings(line) for line in lines)
    for enum_match in ENUM_BLOCK_RE.finditer(cleaned):
        enum_name = enum_match.group(1)
        if enum_name not in GAME_MANAGER_ALLOWED_ENUMS:
            continue
        expected = GAME_MANAGER_ALLOWED_ENUMS[enum_name]
        members = _enum_members(enum_match.group(2))
        for member in members:
            if member not in expected:
                violations.append(InvariantViolation(
                    rule_id="RULE-05-GAMEMANAGER-SHELL",
                    file_path=file_path,
                    line_number=1,
                    message=f"MatchPhase gained state '{member}'; the post-pivot phase model is exactly PREGAME and FULL_TIME."
                ))
        for member in expected:
            if member not in members:
                violations.append(InvariantViolation(
                    rule_id="RULE-05-GAMEMANAGER-SHELL",
                    file_path=file_path,
                    line_number=1,
                    message=f"MatchPhase lost state '{member}'; GameManager.MatchPhase is a fixed two-state contract."
                ))

    return violations


# ---------------------------------------------------------------------------
# Rule 6: Career / League State Ownership
# ---------------------------------------------------------------------------
CAREER_SAVE_DATA_PATH = "shared/career/CareerSaveData.gd"
CAREER_SERIALIZER_PATH = "shared/career/CareerSerializer.gd"
DATA_LOADER_PATH = "autoloads/DataLoader.gd"

CAREER_SAVE_CTOR_RE = re.compile(r'\bCareerSaveData\.new\s*\(')
LEAGUE_ASSIGN_RE = re.compile(r'\bDataLoader\.league\s*(?:\[[^\]]*\]\s*)?(?:[+\-*/%|]?=)(?!=)')


def check_state_ownership(file_path: str, lines: list[str]) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []
    rel = repo_rel(file_path)

    may_construct_career = rel in (CAREER_SAVE_DATA_PATH, CAREER_SERIALIZER_PATH)
    may_assign_league = rel == DATA_LOADER_PATH

    for idx, raw_line in enumerate(lines, start=1):
        code = strip_comments_and_strings(raw_line)
        if not code.strip():
            continue

        if not may_construct_career and CAREER_SAVE_CTOR_RE.search(code):
            violations.append(InvariantViolation(
                rule_id="RULE-06-STATE-OWNERSHIP",
                file_path=file_path,
                line_number=idx,
                message=(
                    "CareerManager owns the ONLY live CareerSaveData. Build one through CareerSaveData.make_new() "
                    "from CareerManager, or CareerSerializer.load_from_slot(); never construct a second save state."
                )
            ))

        if not may_assign_league and LEAGUE_ASSIGN_RE.search(code):
            violations.append(InvariantViolation(
                rule_id="RULE-06-STATE-OWNERSHIP",
                file_path=file_path,
                line_number=idx,
                message=(
                    "DataLoader owns DataLoader.league (squads, staff, attributes); only DataLoader may replace it, "
                    "and it is saved per slot via DataLoader.save_league()."
                )
            ))

    return violations


# ---------------------------------------------------------------------------
# Main Analysis Runner
# ---------------------------------------------------------------------------
RULE_CHECKS = (
    check_hot_path_allocations,
    check_scene_tree_crawl,
    check_signal_bus_surface,
    check_publish_ownership,
    check_game_manager_thin_shell,
    check_state_ownership,
)


def run_invariant_linter(target_dir: str = ROOT) -> list[InvariantViolation]:
    violations: list[InvariantViolation] = []

    gd_files = get_all_gd_files(target_dir)

    # Self-integrity guard: a skip list that swallows the whole repository would
    # otherwise let every rule pass vacuously — the exact failure this linter
    # exists to prevent.
    if not gd_files:
        violations.append(InvariantViolation(
            rule_id="INTERNAL-ERROR",
            file_path=os.path.join(target_dir, "<scan>"),
            line_number=1,
            message=f"No live .gd files discovered under {target_dir}; the skip list is swallowing the repository.",
        ))
        return violations

    for gd_path in gd_files:
        try:
            with open(gd_path, "r", encoding="utf-8", errors="replace") as f:
                lines = f.read().split("\n")

            for check in RULE_CHECKS:
                violations.extend(check(gd_path, lines))
        except Exception as e:
            violations.append(InvariantViolation(
                rule_id="INTERNAL-ERROR",
                file_path=gd_path,
                line_number=1,
                message=f"Failed to parse file: {e}"
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
    scanned = len(get_all_gd_files(target_path))
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
        print(
            f"lint_invariants: 0 invariant errors across {scanned} live .gd files "
            f"({len(RULE_CHECKS)} rules active; legacy/ skipped)."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
