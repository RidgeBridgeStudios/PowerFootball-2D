#!/usr/bin/env python3
"""
lint_stringnames.py — StringName Literal Enforcement Linter.

Audits all GDScript files across the repository to verify that invocations of
`connect()`, `emit_signal()`, `set_meta()`, `get_meta()`, and `has_meta()`
strictly use `&"string_name"` StringName literals rather than plain `"string"`
literals, eliminating per-frame string hashing and dynamic allocations.

Usage:
    python tools/lint_stringnames.py [--fix]
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import List, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Target method patterns where first argument should be a StringName if literal
TARGET_METHODS = {"connect", "emit_signal", "set_meta", "get_meta", "has_meta"}

# Regex matching target calls with a plain string literal as first argument
# e.g., set_meta("practice_mode", ...) or emit_signal("goal_scored", ...)
# Negative lookbehind (?<!&) ensures &"..." is not matched.
PATTERN_PLAIN_STRING = re.compile(
    r'(?<![&\w])\b(connect|emit_signal|set_meta|get_meta|has_meta)\s*\(\s*(["\'])(.*?)\2'
)


def find_gd_files(root_dir: str) -> list[str]:
    gd_files: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        # Ignore .godot, .git, etc. plus the archived legacy/ tree.
        dirnames[:] = [d for d in dirnames if d != "legacy" and not d.startswith(".")]
        for f in filenames:
            if f.endswith(".gd"):
                gd_files.append(os.path.join(dirpath, f))
    return sorted(gd_files)


def check_file(filepath: str, fix: bool = False) -> tuple[list[str], int]:
    violations: list[str] = []
    rel_path = os.path.relpath(filepath, ROOT).replace("\\", "/")

    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines(keepends=True)
    modified = False
    new_lines: list[str] = []

    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        # Skip pure comments
        if stripped.startswith("#"):
            new_lines.append(line)
            continue

        # Check for plain string matches
        matches = list(PATTERN_PLAIN_STRING.finditer(line))
        line_violations = []

        for m in matches:
            method_name = m.group(1)
            quote = m.group(2)
            string_val = m.group(3)
            # Ensure it's not preceded by &
            start_idx = m.start(0)
            prefix = line[:start_idx]
            
            # Additional check: avoid matching comments on the same line
            comment_idx = line.find("#")
            if comment_idx != -1 and start_idx > comment_idx:
                continue

            # If method is connect, check if it's node.connect("signal") or signal.connect(callable)
            # If the first argument is a string without &, it's invalid legacy string connection
            line_violations.append((method_name, string_val))

        if line_violations:
            for method_name, string_val in line_violations:
                violations.append(
                    f"{rel_path}:{idx}: `{method_name}(\"{string_val}\")` uses plain string literal instead of `&\"{string_val}\"`"
                )

            if fix:
                def replace_match(m: re.Match) -> str:
                    method = m.group(1)
                    quote = m.group(2)
                    val = m.group(3)
                    return f'{method}(&"{val}"'

                new_line = PATTERN_PLAIN_STRING.sub(replace_match, line)
                new_lines.append(new_line)
                modified = True
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)

    if fix and modified:
        with open(filepath, "w", encoding="utf-8", newline="\n") as f:
            f.writelines(new_lines)

    return violations, len(violations)


def main() -> int:
    parser = argparse.ArgumentParser(description="Lint GDScript files for StringName literal compliance.")
    parser.add_argument("--fix", action="store_true", help="Automatically convert plain strings to StringName literals.")
    args = parser.parse_args()

    gd_files = find_gd_files(ROOT)
    total_violations = 0
    all_violation_messages: list[str] = []

    for filepath in gd_files:
        violations, count = check_file(filepath, fix=args.fix)
        if count > 0:
            total_violations += count
            all_violation_messages.extend(violations)

    if total_violations == 0:
        print(f"lint_stringnames: {len(gd_files)} scripts checked, 0 StringName errors.")
        return 0
    else:
        print(f"lint_stringnames: Found {total_violations} StringName literal violation(s):", file=sys.stderr)
        for msg in all_violation_messages:
            print(f"  [ERROR] {msg}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
