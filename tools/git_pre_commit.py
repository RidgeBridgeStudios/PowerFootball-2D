#!/usr/bin/env python3
"""
git_pre_commit.py — Git Pre-Commit Hook Installer & Runner.

Executes the repository verification suite:
1. `tools/gdcheck.py` (Strict GDScript typing & syntax linter)
2. `tools/lint_invariants.py` (Architecture AST invariant linter)
3. `tools/tscn_linter.py` (Scene graph & node linter)
4. `tools/lint_stringnames.py` (StringName literal linter)
5. `tools/lint_shadowing.py` (Parameter shadowing linter)
6. `tools/verify_db.py` (Database schema & integrity checker)

Usage:
    python tools/git_pre_commit.py            # Runs all checks
    python tools/git_pre_commit.py --install  # Installs git pre-commit hook
"""

from __future__ import annotations

import argparse
import os
import stat
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GIT_HOOKS_DIR = os.path.join(ROOT, ".git", "hooks")
PRE_COMMIT_HOOK_PATH = os.path.join(GIT_HOOKS_DIR, "pre-commit")

CHECKS = [
    ("Unified Fast Verification Gate", [sys.executable, os.path.join(ROOT, "tools", "verify_gate.py"), "--fast"]),
    ("Godot Engine Headless Verification", [sys.executable, os.path.join(ROOT, "tools", "godot_verify.py")]),
]


def install_hook() -> int:
    if not os.path.isdir(os.path.join(ROOT, ".git")):
        print("Error: .git directory not found. Not a git repository root.", file=sys.stderr)
        return 1

    os.makedirs(GIT_HOOKS_DIR, exist_ok=True)

    hook_content = (
        "#!/bin/sh\n"
        "# PowerFootball-2D automated pre-commit verification hook\n"
        "python3 tools/git_pre_commit.py || python tools/git_pre_commit.py || py -3 tools/git_pre_commit.py\n"
    )

    with open(PRE_COMMIT_HOOK_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write(hook_content)

    # Set executable permissions on POSIX
    try:
        st = os.stat(PRE_COMMIT_HOOK_PATH)
        os.chmod(PRE_COMMIT_HOOK_PATH, st.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    except Exception:
        pass

    print(f"[OK] Pre-commit hook installed successfully -> {os.path.relpath(PRE_COMMIT_HOOK_PATH, ROOT)}")
    return 0


def run_checks() -> int:
    print("=== PowerFootball-2D Pre-Commit Verification Suite ===\n")
    failed_checks = []

    for name, cmd in CHECKS:
        print(f"[Running] {name}...")
        res = subprocess.run(cmd, cwd=ROOT)
        if res.returncode != 0:
            print(f"  -> [FAILED] {name}\n", file=sys.stderr)
            failed_checks.append(name)
        else:
            print(f"  -> [PASSED] {name}\n")

    if not failed_checks:
        print("=== All Pre-Commit Checks Passed (0 errors) ===")
        return 0
    else:
        print(f"=== Verification FAILED ({len(failed_checks)} check(s) failed) ===", file=sys.stderr)
        for fc in failed_checks:
            print(f"  - {fc}", file=sys.stderr)
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Git pre-commit runner and installer.")
    parser.add_argument("--install", action="store_true", help="Install git pre-commit hook into .git/hooks/pre-commit.")
    args = parser.parse_args()

    if args.install:
        return install_hook()
    return run_checks()


if __name__ == "__main__":
    sys.exit(main())
