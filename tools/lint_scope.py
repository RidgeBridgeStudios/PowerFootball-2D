#!/usr/bin/env python3
"""
lint_scope.py — Scope and Dead-Code AST Linter for PowerFootball-2D (GDScript 2.0).

Enforces critical postmortem compiler safeguards:
1. DUPLICATE DECLARATIONS:
   Tracks local variable declarations (`var <ident>`) within each function scope.
   Flags an ERROR if an identifier is declared more than once in the same function,
   even if located in unreachable blocks below early `return`, `break`, or `continue`.

2. DEAD CODE DETECTION:
   Flags statements or declarations occurring immediately below an unconditional
   `return`, `break`, or `continue` at the same or deeper indentation level within
   the same block. Multi-line return expressions and bracket continuations are correctly tracked.

Usage:
    python tools/lint_scope.py [target_path] [--xml]
"""

from __future__ import annotations

import argparse
import html
import os
import re
import sys
from typing import List, Optional, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STRING_RE = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
COMMENT_RE = re.compile(r'#.*$')
VAR_DECL_RE = re.compile(r'^\s*var\s+([A-Za-z0-9_]+)')


class ScopeViolation:
    def __init__(self, rule_id: str, file_path: str, line_number: int, message: str, severity: str = "ERROR") -> None:
        self.rule_id = rule_id
        self.file_path = file_path
        self.line_number = line_number
        self.message = message
        self.severity = severity

    def __str__(self) -> str:
        rel = os.path.relpath(self.file_path, ROOT).replace("\\", "/")
        return f"{self.severity:<5} [{self.rule_id}] {rel}:{self.line_number}  {self.message}"


def strip_comments_and_strings(line: str) -> str:
    clean = STRING_RE.sub('""', line)
    clean = COMMENT_RE.sub('', clean)
    return clean


def get_all_gd_files(base_dir: str) -> list[str]:
    files = []
    if os.path.isfile(base_dir):
        return [base_dir] if base_dir.endswith(".gd") else []
    for dirpath, dirnames, filenames in os.walk(base_dir):
        dirnames[:] = [d for d in dirnames if d not in (".git", "addons", ".claude", "__pycache__", ".godot")]
        for f in filenames:
            if f.endswith(".gd"):
                files.append(os.path.join(dirpath, f))
    return sorted(files)


def get_line_indent(raw_line: str) -> int:
    stripped = raw_line.lstrip()
    if not stripped:
        return -1
    indent = 0
    for char in raw_line[:len(raw_line) - len(stripped)]:
        if char == '\t':
            indent += 4
        else:
            indent += 1
    return indent


def count_bracket_delta(code: str) -> int:
    opens = code.count('(') + code.count('[') + code.count('{')
    closes = code.count(')') + code.count(']') + code.count('}')
    return opens - closes


