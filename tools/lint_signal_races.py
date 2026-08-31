#!/usr/bin/env python3
"""
lint_signal_races.py — Signal Emission & State Update Order Race Linter.

Audits state managers and coordinators (`autoloads/GameManager.gd`, `pitch/PitchScene.gd`,
`pitch/SetPieceCoordinator.gd`, etc.) to verify that state transition signals
(e.g., `match_phase_changed`, `goal_scored`, `kickoff_started`, `set_piece_taken`)
are strictly emitted AFTER all relevant internal state variables (phase enums, score counters,
taker slots, timers) have been updated in local memory.

Usage:
    python tools/lint_signal_races.py
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import Dict, List, Set, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Target files to audit rigorously for state transition races
CRITICAL_FILES = [
    "autoloads/GameManager.gd",
    "pitch/PitchScene.gd",
    "pitch/SetPieceCoordinator.gd",
]

# State variables that must be updated before specific state transition signals
STATE_TRANSITION_SIGNALS = {
    "match_phase_changed": {"current_phase", "phase"},
    "goal_scored": {"score", "last_scoring_team", "current_phase"},
    "kickoff_started": {"match_time", "score", "current_phase"},
    "goal_kick_started": {"set_piece_team", "set_piece_position", "current_phase"},
    "corner_kick_started": {"set_piece_team", "set_piece_position", "current_phase"},
    "throw_in_started": {"set_piece_team", "set_piece_position", "current_phase"},
    "free_kick_started": {"set_piece_team", "set_piece_position", "current_phase"},
    "penalty_started": {"set_piece_team", "set_piece_position", "current_phase"},
    "set_piece_taken": {"_active_set_piece", "is_taking", "taker"},
}


def audit_file_signal_races(rel_path: str) -> list[str]:
    filepath = os.path.join(ROOT, rel_path.replace("/", os.sep))
    if not os.path.isfile(filepath):
        return [f"File not found: {rel_path}"]

    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    violations: list[str] = []
    
    # Parse functions
    func_pattern = re.compile(r"^func\s+([a-zA-Z0-9_]+)\s*\(")
    emit_pattern = re.compile(r"(?:GameEvents\.)?([a-zA-Z0-9_]+)\.emit\(")

    current_func: str | None = None
    func_lines: list[tuple[int, str]] = []

    def check_func_block(func_name: str, block: list[tuple[int, str]]) -> None:
        # Trace statements along sequential execution paths
        # If an emit happens and a subsequent state mutation occurs in the same block without an intervening return
        for i, (emit_line, emit_str) in enumerate(block):
            stripped_emit = emit_str.strip()
            if stripped_emit.startswith("#"):
                continue
            for m in emit_pattern.finditer(stripped_emit):
                sig_name = m.group(1)
                if sig_name in STATE_TRANSITION_SIGNALS:
                    required_states = STATE_TRANSITION_SIGNALS[sig_name]
                    # Check subsequent lines until next unindented / sibling block or return
                    for j in range(i + 1, len(block)):
                        post_line_num, post_line_str = block[j]
                        stripped_post = post_line_str.strip()
                        if stripped_post.startswith("#"):
                            continue
                        if stripped_post.startswith("return"):
                            # This path ended
                            break
                        for state_var in required_states:
                            assign_re = re.compile(rf"\b{re.escape(state_var)}\b(\[[^\]]+\])?\s*(\+|-|\*|/)?=")
                            if assign_re.search(stripped_post):
                                violations.append(
                                    f"{rel_path}:{emit_line}: Signal `{sig_name}.emit()` called BEFORE internal state variable `{state_var}` assignment at line {post_line_num} in `{func_name}()`."
                                )

    for idx, line in enumerate(lines, start=1):
        m = func_pattern.match(line)
        if m:
            if current_func is not None:
                check_func_block(current_func, func_lines)
            current_func = m.group(1)
            func_lines = [(idx, line)]
        elif current_func is not None:
            # Check if out of function (indent 0 and non-empty, non-comment)
            if line.strip() and not line.startswith("\t") and not line.startswith(" ") and not line.startswith("#"):
                check_func_block(current_func, func_lines)
                current_func = None
                func_lines = []
            else:
                func_lines.append((idx, line))

    if current_func is not None:
        check_func_block(current_func, func_lines)

    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Lint GDScript coordinators for signal race conditions.")
    args = parser.parse_args()

    total_violations: list[str] = []
    for rel_path in CRITICAL_FILES:
        v = audit_file_signal_races(rel_path)
        total_violations.extend(v)

    if not total_violations:
        print(f"lint_signal_races: {len(CRITICAL_FILES)} coordinators checked, 0 signal race conditions.")
        return 0
    else:
        print(f"lint_signal_races: Found {len(total_violations)} signal race condition(s):", file=sys.stderr)
        for msg in total_violations:
            print(f"  [ERROR] {msg}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
