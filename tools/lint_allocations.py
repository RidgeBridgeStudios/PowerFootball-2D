#!/usr/bin/env python3
"""
lint_allocations.py — Allocation & Distance-Sorting Linter.

Audits GDScript files for:
1. Candidate ranking, nearest-neighbor, and distance-sorting loops enforcing
   that `distance_squared_to()` is strictly utilized instead of `distance_to()`
   to eliminate square-root calculations on critical evaluation paths.
2. Transient allocation patterns in hot paths and UI nodes (e.g., `RandomNumberGenerator.new()`
   or unbuffered arrays in per-frame methods).

Usage:
    python tools/lint_allocations.py
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import List, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def find_gd_files(root_dir: str) -> list[str]:
    gd_files: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d != "legacy" and not d.startswith(".")]
        for f in filenames:
            if f.endswith(".gd"):
                gd_files.append(os.path.join(dirpath, f))
    return sorted(gd_files)


def check_file_allocations_and_distance(filepath: str) -> list[str]:
    violations: list[str] = []
    rel_path = os.path.relpath(filepath, ROOT).replace("\\", "/")

    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Context tracking for sort_custom blocks or hot loops
    in_sort_custom = False
    sort_custom_start = 0

    in_func = False
    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue

        if stripped.startswith("func "):
            in_func = True

        # 1. Check sort_custom using distance_to
        if "sort_custom(" in line:
            in_sort_custom = True
            sort_custom_start = idx

        if in_sort_custom:
            if "distance_to(" in line:
                violations.append(
                    f"{rel_path}:{idx}: `sort_custom` sorting predicate uses `distance_to()` instead of `distance_squared_to()`."
                )
            if ")" in line and (line.endswith(")\n") or line.endswith(")") or "sort_custom" not in line):
                if line.count(")") >= line.count("("):
                    in_sort_custom = False

        # 2. Check RNG instantiation inside function bodies (indented local variables)
        if (line.startswith("\t") or line.startswith("  ")) and "RandomNumberGenerator.new()" in line:
            violations.append(
                f"{rel_path}:{idx}: Local `RandomNumberGenerator.new()` allocation detected. Use global `randf_range()`/`randi()` or persistent cached member RNG."
            )

        # 3. Check for obvious distance comparisons in candidate searches where distance_squared_to is required
        if "best_distance" in line and "distance_to(" in line:
            violations.append(
                f"{rel_path}:{idx}: Candidate distance search uses `distance_to()`. Use `distance_squared_to()` to avoid per-candidate sqrt."
            )

    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Lint GDScript files for allocation & distance_squared_to compliance.")
    args = parser.parse_args()

    gd_files = find_gd_files(ROOT)
    all_violations: list[str] = []

    for filepath in gd_files:
        v = check_file_allocations_and_distance(filepath)
        all_violations.extend(v)

    if not all_violations:
        print(f"lint_allocations: {len(gd_files)} scripts checked, 0 allocation/distance_squared errors.")
        return 0
    else:
        print(f"lint_allocations: Found {len(all_violations)} allocation/distance_squared violation(s):", file=sys.stderr)
        for msg in all_violations:
            print(f"  [ERROR] {msg}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
