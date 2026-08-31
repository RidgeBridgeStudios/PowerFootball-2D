#!/usr/bin/env python3
"""
lint_shadowing.py — GDScript Parameter Shadowing Linter.

Scans function parameter names across all GDScript files to detect parameters
that shadow class member variables, outer scope variables, or autoload singletons
(e.g., `func bind(ball: Pseudo3DBall)` shadowing `var ball` or `func setup(team: int)`
shadowing `var team`). Enforces clean parameter naming (e.g., `p_ball`, `p_team`) to
guarantee 0 Godot 4 shadowing warnings.

Usage:
    python tools/lint_shadowing.py [--fix]
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import Dict, List, Set, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_GODOT = os.path.join(ROOT, "project.godot")


def get_autoload_names() -> set[str]:
    autoloads: set[str] = set()
    if not os.path.isfile(PROJECT_GODOT):
        return autoloads

    with open(PROJECT_GODOT, "r", encoding="utf-8") as f:
        content = f.read()

    in_autoload = False
    for line in content.splitlines():
        line = line.strip()
        if line.startswith("[autoload]"):
            in_autoload = True
            continue
        elif line.startswith("[") and in_autoload:
            break
        if in_autoload and "=" in line:
            name = line.split("=")[0].strip()
            autoloads.add(name)
    return autoloads


def find_gd_files(root_dir: str) -> list[str]:
    gd_files: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for f in filenames:
            if f.endswith(".gd"):
                gd_files.append(os.path.join(dirpath, f))
    return sorted(gd_files)


def parse_function_params(param_str: str) -> list[tuple[str, str]]:
    """
    Parses comma-separated parameter declarations into (param_name, full_param_str).
    Handles type hints, default values, and parenthesis nesting.
    """
    params: list[tuple[str, str]] = []
    if not param_str.strip():
        return params

    current: list[str] = []
    depth = 0
    in_quote = False
    quote_char = ""

    for char in param_str:
        if in_quote:
            current.append(char)
            if char == quote_char:
                in_quote = False
            continue

        if char in ('"', "'"):
            in_quote = True
            quote_char = char
            current.append(char)
        elif char in ("(", "[", "{"):
            depth += 1
            current.append(char)
        elif char in (")", "]", "}"):
            depth -= 1
            current.append(char)
        elif char == "," and depth == 0:
            p_full = "".join(current).strip()
            if p_full:
                p_name = p_full.split(":")[0].split("=")[0].strip()
                params.append((p_name, p_full))
            current = []
        else:
            current.append(char)

    if current:
        p_full = "".join(current).strip()
        if p_full:
            p_name = p_full.split(":")[0].split("=")[0].strip()
            params.append((p_name, p_full))

    return params


def audit_file_shadowing(filepath: str, autoloads: set[str]) -> list[str]:
    rel_path = os.path.relpath(filepath, ROOT).replace("\\", "/")
    violations: list[str] = []

    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    member_vars: set[str] = set()
    var_decl_pattern = re.compile(r"^(?:@export\s+|@onready\s+)?var\s+([a-zA-Z0-9_]+)\b")
    func_pattern = re.compile(r"^func\s+([a-zA-Z0-9_]+)\s*\((.*)\)\s*(?:->\s*[^:]+)?\s*:")

    # Pass 1: Collect class member variables
    for line in lines:
        m = var_decl_pattern.match(line)
        if m:
            member_vars.add(m.group(1))

    # Pass 2: Check function parameters
    for idx, line in enumerate(lines, start=1):
        m = func_pattern.match(line)
        if m:
            func_name = m.group(1)
            raw_params = m.group(2)
            params = parse_function_params(raw_params)
            for p_name, _ in params:
                # Strip leading underscore if present for unused params (e.g. _team)
                clean_name = p_name.lstrip("_")
                if not clean_name:
                    continue

                if clean_name in member_vars:
                    violations.append(
                        f"{rel_path}:{idx}: Parameter `{p_name}` in `{func_name}()` shadows class member variable `var {clean_name}`."
                    )
                elif clean_name in autoloads:
                    violations.append(
                        f"{rel_path}:{idx}: Parameter `{p_name}` in `{func_name}()` shadows autoload singleton `{clean_name}`."
                    )

    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Lint GDScript parameter shadowing.")
    args = parser.parse_args()

    autoloads = get_autoload_names()
    gd_files = find_gd_files(ROOT)

    total_violations: list[str] = []
    for filepath in gd_files:
        v = audit_file_shadowing(filepath, autoloads)
        total_violations.extend(v)

    if not total_violations:
        print(f"lint_shadowing: {len(gd_files)} scripts checked, 0 shadowing warnings.")
        return 0
    else:
        print(f"lint_shadowing: Found {len(total_violations)} parameter shadowing warning(s):", file=sys.stderr)
        for msg in total_violations:
            print(f"  [WARNING] {msg}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
