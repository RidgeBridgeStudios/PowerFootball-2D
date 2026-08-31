#!/usr/bin/env python3
"""
audit_process_modes.py — Process Mode Consistency Auditor.

Audits all `.gd` and `.tscn` files to verify that:
1. Singleton coordinators and UI menus (`GameManager.gd`, `MatchStatsTracker.gd`,
   `MatchWorldModel.gd`, `HUD.gd`, `PauseMenu.gd`) set `process_mode = PROCESS_MODE_ALWAYS` (or mode 3)
   to ensure clean execution while the game is paused.
2. Gameplay entities (`HeavyPlayerController.gd`, `Pseudo3DBall.gd`, `PlayerBrain.gd`)
   remain pausable (`PROCESS_MODE_PAUSABLE` or mode 0/Inherit) so match pausing freezes on-pitch action.

Usage:
    python tools/audit_process_modes.py
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import List, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ALWAYS_COORDINATORS = [
    "autoloads/GameManager.gd",
    "autoloads/MatchStatsTracker.gd",
    "autoloads/MatchWorldModel.gd",
    "ui/HUD.gd",
    "ui/pause/PauseMenu.gd",
]

PAUSABLE_ENTITIES = [
    "entities/player/HeavyPlayerController.gd",
    "entities/ball/Pseudo3DBall.gd",
    "entities/player/PlayerBrain.gd",
]


def audit_process_modes() -> list[str]:
    violations: list[str] = []

    # 1. Verify ALWAYS coordinators
    for rel_path in ALWAYS_COORDINATORS:
        filepath = os.path.join(ROOT, rel_path.replace("/", os.sep))
        if not os.path.isfile(filepath):
            violations.append(f"Coordinator script not found: {rel_path}")
            continue

        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()

        # Check for process_mode = Node.PROCESS_MODE_ALWAYS or process_mode = PROCESS_MODE_ALWAYS or process_mode = 3
        has_always = bool(
            re.search(r"process_mode\s*=\s*(?:Node\.)?PROCESS_MODE_ALWAYS", content)
            or re.search(r"process_mode\s*=\s*3", content)
        )
        if not has_always:
            violations.append(
                f"{rel_path}: Missing `process_mode = Node.PROCESS_MODE_ALWAYS` in singleton/UI coordinator."
            )

    # 2. Verify PAUSABLE entities do not erroneously set PROCESS_MODE_ALWAYS
    for rel_path in PAUSABLE_ENTITIES:
        filepath = os.path.join(ROOT, rel_path.replace("/", os.sep))
        if not os.path.isfile(filepath):
            violations.append(f"Gameplay entity script not found: {rel_path}")
            continue

        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()

        has_always = bool(
            re.search(r"process_mode\s*=\s*(?:Node\.)?PROCESS_MODE_ALWAYS", content)
            or re.search(r"process_mode\s*=\s*3", content)
        )
        if has_always:
            violations.append(
                f"{rel_path}: Gameplay entity erroneously configured with `PROCESS_MODE_ALWAYS`; must remain pausable."
            )

    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit process_mode configurations.")
    args = parser.parse_args()

    violations = audit_process_modes()

    if not violations:
        print(f"audit_process_modes: {len(ALWAYS_COORDINATORS) + len(PAUSABLE_ENTITIES)} target components verified, 0 process_mode errors.")
        return 0
    else:
        print(f"audit_process_modes: Found {len(violations)} process_mode violation(s):", file=sys.stderr)
        for msg in violations:
            print(f"  [ERROR] {msg}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
