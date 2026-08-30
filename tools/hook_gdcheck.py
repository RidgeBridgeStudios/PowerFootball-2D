#!/usr/bin/env python3
"""
hook_gdcheck.py — Antigravity lifecycle hook runner for comprehensive static verification.

Executes gdcheck.py, lint_invariants.py, tscn_linter.py, and validate_schemas.py.
On failure, exits with non-zero status and structured XML diagnostic output to stderr
so Antigravity intercepts the failure and feeds actionable diagnostics back into agent context.
"""

from __future__ import annotations

import html
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GDCHECK_PATH = os.path.join(ROOT, "tools", "gdcheck.py")
LINT_INVARIANTS_PATH = os.path.join(ROOT, "tools", "lint_invariants.py")
TSCN_LINTER_PATH = os.path.join(ROOT, "tools", "tscn_linter.py")
VALIDATE_SCHEMAS_PATH = os.path.join(ROOT, "tools", "validate_schemas.py")

PROBLEM_RE = re.compile(r"^(ERROR|WARN)\s+([^:]+):(\d+)\s+(.+)$")


def parse_gdcheck_output(raw_output: str) -> list[dict[str, str]]:
    diagnostics = []
    for line in raw_output.splitlines():
        line = line.strip()
        m = PROBLEM_RE.match(line)
        if m:
            diagnostics.append({
                "severity": m.group(1),
                "file": m.group(2).replace("\\", "/"),
                "line": m.group(3),
                "message": m.group(4)
            })
    return diagnostics


def format_xml_diagnostics(diagnostics: list[dict[str, str]], tool_name: str = "gdcheck", fallback_text: str = "") -> str:
    xml_lines = [f'<verification_failure tool="{tool_name}">']
    if diagnostics:
        for diag in diagnostics:
            f = html.escape(diag["file"])
            l = diag["line"]
            s = html.escape(diag["severity"])
            msg = html.escape(diag["message"])
            xml_lines.append(f'  <diagnostic file="{f}" line="{l}" severity="{s}">{msg}</diagnostic>')
    elif fallback_text.strip():
        xml_lines.append(f'  <diagnostic file="project" line="1" severity="ERROR">{html.escape(fallback_text.strip())}</diagnostic>')
    xml_lines.append("</verification_failure>")
    return "\n".join(xml_lines)


def main() -> int:
    # 1. Run gdcheck.py
    cmd_gdcheck = [sys.executable, GDCHECK_PATH]
    proc_gdcheck = subprocess.run(cmd_gdcheck, cwd=ROOT, capture_output=True, text=True)

    if proc_gdcheck.returncode != 0:
        combined_out = (proc_gdcheck.stdout or "") + "\n" + (proc_gdcheck.stderr or "")
        diagnostics = parse_gdcheck_output(combined_out)
        xml_report = format_xml_diagnostics(diagnostics, "gdcheck", combined_out)
        print(xml_report, file=sys.stderr)
        if proc_gdcheck.stdout.strip():
            print(proc_gdcheck.stdout)
        return proc_gdcheck.returncode

    # 2. Run lint_invariants.py
    cmd_lint = [sys.executable, LINT_INVARIANTS_PATH, "--xml"]
    proc_lint = subprocess.run(cmd_lint, cwd=ROOT, capture_output=True, text=True)

    if proc_lint.returncode != 0:
        if proc_lint.stderr.strip():
            print(proc_lint.stderr, file=sys.stderr)
        else:
            print(proc_lint.stdout, file=sys.stderr)
        return proc_lint.returncode

    # 3. Run tscn_linter.py
    cmd_tscn = [sys.executable, TSCN_LINTER_PATH, "--xml"]
    proc_tscn = subprocess.run(cmd_tscn, cwd=ROOT, capture_output=True, text=True)

    if proc_tscn.returncode != 0:
        if proc_tscn.stderr.strip():
            print(proc_tscn.stderr, file=sys.stderr)
        else:
            print(proc_tscn.stdout, file=sys.stderr)
        return proc_tscn.returncode

    # 4. Run validate_schemas.py
    cmd_schema = [sys.executable, VALIDATE_SCHEMAS_PATH, "--xml"]
    proc_schema = subprocess.run(cmd_schema, cwd=ROOT, capture_output=True, text=True)

    if proc_schema.returncode != 0:
        if proc_schema.stderr.strip():
            print(proc_schema.stderr, file=sys.stderr)
        else:
            print(proc_schema.stdout, file=sys.stderr)
        return proc_schema.returncode

    print("{}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
