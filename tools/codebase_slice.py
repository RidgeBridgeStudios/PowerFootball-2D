#!/usr/bin/env python3
"""
codebase_slice.py — Targeted Code Slicing CLI Utility.

Extracts specific class methods, enums, signal declarations, or class headers
with exact line numbers without loading entire files into agent context.

Usage:
    python tools/codebase_slice.py <filepath> --func <func_name>
    python tools/codebase_slice.py <filepath> --enum <enum_name>
    python tools/codebase_slice.py <filepath> --class
    python tools/codebase_slice.py <filepath> --signals
    python tools/codebase_slice.py <filepath> --list
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import List, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_file_lines(filepath: str) -> tuple[str, list[str]]:
    if not os.path.isabs(filepath):
        filepath = os.path.join(ROOT, filepath.replace("/", os.sep))

    if not os.path.isfile(filepath):
        print(f"Error: File not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    rel_path = os.path.relpath(filepath, ROOT).replace("\\", "/")
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()
    return rel_path, lines


def slice_function(lines: list[str], func_name: str, show_line_numbers: bool = True) -> list[str]:
    func_pattern = re.compile(rf"^(?:static\s+)?func\s+{re.escape(func_name)}\s*\(")
    start_idx = -1
    docstring_start = -1

    for idx, line in enumerate(lines):
        if func_pattern.match(line):
            start_idx = idx
            # Backtrack to capture preceding docstrings / comments
            back = idx - 1
            while back >= 0 and lines[back].strip().startswith("##"):
                back -= 1
            docstring_start = back + 1
            break

    if start_idx == -1:
        return []

    # Find function end (next function, class_name, enum, or non-indented top-level line)
    end_idx = len(lines)
    for idx in range(start_idx + 1, len(lines)):
        line = lines[idx]
        stripped = line.strip()
        if not stripped:
            continue
        # If line starts at column 0 and is a new top-level declaration
        if not line.startswith("\t") and not line.startswith(" "):
            if stripped.startswith("func ") or stripped.startswith("static func ") or \
               stripped.startswith("class_name ") or stripped.startswith("enum ") or \
               stripped.startswith("signal ") or stripped.startswith("const ") or \
               stripped.startswith("var ") or stripped.startswith("@export ") or stripped.startswith("@onready "):
                # Backtrack any docstring comments attached to the next item
                back = idx
                while back > start_idx and lines[back - 1].strip().startswith("##"):
                    back -= 1
                end_idx = back
                break

    output_slice: list[str] = []
    first_line = docstring_start if docstring_start != -1 else start_idx
    for idx in range(first_line, end_idx):
        line_content = lines[idx].rstrip("\r\n")
        if show_line_numbers:
            output_slice.append(f"{idx + 1:4d}: {line_content}")
        else:
            output_slice.append(line_content)

    return output_slice


def slice_enum(lines: list[str], enum_name: str, show_line_numbers: bool = True) -> list[str]:
    enum_pattern = re.compile(rf"^enum\s+{re.escape(enum_name)}\b")
    start_idx = -1
    docstring_start = -1

    for idx, line in enumerate(lines):
        if enum_pattern.match(line.strip()):
            start_idx = idx
            back = idx - 1
            while back >= 0 and lines[back].strip().startswith("##"):
                back -= 1
            docstring_start = back + 1
            break

    if start_idx == -1:
        return []

    end_idx = start_idx + 1
    if "}" not in lines[start_idx]:
        for idx in range(start_idx + 1, len(lines)):
            if "}" in lines[idx]:
                end_idx = idx + 1
                break

    output_slice: list[str] = []
    first_line = docstring_start if docstring_start != -1 else start_idx
    for idx in range(first_line, end_idx):
        line_content = lines[idx].rstrip("\r\n")
        if show_line_numbers:
            output_slice.append(f"{idx + 1:4d}: {line_content}")
        else:
            output_slice.append(line_content)

    return output_slice


def slice_class_header(lines: list[str], show_line_numbers: bool = True) -> list[str]:
    output_slice: list[str] = []
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("func ") or stripped.startswith("static func "):
            break
        line_content = line.rstrip("\r\n")
        if show_line_numbers:
            output_slice.append(f"{idx + 1:4d}: {line_content}")
        else:
            output_slice.append(line_content)
    return output_slice


def slice_signals(lines: list[str], show_line_numbers: bool = True) -> list[str]:
    output_slice: list[str] = []
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("signal "):
            line_content = line.rstrip("\r\n")
            if show_line_numbers:
                output_slice.append(f"{idx + 1:4d}: {line_content}")
            else:
                output_slice.append(line_content)
    return output_slice


def list_symbols_in_file(lines: list[str]) -> list[str]:
    summary: list[str] = []
    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("func ") or stripped.startswith("static func "):
            m = re.match(r"(?:static\s+)?func\s+([a-zA-Z0-9_]+)\s*\((.*)\)\s*(?:->\s*([a-zA-Z0-9_\[\], \.]+))?", stripped)
            if m:
                ret = m.group(3) or "void"
                summary.append(f"  Line {idx:4d} | Method: {m.group(1)}({m.group(2)}) -> {ret}")
        elif stripped.startswith("enum "):
            m = re.match(r"enum\s+([a-zA-Z0-9_]+)", stripped)
            if m:
                summary.append(f"  Line {idx:4d} | Enum:   {m.group(1)}")
        elif stripped.startswith("signal "):
            m = re.match(r"signal\s+([a-zA-Z0-9_]+)", stripped)
            if m:
                summary.append(f"  Line {idx:4d} | Signal: {m.group(1)}")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract targeted code slices from GDScript files.")
    parser.add_argument("file", help="Path to GDScript file.")
    parser.add_argument("--func", help="Function/method name to slice.")
    parser.add_argument("--enum", help="Enum name to slice.")
    parser.add_argument("--class-header", "--class", action="store_true", help="Slice class header & member declarations.")
    parser.add_argument("--signals", action="store_true", help="Slice all signal declarations.")
    parser.add_argument("--list", action="store_true", help="List all declarations in the file.")
    parser.add_argument("--raw", action="store_true", help="Output raw code without line numbers.")

    args = parser.parse_args()

    rel_path, lines = load_file_lines(args.file)
    show_line_numbers = not args.raw

    if args.list:
        symbols = list_symbols_in_file(lines)
        print(f"=== Symbols in {rel_path} ({len(lines)} lines) ===")
        for s in symbols:
            print(s)
        return 0

    if args.func:
        sliced = slice_function(lines, args.func, show_line_numbers)
        if not sliced:
            print(f"Error: Function `{args.func}` not found in {rel_path}", file=sys.stderr)
            return 1
        print(f"=== Slicing `{args.func}()` from {rel_path} ===")
        for l in sliced:
            print(l)
        return 0

    if args.enum:
        sliced = slice_enum(lines, args.enum, show_line_numbers)
        if not sliced:
            print(f"Error: Enum `{args.enum}` not found in {rel_path}", file=sys.stderr)
            return 1
        print(f"=== Slicing enum `{args.enum}` from {rel_path} ===")
        for l in sliced:
            print(l)
        return 0

    if args.signals:
        sliced = slice_signals(lines, show_line_numbers)
        print(f"=== Slicing signals from {rel_path} ({len(sliced)} signals) ===")
        for l in sliced:
            print(l)
        return 0

    if args.class_header:
        sliced = slice_class_header(lines, show_line_numbers)
        print(f"=== Slicing class header from {rel_path} ===")
        for l in sliced:
            print(l)
        return 0

    # Default if no specific flag passed: show symbol list
    symbols = list_symbols_in_file(lines)
    print(f"=== Symbols in {rel_path} ({len(lines)} lines) ===")
    for s in symbols:
        print(s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
