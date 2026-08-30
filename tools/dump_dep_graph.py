#!/usr/bin/env python3
"""
dump_dep_graph.py — Static Dependency DAG & Blast Radius Analyzer for PowerFootball-2D.

Parses all GDScript files across the codebase to extract:
  - class_name definitions
  - extends inheritance chains
  - preload() / load() resource references
  - signal declarations with parameters
  - signal .emit() invocations
  - signal .connect() bindings
  - Simulation layer classification (Layers 1-5)

Constructs a bidirectional dependency graph, calculates transitive blast radii,
and exports docs/DEPENDENCY_GRAPH.json. Supports CLI query mode:
    python3 tools/dump_dep_graph.py --blast-radius entities/ball/Pseudo3DBall.gd
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Dict, List, Set

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.path.join(ROOT, "docs", "DEPENDENCY_GRAPH.json")

# Simulation Layer mapping (1 to 5)
LAYER_MAPPING = {
    "entities/ball/": 1,
    "entities/player/HeavyPlayerController.gd": 1,
    "entities/player/PlayerState.gd": 1,
    "entities/player/PlayerStateFactory.gd": 1,
    "entities/player/states/": 1,
    "pitch/PitchBoundary.gd": 1,
    "pitch/GoalZone.gd": 1,
    "pitch/PitchMarkings.gd": 1,
    "pitch/PitchScene.gd": 1,
    "pitch/SetPieceCoordinator.gd": 1,
    "pitch/PenaltyShootoutCoordinator.gd": 1,
    "shared/CollisionLayers.gd": 1,

    "autoloads/MatchWorldModel.gd": 2,
    "entities/player/PlayerBrain.gd": 2,
    "entities/goalkeeper/GoalkeeperDiveBrain.gd": 2,
    "entities/manager/ManagerDirector.gd": 2,
    "entities/referee/MatchReferee.gd": 2,
    "entities/referee/OffsideDetector.gd": 2,
    "entities/referee/MatchOfficialCrew.gd": 2,
    "entities/referee/CenterRefereeVisual.gd": 2,
    "entities/referee/AssistantRefereeVisual.gd": 2,
    "entities/referee/FourthOfficialVisual.gd": 2,
    "entities/referee/WhistleSynthesizer.gd": 2,
    "shared/PassUtilityScorer.gd": 2,
    "shared/UtilityMath.gd": 2,
    "shared/FormationAnchorMath.gd": 2,
    "shared/FormationLibrary.gd": 2,
    "shared/FormationRegistry.gd": 2,
    "shared/PlayerRoleConfig.gd": 2,

    "entities/player/MoodSystem.gd": 3,
    "entities/player/TrustSystem.gd": 3,
    "shared/PlayerRatingCalculator.gd": 3,
    "autoloads/MatchStatsTracker.gd": 3,

    "autoloads/DataLoader.gd": 4,
    "autoloads/ManagerLoader.gd": 4,
    "autoloads/RefereeLoader.gd": 4,
    "shared/PlayerData.gd": 4,
    "shared/TeamData.gd": 4,
    "shared/TeamManagementData.gd": 4,
    "shared/LeagueData.gd": 4,
    "shared/ManagerData.gd": 4,
    "shared/RefereeData.gd": 4,
    "shared/PlayerFactory.gd": 4,

    "autoloads/GameEvents.gd": 5,
    "autoloads/GameManager.gd": 5,
    "autoloads/InputHelper.gd": 5,
    "entities/manager/PressOffice.gd": 5,
    "entities/player/FacingArrow.gd": 5,
    "pitch/MatchCamera.gd": 5,
    "pitch/Minimap.gd": 5,
    "ui/": 5,
}

LAYER_NAMES = {
    1: "Layer 1 — Physics & Kinematics",
    2: "Layer 2 — Match AI & Spatial Navigation",
    3: "Layer 3 — Match Social & Dynamic Psychology",
    4: "Layer 4 — Club World & Persistent Entities",
    5: "Layer 5 — Narrative, Presentation & UI"
}

CLASS_NAME_RE = re.compile(r'^\s*class_name\s+([A-Za-z0-9_]+)', re.MULTILINE)
EXTENDS_RE = re.compile(r'^\s*extends\s+([A-Za-z0-9_]+)', re.MULTILINE)
PRELOAD_RE = re.compile(r'\b(?:preload|load)\s*\(\s*["\']res:\/\/([^"\']+)["\']\s*\)')
SIGNAL_DECL_RE = re.compile(r'^\s*signal\s+([A-Za-z0-9_]+)(?:\((.*?)\))?', re.MULTILINE)
SIGNAL_EMIT_RE = re.compile(r'(?:([A-Za-z0-9_]+)\.)?([A-Za-z0-9_]+)\.emit\s*\(')
SIGNAL_CONNECT_RE = re.compile(r'(?:([A-Za-z0-9_]+)\.)?([A-Za-z0-9_]+)\.connect\s*\(')
COMMENT_RE = re.compile(r'#.*$', re.MULTILINE)


def get_layer(rel_path: str) -> int:
    norm = rel_path.replace("\\", "/")
    for prefix, layer in LAYER_MAPPING.items():
        if norm.startswith(prefix) or norm == prefix:
            return layer
    if norm.startswith("autoloads/"):
        return 5
    if norm.startswith("ui/"):
        return 5
    if norm.startswith("shared/"):
        return 2
    if norm.startswith("entities/"):
        return 1
    return 1


class ScriptNode:
    def __init__(self, rel_path: str) -> None:
        self.rel_path = rel_path.replace("\\", "/")
        self.layer = get_layer(self.rel_path)
        self.class_name: str | None = None
        self.extends_class: str | None = None
        self.signals_declared: list[str] = []
        self.signals_emitted: list[str] = []
        self.signals_connected: list[str] = []
        self.preloaded_paths: list[str] = []
        self.referenced_classes: set[str] = set()

        # Graph edges
        self.direct_dependencies: set[str] = set()
        self.direct_dependents: set[str] = set()


def scan_repository() -> tuple[dict[str, ScriptNode], dict[str, str]]:
    nodes: dict[str, ScriptNode] = {}
    class_to_file: dict[str, str] = {}

    # 1. First pass: find all scripts and class definitions
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in (".git", "addons", ".claude", "__pycache__", "docs")]
        for f in filenames:
            if f.endswith(".gd"):
                full_path = os.path.join(dirpath, f)
                rel_path = os.path.relpath(full_path, ROOT).replace("\\", "/")
                node = ScriptNode(rel_path)

                with open(full_path, "r", encoding="utf-8", errors="replace") as file_obj:
                    content = file_obj.read()

                # class_name
                cn_match = CLASS_NAME_RE.search(content)
                if cn_match:
                    node.class_name = cn_match.group(1)
                    class_to_file[node.class_name] = rel_path

                # extends
                ext_match = EXTENDS_RE.search(content)
                if ext_match:
                    node.extends_class = ext_match.group(1)

                # preloads
                for pl in PRELOAD_RE.finditer(content):
                    node.preloaded_paths.append(pl.group(1))

                # signals declared
                for sig in SIGNAL_DECL_RE.finditer(content):
                    node.signals_declared.append(sig.group(1))

                # signals emitted
                for em in SIGNAL_EMIT_RE.finditer(content):
                    sig_name = em.group(2)
                    if sig_name not in ("emit", "is_connected", "connect", "disconnect"):
                        node.signals_emitted.append(sig_name)

                # signals connected
                for cn in SIGNAL_CONNECT_RE.finditer(content):
                    sig_name = cn.group(2)
                    if sig_name not in ("emit", "is_connected", "connect", "disconnect"):
                        node.signals_connected.append(sig_name)

                nodes[rel_path] = node

    # Add project Autoloads as known global symbols
    autoloads = {
        "MatchWorldModel": "autoloads/MatchWorldModel.gd",
        "GameEvents": "autoloads/GameEvents.gd",
        "GameManager": "autoloads/GameManager.gd",
        "MatchStatsTracker": "autoloads/MatchStatsTracker.gd",
        "DataLoader": "autoloads/DataLoader.gd",
        "RefereeLoader": "autoloads/RefereeLoader.gd",
        "ManagerLoader": "autoloads/ManagerLoader.gd",
        "InputHelper": "autoloads/InputHelper.gd",
    }
    class_to_file.update(autoloads)

    # 2. Second pass: resolve dependencies and build graph edges
    for rel_path, node in nodes.items():
        full_path = os.path.join(ROOT, rel_path)
        with open(full_path, "r", encoding="utf-8", errors="replace") as file_obj:
            content = file_obj.read()

        # Check extends
        if node.extends_class and node.extends_class in class_to_file:
            target = class_to_file[node.extends_class]
            if target != rel_path:
                node.direct_dependencies.add(target)

        # Check preloads / loads
        for pl in node.preloaded_paths:
            if pl in nodes and pl != rel_path:
                node.direct_dependencies.add(pl)

        # Check references to other class_names and Autoloads in file text
        for class_name, target_file in class_to_file.items():
            if target_file != rel_path and target_file in nodes:
                # Word boundary check
                pattern = r'\b' + re.escape(class_name) + r'\b'
                if re.search(pattern, content):
                    node.direct_dependencies.add(target_file)

    # 3. Third pass: calculate reverse dependents
    for rel_path, node in nodes.items():
        for dep in node.direct_dependencies:
            if dep in nodes:
                nodes[dep].direct_dependents.add(rel_path)

    return nodes, class_to_file


def calculate_blast_radius(target_path: str, nodes: dict[str, ScriptNode]) -> dict[str, Any]:
    norm_target = target_path.replace("\\", "/").replace("res://", "")
    if norm_target not in nodes:
        # Search by suffix or filename
        for k in nodes:
            if k.endswith(norm_target) or norm_target in k:
                norm_target = k
                break

    if norm_target not in nodes:
        return {"error": f"Target file '{target_path}' not found in repository."}

    target_node = nodes[norm_target]

    # Transitive BFS
    visited_dependents: set[str] = set()
    queue = list(target_node.direct_dependents)
    while queue:
        curr = queue.pop(0)
        if curr not in visited_dependents:
            visited_dependents.add(curr)
            if curr in nodes:
                for nxt in nodes[curr].direct_dependents:
                    if nxt not in visited_dependents:
                        queue.append(nxt)

    affected_layers: set[int] = {target_node.layer}
    for dep in visited_dependents:
        if dep in nodes:
            affected_layers.add(nodes[dep].layer)

    # Determine choke points impacted
    choke_points = []
    if "autoloads/MatchWorldModel.gd" in visited_dependents or norm_target == "autoloads/MatchWorldModel.gd":
        choke_points.append("MatchWorldModel.gd (Spatial Position Cache)")
    if "autoloads/GameEvents.gd" in visited_dependents or norm_target == "autoloads/GameEvents.gd":
        choke_points.append("GameEvents.gd (Inter-System Event Bus)")
    if "entities/player/HeavyPlayerController.gd" in visited_dependents or norm_target == "entities/player/HeavyPlayerController.gd":
        choke_points.append("HeavyPlayerController.gd (Kinematic Weight & Move-and-Slide)")
    if "entities/player/PlayerBrain.gd" in visited_dependents or norm_target == "entities/player/PlayerBrain.gd":
        choke_points.append("PlayerBrain.gd (AI Decision Stagger & Intent)")

    return {
        "target": norm_target,
        "class_name": target_node.class_name or "(none)",
        "layer": target_node.layer,
        "layer_name": LAYER_NAMES.get(target_node.layer, "Unknown"),
        "direct_dependencies_count": len(target_node.direct_dependencies),
        "direct_dependencies": sorted(list(target_node.direct_dependencies)),
        "direct_dependents_count": len(target_node.direct_dependents),
        "direct_dependents": sorted(list(target_node.direct_dependents)),
        "transitive_blast_radius_count": len(visited_dependents),
        "transitive_dependents": sorted(list(visited_dependents)),
        "affected_layers": [LAYER_NAMES.get(l, str(l)) for l in sorted(list(affected_layers))],
        "choke_points_impacted": choke_points,
        "signals_declared": target_node.signals_declared,
        "signals_emitted": sorted(list(set(target_node.signals_emitted))),
        "signals_connected": sorted(list(set(target_node.signals_connected))),
        "recommended_tests": [
            "python tools/gdcheck.py",
            "python tools/lint_invariants.py",
            "python tools/eval_simulation.py --duration=60"
        ]
    }


def export_graph_json(nodes: dict[str, ScriptNode], output_path: str) -> None:
    graph_data: dict[str, Any] = {
        "total_nodes": len(nodes),
        "layer_summary": {
            LAYER_NAMES[l]: len([n for n in nodes.values() if n.layer == l])
            for l in range(1, 6)
        },
        "nodes": {}
    }

    for rel_path, node in sorted(nodes.items()):
        graph_data["nodes"][rel_path] = {
            "class_name": node.class_name,
            "layer": node.layer,
            "layer_name": LAYER_NAMES.get(node.layer, "Unknown"),
            "extends": node.extends_class,
            "direct_dependencies": sorted(list(node.direct_dependencies)),
            "direct_dependents": sorted(list(node.direct_dependents)),
            "signals_declared": node.signals_declared,
            "signals_emitted": sorted(list(set(node.signals_emitted))),
            "signals_connected": sorted(list(set(node.signals_connected)))
        }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(graph_data, f, indent=2)


def print_blast_radius_report(report: dict[str, Any]) -> None:
    if "error" in report:
        print(f"[ERROR] {report['error']}", file=sys.stderr)
        return

    print("\n" + "=" * 70)
    print(f"       BLAST RADIUS REPORT: {report['target']}       ")
    print("=" * 70)
    print(f" Class Name:             {report['class_name']}")
    print(f" Primary Layer:          {report['layer_name']}")
    print(f" Direct Dependencies:    {report['direct_dependencies_count']}")
    print(f" Direct Dependents:      {report['direct_dependents_count']}")
    print(f" Transitive Blast Radius:{report['transitive_blast_radius_count']} files")
    print(f" Affected Layers:        {', '.join(report['affected_layers'])}")

    if report["choke_points_impacted"]:
        print(f"\n [!] Critical Choke Points Impacted:")
        for cp in report["choke_points_impacted"]:
            print(f"     • {cp}")

    if report["signals_declared"]:
        print(f"\n Signals Declared:       {', '.join(report['signals_declared'])}")
    if report["signals_emitted"]:
        print(f" Signals Emitted:        {', '.join(report['signals_emitted'])}")
    if report["signals_connected"]:
        print(f" Signals Connected:      {', '.join(report['signals_connected'])}")

    print("\n Direct Dependents:")
    for dep in report["direct_dependents"]:
        print(f"   -> {dep}")

    print("\n Recommended Verification Suites:")
    for test in report["recommended_tests"]:
        print(f"   $ {test}")
    print("=" * 70 + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Static Dependency DAG & Blast Radius Analyzer")
    parser.add_argument("--blast-radius", help="Calculate blast radius for target file")
    parser.add_argument("--output", default=OUTPUT_PATH, help="Output path for DEPENDENCY_GRAPH.json")
    args = parser.parse_args()

    nodes, class_to_file = scan_repository()
    export_graph_json(nodes, args.output)

    if args.blast_radius:
        report = calculate_blast_radius(args.blast_radius, nodes)
        print_blast_radius_report(report)
    else:
        print(f"[dump_dep_graph] Mapped {len(nodes)} GDScript files into Dependency DAG -> {args.output}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
