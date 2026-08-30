#!/usr/bin/env python3
"""
Next Task Tool
Reads ROADMAP.md, finds the next unchecked item in 'PHASE 1 — Gameplay Completeness',
and outputs the task details and relevant file context paths.
"""

import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROADMAP_FILE = os.path.join(REPO_ROOT, "ROADMAP.md")

# Mapping of Phase 1 keywords to primary relevant file contexts
CONTEXT_MAP = {
    "injury system": [
        "shared/PlayerData.gd",
        "entities/player/HeavyPlayerController.gd",
        "entities/player/MoodSystem.gd",
        "autoloads/GameEvents.gd",
        "autoloads/DataLoader.gd",
        "docs/course_implementation_specification.md"
    ],
    "aerialstate / heading resolution": [
        "entities/player/states/AerialState.gd",
        "entities/ball/Pseudo3DBall.gd",
        "entities/player/PlayerBrain.gd",
        "entities/player/PlayerStateFactory.gd",
        "entities/player/HeavyPlayerController.gd",
        "docs/course_implementation_specification.md"
    ],
    "through-ball lead targeting": [
        "shared/PassUtilityScorer.gd",
        "shared/UtilityMath.gd",
        "entities/player/PlayerBrain.gd",
        "entities/ball/Pseudo3DBall.gd",
        "autoloads/MatchWorldModel.gd",
        "docs/course_implementation_specification.md"
    ]
}


def main() -> int:
    if not os.path.exists(ROADMAP_FILE):
        print(f"[next-task] Error: {ROADMAP_FILE} not found.", file=sys.stderr)
        return 1

    with open(ROADMAP_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    # Extract Phase 1 section
    phase1_match = re.search(r"## PHASE 1[^\n]*\n(.*?)(?=\n## PHASE 2|\Z)", content, re.DOTALL)
    if not phase1_match:
        print("[next-task] Error: Could not locate 'PHASE 1' section in ROADMAP.md", file=sys.stderr)
        return 1

    phase1_text = phase1_match.group(1)
    unchecked_items = re.findall(r"-\s*\[\s*\]\s*(.+)", phase1_text)

    if not unchecked_items:
        print("[next-task] All items in 'PHASE 1 — Gameplay Completeness' are completed [x]!")
        return 0

    next_task = unchecked_items[0].strip()
    print("=" * 60)
    print(f"[NEXT TASK] {next_task}")
    print("=" * 60)
    print(f"Remaining Phase 1 items: {len(unchecked_items)}")
    for i, item in enumerate(unchecked_items, 1):
        prefix = "-> " if i == 1 else "   "
        print(f"{prefix}{i}. {item}")

    print("\n[RELEVANT FILE CONTEXT]")
    matched_context = None
    for key, paths in CONTEXT_MAP.items():
        if key in next_task.lower():
            matched_context = paths
            break

    if matched_context:
        for p in matched_context:
            full_p = os.path.join(REPO_ROOT, p)
            status = "EXISTS" if os.path.exists(full_p) else "PENDING CREATION"
            print(f" - {p} [{status}]")
    else:
        print(" - docs/course_implementation_specification.md")
        print(" - POWERFOOTBALL_MASTER_VISION.md")
        print(" - ROADMAP.md")

    print("=" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
