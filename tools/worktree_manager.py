#!/usr/bin/env python3
"""
worktree_manager.py — Isolated Git Worktree Sandbox & Verification Manager.

Automates isolated git worktree lifecycle for feature development:
- create: Provision an isolated worktree branch in .worktrees/<branch>
- verify: Execute static verification and invariant gates inside worktree
- merge: Run verification gate, merge into base branch, and cleanup
- cleanup: Safely prune and remove worktree directories
- list: List active worktrees and branch states

Usage:
    python tools/worktree_manager.py list
    python tools/worktree_manager.py create feature/aerial-contest
    python tools/worktree_manager.py verify feature/aerial-contest
    python tools/worktree_manager.py merge feature/aerial-contest
    python tools/worktree_manager.py cleanup feature/aerial-contest
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from typing import List, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKTREES_BASE = os.path.join(ROOT, ".worktrees")


def run_cmd(cmd: list[str], cwd: str = ROOT) -> tuple[int, str, str]:
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def cmd_list() -> int:
    code, stdout, stderr = run_cmd(["git", "worktree", "list"])
    print("\n" + "=" * 65)
    print("                 ACTIVE GIT WORKTREES                 ")
    print("=" * 65)
    if code == 0 and stdout:
        for line in stdout.splitlines():
            print(f"  {line}")
    else:
        print("  No secondary worktrees active.")
    print("=" * 65 + "\n")
    return code


def cmd_create(branch_name: str) -> int:
    sanitized = branch_name.replace("/", "-").replace("\\", "-")
    target_dir = os.path.join(WORKTREES_BASE, sanitized)

    os.makedirs(WORKTREES_BASE, exist_ok=True)
    print(f"[worktree] Creating worktree for '{branch_name}' at {os.path.relpath(target_dir, ROOT)}...")

    # Check if branch exists
    code, _, _ = run_cmd(["git", "show-ref", "--verify", f"refs/heads/{branch_name}"])
    if code == 0:
        # Branch exists
        c, out, err = run_cmd(["git", "worktree", "add", target_dir, branch_name])
    else:
        # Create new branch
        c, out, err = run_cmd(["git", "worktree", "add", "-b", branch_name, target_dir])

    if c == 0:
        print(f"[worktree] Successfully created worktree -> {target_dir}")
        return 0
    else:
        print(f"[worktree] Error creating worktree: {err or out}", file=sys.stderr)
        return c


def cmd_verify(branch_name: str) -> int:
    sanitized = branch_name.replace("/", "-").replace("\\", "-")
    target_dir = os.path.join(WORKTREES_BASE, sanitized)

    worktree_path = target_dir if os.path.exists(target_dir) else ROOT
    print(f"[worktree] Running verification suite in {os.path.relpath(worktree_path, ROOT)}...")

    checks = [
        ("GDScript Static Analysis", [sys.executable, os.path.join(worktree_path, "tools", "gdcheck.py")]),
        ("Domain Invariant Linter", [sys.executable, os.path.join(worktree_path, "tools", "lint_invariants.py")]),
        ("TSCN Scene Linter", [sys.executable, os.path.join(worktree_path, "tools", "tscn_linter.py")]),
        ("Schema Validation", [sys.executable, os.path.join(worktree_path, "tools", "validate_schemas.py")]),
    ]

    all_passed = True
    for name, cmd in checks:
        if not os.path.exists(cmd[1]):
            continue
        c, out, err = run_cmd(cmd, cwd=worktree_path)
        status = "PASSED" if c == 0 else "FAILED"
        print(f"  [{status}] {name}")
        if c != 0:
            all_passed = False
            if out:
                print(f"    STDOUT: {out}")
            if err:
                print(f"    STDERR: {err}")

    if all_passed:
        print("\n[worktree] All verification checks passed with 0 errors.\n")
        return 0
    else:
        print("\n[worktree] Verification failed. Resolve errors before merging.\n", file=sys.stderr)
        return 1


def cmd_merge(branch_name: str) -> int:
    print(f"[worktree] Running pre-merge verification for '{branch_name}'...")
    if cmd_verify(branch_name) != 0:
        print(f"[worktree] Merge aborted: verification failed.", file=sys.stderr)
        return 1

    print(f"[worktree] Merging '{branch_name}' into current branch...")
    c, out, err = run_cmd(["git", "merge", branch_name])
    if c != 0:
        print(f"[worktree] Error during git merge: {err or out}", file=sys.stderr)
        return c

    print(f"[worktree] Successfully merged '{branch_name}'.")
    return cmd_cleanup(branch_name)


def cmd_cleanup(branch_name: str) -> int:
    sanitized = branch_name.replace("/", "-").replace("\\", "-")
    target_dir = os.path.join(WORKTREES_BASE, sanitized)

    print(f"[worktree] Cleaning up worktree for '{branch_name}'...")
    if os.path.exists(target_dir):
        run_cmd(["git", "worktree", "remove", "--force", target_dir])
        if os.path.exists(target_dir):
            shutil.rmtree(target_dir, ignore_errors=True)

    run_cmd(["git", "worktree", "prune"])
    print(f"[worktree] Cleanup complete.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Git Worktree Sandbox & Verification Manager")
    subparsers = parser.add_subparsers(dest="action", help="Worktree action")

    subparsers.add_parser("list", help="List active worktrees")

    create_parser = subparsers.add_parser("create", help="Create isolated worktree branch")
    create_parser.add_argument("branch", help="Branch name to create")

    verify_parser = subparsers.add_parser("verify", help="Verify worktree")
    verify_parser.add_argument("branch", help="Branch name to verify")

    merge_parser = subparsers.add_parser("merge", help="Verify and merge worktree")
    merge_parser.add_argument("branch", help="Branch name to merge")

    cleanup_parser = subparsers.add_parser("cleanup", help="Remove worktree")
    cleanup_parser.add_argument("branch", help="Branch name to cleanup")

    args = parser.parse_args()

    if args.action == "list" or not args.action:
        return cmd_list()
    elif args.action == "create":
        return cmd_create(args.branch)
    elif args.action == "verify":
        return cmd_verify(args.branch)
    elif args.action == "merge":
        return cmd_merge(args.branch)
    elif args.action == "cleanup":
        return cmd_cleanup(args.branch)

    return 0


if __name__ == "__main__":
    sys.exit(main())