def lint_file_scope(file_path: str) -> list[ScopeViolation]:
    violations: list[ScopeViolation] = []
    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception as e:
        return [ScopeViolation("READ-ERROR", file_path, 1, f"Failed to read file: {e}")]

    in_func: bool = False
    func_name: str = ""
    func_indent: int = 0
    bracket_depth: int = 0
    declared_vars: dict[str, int] = {}  # var_name -> line_number

    # Unconditional jump tracking for dead code detection
    # Each entry: (indent_level, line_number, jump_type)
    active_jumps: list[tuple[int, int, str]] = []
    pending_jump: tuple[int, int, str] | None = None

    for idx, raw_line in enumerate(lines, start=1):
        code = strip_comments_and_strings(raw_line).rstrip()
        stripped = code.strip()
        if not stripped:
            continue

        indent = get_line_indent(raw_line)

        # Check for function definition
        func_match = re.match(r'^(?:static\s+)?func\s+([A-Za-z0-9_]+)\s*\(', stripped)
        if func_match and bracket_depth == 0:
            in_func = True
            func_name = func_match.group(1)
            func_indent = indent
            bracket_depth = count_bracket_delta(code)
            declared_vars = {}
            active_jumps = []
            pending_jump = None
            continue

        if in_func:
            # If bracket depth was open, we are continuing a multi-line statement
            if bracket_depth > 0:
                bracket_depth += count_bracket_delta(code)
                if bracket_depth <= 0:
                    bracket_depth = 0
                    if pending_jump is not None:
                        active_jumps.append(pending_jump)
                        pending_jump = None
                continue

            # Check if function ended (non-empty line at or below func_indent)
            if indent <= func_indent:
                in_func = False
                func_name = ""
                declared_vars = {}
                active_jumps = []
                pending_jump = None
                bracket_depth = count_bracket_delta(code)
                continue

            # Pop jumps that belonged to deeper indentation blocks that have ended
            active_jumps = [j for j in active_jumps if j[0] < indent]

            # Dead code check: If there's an active jump at the exact same or parent block level
            is_branch_start = (
                stripped.startswith("elif ")
                or stripped.startswith("else:")
                or stripped.startswith("elif:")
                or stripped.startswith("case ")
                or stripped.startswith("default:")
            )
            if not is_branch_start:
                for jump_indent, jump_line, jump_type in active_jumps:
                    if indent >= jump_indent:
                        violations.append(ScopeViolation(
                            rule_id="RULE-DEAD-CODE",
                            file_path=file_path,
                            line_number=idx,
                            message=f"Unreachable dead code following unconditional '{jump_type}' at line {jump_line} in function '{func_name}'",
                            severity="WARNING"
                        ))
                        break

            # Check variable declaration
            var_match = VAR_DECL_RE.match(code)
            if var_match:
                var_name = var_match.group(1)
                if var_name in declared_vars:
                    orig_line = declared_vars[var_name]
                    violations.append(ScopeViolation(
                        rule_id="RULE-DUPLICATE-VAR",
                        file_path=file_path,
                        line_number=idx,
                        message=f"Duplicate local variable declaration 'var {var_name}' in function '{func_name}' (previously declared at line {orig_line}). Causes fatal GDScript parse failure.",
                        severity="ERROR"
                    ))
                else:
                    declared_vars[var_name] = idx

            # Update bracket depth
            b_delta = count_bracket_delta(code)
            bracket_depth += b_delta
            if bracket_depth < 0:
                bracket_depth = 0

            # Check for unconditional jump statements (return, break, continue)
            if stripped == "return" or stripped.startswith("return ") or stripped == "break" or stripped == "continue":
                jump_type = stripped.split()[0]
                if bracket_depth > 0:
                    pending_jump = (indent, idx, jump_type)
                else:
                    active_jumps.append((indent, idx, jump_type))

    return violations


def run_scope_linter(target_path: str = ROOT) -> list[ScopeViolation]:
    gd_files = get_all_gd_files(target_path)
    all_violations: list[ScopeViolation] = []
    for f in gd_files:
        all_violations.extend(lint_file_scope(f))
    return all_violations


def format_xml_output(violations: list[ScopeViolation]) -> str:
    xml_lines = ['<verification_failure tool="lint_scope">']
    for v in violations:
        rel = html.escape(os.path.relpath(v.file_path, ROOT).replace("\\", "/"))
        xml_lines.append(
            f'  <diagnostic file="{rel}" line="{v.line_number}" severity="{v.severity}" rule="{v.rule_id}">'
            f'{html.escape(v.message)}'
            f'</diagnostic>'
        )
    xml_lines.append('</verification_failure>')
    return "\n".join(xml_lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Scope & Dead-Code AST Linter")
    parser.add_argument("target", nargs="?", default=ROOT, help="Target directory or file to lint")
    parser.add_argument("--xml", action="store_true", help="Output failures as structured XML")
    args = parser.parse_args()

    target_path = os.path.abspath(args.target) if args.target else ROOT
    violations = run_scope_linter(target_path)
    errors = [v for v in violations if v.severity == "ERROR"]

    if violations:
        if args.xml:
            print(format_xml_output(violations), file=sys.stderr)
        else:
            print(f"=== Scope Linter Report ({len(violations)} findings: {len(errors)} errors, {len(violations) - len(errors)} warnings) ===")
            for v in violations:
                print(str(v))
            print("===============================================================")
        return 1 if errors else 0

    if not args.xml:
        print("lint_scope: 0 scope or duplicate variable errors across repository.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
