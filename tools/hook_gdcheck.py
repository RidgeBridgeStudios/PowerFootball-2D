#!/usr/bin/env python3
"""
hook_gdcheck.py — Antigravity lifecycle hook runner for GDScript static verification.

Executes gdcheck.py, and on failure exits with non-zero status + diagnostic output
so Antigravity intercepts the failure and feeds the error log back to the agent context.
"""

from __future__ import annotations

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GDCHECK_PATH = os.path.join(ROOT, "tools", "gdcheck.py")


def main() -> int:
    cmd = [sys.executable, GDCHECK_PATH]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)

    if proc.returncode != 0:
        err_msg = proc.stdout.strip() or proc.stderr.strip()
        print(f"GDCHECK VERIFICATION FAILED:\n{err_msg}", file=sys.stderr)
        print(proc.stdout)
        return proc.returncode

    print("{}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
