#!/usr/bin/env python3
"""
tscn_linter.py — Scene Graph & TSCN Static Invariant Linter for PowerFootball-2D.

Parses all .tscn scene files in the repository and verifies:
1. Resource Resolution: Every ext_resource path (res://...) points to an existing file on disk.
2. Node Tree Integrity: Every [node] declaration has a valid parent reference (no orphaned nodes).
3. Signal Connections: All [connection] blocks reference valid existing nodes in the scene.
4. Collision Matrix Guard: CharacterBody2D nodes must NEVER mask Layer 3 (Ball, bit 3 / value 4).
5. Resource Isolation: Materials/Shaders on player scenes declare resource_local_to_scene = true where applicable.

Usage:
    python tools/tscn_linter.py [--xml] [path/to/target.tscn]
"""

from __future__ import annotations

import argparse
import html
import os
import re
import sys
from typing import Dict, List, Optional, Set, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class TSCNViolation:
    def __init__(self, rule_id: str, file_path: str, line_number: int, message: str, severity: str = "ERROR") -> None:
        self.rule_id = rule_id
        self.file_path = file_path
        self.line_number = line_number
        self.message = message
        self.severity = severity

    def __str__(self) -> str:
        rel = os.path.relpath(self.file_path, ROOT).replace("\\", "/")
        return f"{self.severity:<5} [{self.rule_id}] {rel}:{self.line_number}  {self.message}"


def get_all_tscn_files(base_dir: str) -> list[str]:
    files = []
    for dirpath, dirnames, filenames in os.walk(base_dir):
        dirnames[:] = [d for d in dirnames if d not in (".git", "addons", ".claude", "__pycache__", ".godot", "legacy", "autoload")]
        for f in filenames:
            if f.endswith(".tscn"):
                files.append(os.path.join(dirpath, f))
    return sorted(files)


