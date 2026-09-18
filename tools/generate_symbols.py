#!/usr/bin/env python3
"""
generate_symbols.py — GDScript Symbolic Indexer.

Parses all GDScript files across the repository to generate `docs/SYMBOLS.json`,
a line-indexed map of every class, signal, enum, property, and method.

Usage:
    python tools/generate_symbols.py [--output docs/SYMBOLS.json]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Dict, List, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_GODOT = os.path.join(ROOT, "project.godot")
DEFAULT_OUTPUT = os.path.join(ROOT, "docs", "SYMBOLS.json")


def get_autoload_map() -> dict[str, str]:
    """Returns mapping from relative file path to autoload global name."""
    mapping: dict[str, str] = {}
    if not os.path.isfile(PROJECT_GODOT):
        return mapping

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
            parts = line.split("=", 1)
            name = parts[0].strip()
            val = parts[1].strip().strip('"').lstrip("*res://").replace("\\", "/")
            mapping[val] = name
    return mapping


def find_gd_files(root_dir: str) -> list[str]:
    gd_files: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in ("legacy", "addons") and not d.startswith(".")]
        for f in filenames:
            if f.endswith(".gd"):
                gd_files.append(os.path.join(dirpath, f))
    return sorted(gd_files)


def parse_function_signature(raw_sig: str) -> tuple[str, list[str], str]:
    """
    Parses `func_name(arg1: Type, ...) -> RetType` into (name, args_list, ret_type).
    """
    m = re.match(r"(?:static\s+)?func\s+([a-zA-Z0-9_]+)\s*\((.*)\)\s*(?:->\s*([a-zA-Z0-9_\[\], \.]+))?", raw_sig)
    if not m:
        return "", [], "void"

    name = m.group(1)
    raw_args = m.group(2).strip()
    ret_type = m.group(3).strip() if m.group(3) else "void"

    args_list: list[str] = []
    if raw_args:
        # Split by comma respecting brackets/parentheses
        current: list[str] = []
        depth = 0
        in_quote = False
        quote_char = ""
        for c in raw_args:
            if in_quote:
                current.append(c)
                if c == quote_char:
                    in_quote = False
                continue
            if c in ('"', "'"):
                in_quote = True
                quote_char = c
                current.append(c)
            elif c in ("(", "[", "{"):
                depth += 1
                current.append(c)
            elif c in (")", "]", "}"):
                depth -= 1
                current.append(c)
            elif c == "," and depth == 0:
                arg_item = "".join(current).strip()
                if arg_item:
                    args_list.append(arg_item)
                current = []
            else:
                current.append(c)
        if current:
            arg_item = "".join(current).strip()
            if arg_item:
                args_list.append(arg_item)

    return name, args_list, ret_type


def parse_file_symbols(filepath: str, autoload_map: dict[str, str]) -> tuple[str, dict[str, Any]]:
    rel_path = os.path.relpath(filepath, ROOT).replace("\\", "/")
    
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    class_name = ""
    signals: dict[str, Any] = {}
    enums: dict[str, Any] = {}
    properties: dict[str, Any] = {}
    methods: dict[str, Any] = {}

    # Check if autoload
    if rel_path in autoload_map:
        class_name = autoload_map[rel_path]

    in_enum = False
    enum_name = ""
    enum_line = 0
    enum_values: list[str] = []

    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()

        # Multi-line Enum parsing
        if in_enum:
            if "}" in stripped:
                in_enum = False
                val_part = stripped.split("}")[0]
                for v in val_part.split(","):
                    v_clean = v.strip().split("=")[0].split("#")[0].strip()
                    if v_clean:
                        enum_values.append(v_clean)
                enums[enum_name] = {"line": enum_line, "values": enum_values}
                enum_name = ""
                enum_values = []
            else:
                for v in stripped.split(","):
                    v_clean = v.strip().split("=")[0].split("#")[0].strip()
                    if v_clean:
                        enum_values.append(v_clean)
            continue

        if not stripped or stripped.startswith("#"):
            continue

        # Class Name
        m_class = re.match(r"^class_name\s+([a-zA-Z0-9_]+)", stripped)
        if m_class and not class_name:
            class_name = m_class.group(1)

        # Single-line or Start of Multi-line Enum
        m_enum = re.match(r"^enum\s+([a-zA-Z0-9_]+)\s*\{(.*)", stripped)
        if m_enum:
            e_name = m_enum.group(1)
            rest = m_enum.group(2)
            if "}" in rest:
                vals = [v.strip().split("=")[0].split("#")[0].strip() for v in rest.split("}")[0].split(",") if v.strip()]
                vals = [v for v in vals if v]
                enums[e_name] = {"line": idx, "values": vals}
            else:
                in_enum = True
                enum_name = e_name
                enum_line = idx
                enum_values = [v.strip().split("=")[0].split("#")[0].strip() for v in rest.split(",") if v.strip()]
                enum_values = [v for v in enum_values if v]
            continue

        # Signal
        m_sig = re.match(r"^signal\s+([a-zA-Z0-9_]+)(?:\((.*)\))?", stripped)
        if m_sig:
            sig_name = m_sig.group(1)
            sig_args = [a.strip() for a in (m_sig.group(2) or "").split(",") if a.strip()]
            signals[sig_name] = {"line": idx, "args": sig_args}
            continue

        # Properties & Constants (at top level column 0)
        if not line.startswith("\t") and not line.startswith("  "):
            m_const = re.match(r"^const\s+([a-zA-Z0-9_]+)(?:\s*:\s*([a-zA-Z0-9_\[\], \.]+))?", stripped)
            if m_const:
                c_name = m_const.group(1)
                c_type = m_const.group(2) or "Constant"
                properties[c_name] = {"line": idx, "type": c_type.strip(), "is_const": True}
                continue

            m_var = re.match(r"^(?:@export\s+|@onready\s+)?var\s+([a-zA-Z0-9_]+)(?:\s*:\s*([a-zA-Z0-9_\[\], \.]+))?", stripped)
            if m_var:
                v_name = m_var.group(1)
                v_type = m_var.group(2) or "Variant"
                # If assigned with := or = type inference, clean up
                if "=" in v_type:
                    v_type = v_type.split("=")[0].strip()
                properties[v_name] = {
                    "line": idx,
                    "type": v_type.strip(),
                    "is_export": "@export" in stripped,
                    "is_onready": "@onready" in stripped,
                }
                continue

        # Functions / Methods
        if stripped.startswith("func ") or stripped.startswith("static func "):
            # Join multi-line signatures if needed
            full_sig = stripped
            sig_idx = idx
            f_name, f_args, f_ret = parse_function_signature(full_sig)
            if f_name:
                methods[f_name] = {
                    "line": sig_idx,
                    "args": f_args,
                    "return": f_ret,
                    "is_static": stripped.startswith("static func "),
                }

    if not class_name:
        class_name = os.path.splitext(os.path.basename(filepath))[0]

    symbol_data = {
        "path": rel_path,
        "line": 1,
        "signals": signals,
        "enums": enums,
        "properties": properties,
        "methods": methods,
    }

    return class_name, symbol_data


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate docs/SYMBOLS.json symbol index.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="Path to write SYMBOLS.json.")
    args = parser.parse_args()

    autoload_map = get_autoload_map()
    gd_files = find_gd_files(ROOT)

    symbols_db: dict[str, Any] = {}

    for filepath in gd_files:
        c_name, sym_info = parse_file_symbols(filepath, autoload_map)
        symbols_db[c_name] = sym_info

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(symbols_db, f, indent=2)

    total_classes = len(symbols_db)
    total_methods = sum(len(s["methods"]) for s in symbols_db.values())
    total_properties = sum(len(s["properties"]) for s in symbols_db.values())
    total_signals = sum(len(s["signals"]) for s in symbols_db.values())

    print(f"generate_symbols: Indexed {total_classes} classes, {total_methods} methods, {total_properties} properties, {total_signals} signals -> {os.path.relpath(args.output, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
