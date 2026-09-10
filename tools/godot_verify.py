#!/usr/bin/env python3
"""
godot_verify.py -- Godot Engine Headless Compiler & Parse Verification."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

COMMON_SEARCH_PATHS = [
    r"F:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe",
    r"F:\Godot_v4.7.2-stable_mono_win67\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe",
]

ERROR_PATTERNS = [
    re.compile(r"SCRIPT ERROR:\s*(.+)", re.I),
    re.compile(r"ERROR:\s+Failed to load script\s+(.+)", re.I),
    re.compile(r"Parse Error:\s*(.+)", re.I),
    re.compile(r"Compile Error:\s*(.+)", re.I),
    re.compile(r"Compilation failed", re.I),
    re.compile(r"Identifier not found:\s*(.+)", re.I),
]

BENIGN_PATTERNS = [
    re.compile(r"\.NET Sdk not found", re.I),
    re.compile(r"GodotSharpEditor", re.I),
    re.compile(r"CSharpInstanceBridge", re.I),
    re.compile(r"audio", re.I),
]


def find_godot_binary() -> str | None:
    env_bin = os.environ.get("GODOT_BIN")
    if env_bin and os.path.isfile(env_bin):
        return env_bin

    for path in COMMON_SEARCH_PATHS:
        if os.path.isfile(path):
            return path

    for name in ["godot_console", "godot", "godot4", "godot4-console"]:
        p = shutil.which(name)
        if p and os.path.isfile(p):
            return p

    return None


def run_godot_verification(godot_bin: str, timeout_sec: float = 30.0) -> tuple[bool, list[str]]:
    cmd = [godot_bin, "--headless", "--editor", "--quit"]
    try:
        proc = subprocess.run(
            cmd,
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            encoding="utf-8",
            errors="replace"
        )
    except subprocess.TimeoutExpired:
        return False, [f"Godot editor verification timed out after {timeout_sec}s."]
    except Exception as e:
        return False, [f"Failed to execute Godot binary: {e}"]


    output = (proc.stdout or "") + "\n" + (proc.stderr or "")
    lines = output.splitlines()

    compilation_errors: list[str] = []
    for line in lines:
        if any(b.search(line) for b in BENIGN_PATTERNS): continue
        for ep in ERROR_PATTERNS:
            if ep.search(line):
                compilation_errors.append(line.strip())
                break

    return len(compilation_errors) == 0, compilation_errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Godot Engine Headless Compiler & Parse Verification")
    parser.add_argument("--strict", action="store_true", help="Fail if Godot executable is not found")
    parser.add_argument("--timeout", type=float, default=30.0, help="Verification timeout in seconds")
    args = parser.parse_args()

    godot_bin = find_godot_binary()
    if not godot_bin:
        msg = "godot_verify: Godot executable not found. (Install Godot or set GODOT_BIN to enable engine compilation checks)."
        if args.strict:
            print(f"ERROR: {msg}", file=sys.stderr)
            return 1
        print(f"[SKIP] {msg}")
        return 0

    t0 = time.perf_counter()
    passed, errors = run_godot_verification(godot_bin, timeout_sec=args.timeout)
    dt_ms = (time.perf_counter() - t0) * 1000.0

    if not passed:
        print("=== Godot Engine Script Compilation Errors ===", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        print("============================================", file=sys.stderr)
        return 1

    print(f"godot_verify: All project GDScript files compiled successfully by Godot engine ({dt_ms:.1f}ms).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