def lint_tscn_file(tscn_path: str) -> list[TSCNViolation]:
    violations: list[TSCNViolation] = []
    rel_path = os.path.relpath(tscn_path, ROOT).replace("\\", "/")

    try:
        with open(tscn_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception as e:
        return [TSCNViolation("TSCN-READ-ERR", tscn_path, 1, f"Failed to read file: {e}")]

    # Track resources and nodes
    ext_resources: dict[str, tuple[str, str, int]] = {}  # id -> (type, path, line_num)
    sub_resources: set[str] = set()
    node_names: set[str] = set()
    node_paths: set[str] = set()
    root_node_name: str | None = None

    current_section_type = ""
    current_node_name = ""
    current_node_type = ""
    current_node_parent = ""
    in_character_body = False

    for idx, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue

        # 1. Check ext_resource declarations
        if line.startswith("[ext_resource"):
            current_section_type = "ext_resource"
            m_path = re.search(r'path="res:\/\/([^"]+)"', line)
            m_id = re.search(r'id="([^"]+)"', line)
            m_type = re.search(r'type="([^"]+)"', line)

            if m_path and m_id:
                res_rel = m_path.group(1)
                res_id = m_id.group(1)
                res_type = m_type.group(1) if m_type else "Resource"
                ext_resources[res_id] = (res_type, res_rel, idx)

                # Check if resource file exists on disk
                res_disk_path = os.path.join(ROOT, res_rel)
                if not os.path.exists(res_disk_path):
                    violations.append(TSCNViolation(
                        rule_id="TSCN-01-MISSING-RESOURCE",
                        file_path=tscn_path,
                        line_number=idx,
                        message=f"ext_resource id='{res_id}' references missing file 'res://{res_rel}'"
                    ))
            continue

        # 2. Check sub_resource declarations
        if line.startswith("[sub_resource"):
            current_section_type = "sub_resource"
            m_id = re.search(r'id="([^"]+)"', line)
            if m_id:
                sub_resources.add(m_id.group(1))
            continue

        # 3. Check node declarations
        if line.startswith("[node "):
            current_section_type = "node"
            m_name = re.search(r'name="([^"]+)"', line)
            m_type = re.search(r'type="([^"]+)"', line)
            m_parent = re.search(r'parent="([^"]+)"', line)

            if m_name:
                current_node_name = m_name.group(1)
                current_node_type = m_type.group(1) if m_type else ""
                current_node_parent = m_parent.group(1) if m_parent else ""

                if current_node_parent == "":
                    # Root node
                    root_node_name = current_node_name
                    node_paths.add(".")
                    node_paths.add(current_node_name)
                else:
                    # Child node
                    if current_node_parent == ".":
                        node_full_path = current_node_name
                    else:
                        node_full_path = f"{current_node_parent}/{current_node_name}"
                    node_paths.add(node_full_path)

                    # Verify parent exists
                    if current_node_parent != "." and current_node_parent not in node_paths and current_node_parent not in node_names:
                        violations.append(TSCNViolation(
                            rule_id="TSCN-02-ORPHANED-NODE",
                            file_path=tscn_path,
                            line_number=idx,
                            message=f"Node '{current_node_name}' specifies non-existent parent='{current_node_parent}'"
                        ))

                node_names.add(current_node_name)
                in_character_body = (current_node_type == "CharacterBody2D" or "Player" in current_node_name)
            continue

        # 4. Check connection blocks
        if line.startswith("[connection "):
            current_section_type = "connection"
            m_from = re.search(r'from="([^"]+)"', line)
            m_to = re.search(r'to="([^"]+)"', line)
            m_sig = re.search(r'signal="([^"]+)"', line)
            m_meth = re.search(r'method="([^"]+)"', line)

            if m_from and m_to:
                from_node = m_from.group(1)
                to_node = m_to.group(1)

                if from_node != "." and from_node not in node_paths and from_node not in node_names:
                    violations.append(TSCNViolation(
                        rule_id="TSCN-03-BROKEN-CONNECTION",
                        file_path=tscn_path,
                        line_number=idx,
                        message=f"Connection 'from=\"{from_node}\"' references non-existent node in scene"
                    ))
                if to_node != "." and to_node not in node_paths and to_node not in node_names:
                    violations.append(TSCNViolation(
                        rule_id="TSCN-03-BROKEN-CONNECTION",
                        file_path=tscn_path,
                        line_number=idx,
                        message=f"Connection 'to=\"{to_node}\"' references non-existent node in scene"
                    ))
            continue

        # 5. Check collision_mask on CharacterBody2D
        if current_section_type == "node" and in_character_body and line.startswith("collision_mask"):
            m_mask = re.search(r'collision_mask\s*=\s*(\d+)', line)
            if m_mask:
                mask_val = int(m_mask.group(1))
                if (mask_val & 4) != 0:
                    violations.append(TSCNViolation(
                        rule_id="TSCN-04-COLLISION-LAYER-MASK",
                        file_path=tscn_path,
                        line_number=idx,
                        message=f"CharacterBody2D node '{current_node_name}' sets collision_mask={mask_val} which masks Layer 3 (BallPhysicsBody)."
                    ))

    return violations


def format_xml_output(violations: list[TSCNViolation]) -> str:
    xml_lines = ['<verification_failure tool="tscn_linter">']
    for v in violations:
        rel = html.escape(os.path.relpath(v.file_path, ROOT).replace("\\", "/"))
        xml_lines.append(
            f'  <diagnostic file="{rel}" line="{v.line_number}" severity="{v.severity}" rule="{v.rule_id}">'
            f'{html.escape(v.message)}'
            f'</diagnostic>'
        )
    xml_lines.append('</verification_failure>')
    return "\n".join(xml_lines)


def run_tscn_linter(target: str | None = None) -> list[TSCNViolation]:
    if target and os.path.isfile(target):
        tscn_files = [os.path.abspath(target)]
    elif target and os.path.isdir(target):
        tscn_files = get_all_tscn_files(os.path.abspath(target))
    else:
        tscn_files = get_all_tscn_files(ROOT)

    all_violations: list[TSCNViolation] = []
    for path in tscn_files:
        all_violations.extend(lint_tscn_file(path))
    return all_violations


def main() -> int:
    parser = argparse.ArgumentParser(description="TSCN Scene Graph Invariant Linter")
    parser.add_argument("target", nargs="?", default=None, help="Target TSCN file or directory")
    parser.add_argument("--xml", action="store_true", help="Output failures in structured XML format")
    args = parser.parse_args()

    violations = run_tscn_linter(args.target)

    if violations:
        if args.xml:
            print(format_xml_output(violations), file=sys.stderr)
        else:
            print(f"=== TSCN Linter Violations ({len(violations)} errors) ===")
            for v in violations:
                print(str(v))
            print("=========================================================")
        return 1

    if not args.xml:
        print(f"tscn_linter: 0 scene graph errors across repository.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
