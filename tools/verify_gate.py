#!/usr/bin/env python3
"""
verify_gate.py — Unified Verification Orchestrator for PowerFootball-2D.

Modes:
  --fast (Default, post-file-write gate):
      Executes high-speed (<150ms) static AST, scope, type-comparison,
      StringName, allocation, scene graph, and database integrity checks.
      Runs:
        1. gdcheck.py
        2. lint_invariants.py
        3. lint_scope.py
        4. lint_type_comparisons.py
        5. lint_stringnames.py
        6. lint_shadowing.py
        7. lint_allocations.py
        7b. lint_xref.py  (qualified member access + res:// path existence)
        8. tscn_linter.py
        9. verify_db.py

  --full (Pre-turn-completion verification battery):
      Executes --fast checks plus simulation evaluations, property fuzzers,
      and index regenerations:
        10. eval_simulation.py
        11. fuzz_solvers.py
        12. fuzz_formations.py
        13. dump_api.py
        14. generate_symbols.py
        15. compact_errata.py

Usage:
    python tools/verify_gate.py [--fast | --full] [--xml]
"""

from __future__ import annotations

import argparse
import html
import os
import subprocess
import sys
import time
from typing import Any, List, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class CheckResult:
    def __init__(self, name: str, passed: bool, duration_ms: float, stdout: str, stderr: str, exit_code: int) -> None:
        self.name = name
        self.passed = passed
        self.duration_ms = duration_ms
        self.stdout = stdout
        self.stderr = stderr
        self.exit_code = exit_code


def run_step(name: str, cmd: list[str]) -> CheckResult:
    t0 = time.perf_counter()
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    dt_ms = (time.perf_counter() - t0) * 1000.0
    passed = (proc.returncode == 0)
    return CheckResult(name, passed, dt_ms, proc.stdout.strip(), proc.stderr.strip(), proc.returncode)


def main() -> int:
    parser = argparse.ArgumentParser(description="Unified Verification Orchestrator")
    parser.add_argument("--fast", action="store_true", help="Run fast static verification checks (default)")
    parser.add_argument("--full", action="store_true", help="Run full suite including simulations, fuzzers, and indexing")
    parser.add_argument("--xml", action="store_true", help="Output failure diagnostics in structured XML")
    args = parser.parse_args()

    mode_full = args.full
    py = sys.executable

    fast_checks = [
        ("gdcheck", [py, os.path.join(ROOT, "tools", "gdcheck.py")]),
        ("lint_invariants", [py, os.path.join(ROOT, "tools", "lint_invariants.py")]),
        ("lint_scope", [py, os.path.join(ROOT, "tools", "lint_scope.py")]),
        ("lint_type_comparisons", [py, os.path.join(ROOT, "tools", "lint_type_comparisons.py")]),
        ("lint_stringnames", [py, os.path.join(ROOT, "tools", "lint_stringnames.py")]),
        ("lint_shadowing", [py, os.path.join(ROOT, "tools", "lint_shadowing.py")]),
        ("lint_allocations", [py, os.path.join(ROOT, "tools", "lint_allocations.py")]),
        ("lint_xref", [py, os.path.join(ROOT, "tools", "lint_xref.py")]),
        ("tscn_linter", [py, os.path.join(ROOT, "tools", "tscn_linter.py")]),
        ("verify_db", [py, os.path.join(ROOT, "tools", "verify_db.py")]),
    ]

    full_checks = [
        ("eval_simulation", [py, os.path.join(ROOT, "tools", "eval_simulation.py")]),
        ("fuzz_solvers", [py, os.path.join(ROOT, "tools", "fuzz_solvers.py"), "--iterations=10000"]),
        ("fuzz_formations", [py, os.path.join(ROOT, "tools", "fuzz_formations.py"), "--iterations=5000"]),
        ("dump_api", [py, os.path.join(ROOT, "tools", "dump_api.py")]),
        ("generate_symbols", [py, os.path.join(ROOT, "tools", "generate_symbols.py")]),
        ("compact_errata", [py, os.path.join(ROOT, "tools", "compact_errata.py")]),
    ]

    checks_to_run = list(fast_checks)
    if mode_full:
        checks_to_run.extend(full_checks)

    mode_label = "FULL PRE-TURN BATTERY" if mode_full else "FAST POST-WRITE GATE"
    if not args.xml:
        print(f"================================================================")
        print(f"       POWERFOOTBALL-2D VERIFICATION GATE [{mode_label}]")
        print(f"================================================================")

    results: list[CheckResult] = []
    all_passed = True
    total_start = time.perf_counter()

    for name, cmd in checks_to_run:
        res = run_step(name, cmd)
        results.append(res)
        if not res.passed:
            all_passed = False
            if not args.xml:
                print(f"[FAIL] {name:<22} ({res.duration_ms:6.1f}ms) - Exit code {res.exit_code}")
                if res.stdout:
                    print(f"  --- STDOUT ---\n  {res.stdout.replace(chr(10), chr(10) + '  ')}")
                if res.stderr:
                    print(f"  --- STDERR ---\n  {res.stderr.replace(chr(10), chr(10) + '  ')}")
            # Fast mode stops on first failure for immediate feedback
            if not mode_full:
                break
        else:
            if not args.xml:
                summary_line = res.stdout.splitlines()[0] if res.stdout else "OK"
                print(f"[PASS] {name:<22} ({res.duration_ms:6.1f}ms) - {summary_line}")

    total_duration_ms = (time.perf_counter() - total_start) * 1000.0

    if args.xml:
        xml_lines = [f'<verification_gate mode="{"full" if mode_full else "fast"}" passed="{all_passed}" duration_ms="{total_duration_ms:.1f}">']
        for r in results:
            xml_lines.append(f'  <step name="{r.name}" passed="{r.passed}" duration_ms="{r.duration_ms:.1f}" exit_code="{r.exit_code}">')
            if not r.passed:
                combined_msg = (r.stdout + "\n" + r.stderr).strip()
                xml_lines.append(f'    <diagnostic>{html.escape(combined_msg)}</diagnostic>')
            xml_lines.append('  </step>')
        xml_lines.append('</verification_gate>')
        if not all_passed:
            print("\n".join(xml_lines), file=sys.stderr)
        else:
            print("\n".join(xml_lines))
        return 0 if all_passed else 1

    print(f"----------------------------------------------------------------")
    if all_passed:
        print(f"[ALL CHECKS PASSED] {len(results)} step(s) completed in {total_duration_ms:.1f}ms.")
        print(f"================================================================")
        return 0
    else:
        print(f"[GATE FAILED] Diagnostics reported above.")
        print(f"================================================================")
        return 1


if __name__ == "__main__":
    sys.exit(main())
