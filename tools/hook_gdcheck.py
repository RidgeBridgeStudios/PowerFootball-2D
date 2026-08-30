#!/usr/bin/env python3
"""
hook_gdcheck.py — Antigravity lifecycle hook runner for GDScript static verification.

Executes gdcheck.py, and on failure exits with non-zero status and structured
XML diagnostic output to stderr so Antigravity intercepts the failure and
feeds actionable diagnostics back into the agent context.
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


def format_xml_diagnostics(diagnostics: list[dict[str, str]], fallback_text: str = "") -> str:
    xml_lines = ['<verification_failure tool="gdcheck">']
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
    cmd = [sys.executable, GDCHECK_PATH]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)

    if proc.returncode != 0:
        combined_out = (proc.stdout or "") + "\n" + (proc.stderr or "")
        diagnostics = parse_gdcheck_output(combined_out)
        xml_report = format_xml_diagnostics(diagnostics, combined_out)
        print(xml_report, file=sys.stderr)
        if proc.stdout.strip():
            print(proc.stdout)
        return proc.returncode

    print("{}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
