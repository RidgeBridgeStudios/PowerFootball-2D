#!/usr/bin/env python3
"""
dump_api.py — Public API Surface Generator for PowerFootball-2D.

Parses all .gd scripts in the project and extracts:
- class_name and extends hierarchy
- signals and parameters
- enums and definitions
- public constants
- @export variables
- public functions and static functions with argument/return type annotations

Strips private members (_func, _var), function bodies, and inline comments.
Outputs a structured markdown document to docs/API_SURFACE.md categorized
by the 5 Simulation Layers.
"""

from __future__ import annotations

import os
import re
import sys
from typing import Dict, List, Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.path.join(ROOT, "docs", "API_SURFACE.md")

LAYER_MAPPING = {
    # Layer 1: Physics & Kinematics
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

    # Layer 2: Match AI & Spatial Navigation
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

    # Layer 3: Match Social & Dynamic Psychology
    "entities/player/MoodSystem.gd": 3,
    "entities/player/TrustSystem.gd": 3,
    "shared/PlayerRatingCalculator.gd": 3,
    "autoloads/MatchStatsTracker.gd": 3,

    # Layer 4: Club World & Persistent Entities
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

    # Layer 5: Narrative, Presentation & UI
    "autoloads/GameEvents.gd": 5,
    "autoloads/GameManager.gd": 5,
    "autoloads/InputHelper.gd": 5,
    "entities/manager/PressOffice.gd": 5,
    "entities/player/FacingArrow.gd": 5,
    "pitch/MatchCamera.gd": 5,
    "pitch/Minimap.gd": 5,
    "ui/": 5,
}

LAYER_METADATA = {
    1: {
        "name": "Layer 1 — Physics & Kinematics",
        "tag": "layer_1_physics",
        "desc": "Ball physics, pseudo-3D height trajectory, player kinematic body, turning penalties, pitch bounds, and collision layers."
    },
    2: {
        "name": "Layer 2 — Match AI & Spatial Navigation",
        "tag": "layer_2_match_ai",
        "desc": "Spatial indexing, utility scoring, time-sliced decision engines, dynamic formation anchors, goalkeeper dive AI, and officiating crew."
    },
    3: {
        "name": "Layer 3 — Match Social & Dynamic Psychology",
        "tag": "layer_3_match_social",
        "desc": "Player mood/form (SLUMP/NORMAL/STREAK), passing trust dynamics, performance rating calculator, and match event stats tracking."
    },
    4: {
        "name": "Layer 4 — Club World & Persistent Entities",
        "tag": "layer_4_club_world",
        "desc": "Persistent player profiles, team rosters, manager personalities, referee attributes, league standings, and JSON database loaders."
    },
    5: {
        "name": "Layer 5 — Narrative, Presentation & User Interface",
        "tag": "layer_5_narrative",
        "desc": "Global event bus, match lifecycle manager, camera tracking, HUD, minimap, touchline dialogue, and pre/pause menu interfaces."
    },
}


def get_layer_for_path(rel_path: str) -> int:
    normalized = rel_path.replace("\\", "/")
    # Exact match first
    if normalized in LAYER_MAPPING:
        return LAYER_MAPPING[normalized]
    # Prefix match
    for prefix, layer in LAYER_MAPPING.items():
        if normalized.startswith(prefix):
            return layer
    # Fallback heuristic
    if normalized.startswith("ui/"):
        return 5
    if normalized.startswith("pitch/"):
        return 1
    if normalized.startswith("autoloads/"):
        return 5
    return 1


class ScriptAPI:
    def __init__(self, rel_path: str) -> None:
        self.rel_path: str = rel_path.replace("\\", "/")
        self.class_name: Optional[str] = None
        self.extends: Optional[str] = None
        self.signals: List[str] = []
        self.enums: List[str] = []
        self.constants: List[str] = []
        self.exports: List[str] = []
        self.public_vars: List[str] = []
        self.public_methods: List[str] = []


def parse_gd_file(file_path: str, rel_path: str) -> ScriptAPI:
    api = ScriptAPI(rel_path)
    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    i = 0
    num_lines = len(lines)
    while i < num_lines:
        line = lines[i]
        stripped = line.strip()

        # Skip comment-only or empty lines
        if not stripped or stripped.startswith("#"):
            i += 1
            continue

        # Strip inline comment
        code_part = stripped
        if "#" in code_part:
            parts = code_part.split("#", 1)
            code_part = parts[0].strip()

        if not code_part:
            i += 1
            continue

        # Top-level checks
        is_top_level = not line.startswith((" ", "\t"))

        if is_top_level:
            # class_name
            m_class = re.match(r"^class_name\s+([A-Za-z0-9_]+)", code_part)
            if m_class:
                api.class_name = m_class.group(1)
                i += 1
                continue

            # extends
            m_extends = re.match(r"^extends\s+([A-Za-z0-9_.]+)", code_part)
            if m_extends:
                api.extends = m_extends.group(1)
                i += 1
                continue

            # signal
            m_signal = re.match(r"^signal\s+([A-Za-z0-9_]+(?:\([^)]*\))?)", code_part)
            if m_signal:
                api.signals.append(f"signal {m_signal.group(1)}")
                i += 1
                continue

            # enum
            m_enum = re.match(r"^enum\s+([A-Za-z0-9_]+)?\s*\{([^}]*)\}?", code_part)
            if m_enum:
                enum_name = m_enum.group(1) or ""
                enum_content = m_enum.group(2) or ""
                # Check multi-line enum
                if "}" not in code_part:
                    while i + 1 < num_lines and "}" not in lines[i + 1]:
                        i += 1
                        enum_content += " " + lines[i].strip()
                    if i + 1 < num_lines and "}" in lines[i + 1]:
                        i += 1
                        enum_content += " " + lines[i].split("}")[0].strip()
                # Clean up enum content
                clean_items = [item.strip() for item in enum_content.split(",") if item.strip() and not item.strip().startswith("#")]
                api.enums.append(f"enum {enum_name} {{ {', '.join(clean_items)} }}".strip())
                i += 1
                continue

            # @export var
            if "@export" in code_part and ("var " in code_part or "var\t" in code_part):
                var_decl = code_part
                api.exports.append(var_decl)
                i += 1
                continue

            # public const (skip _CONST)
            m_const = re.match(r"^const\s+([A-Za-z0-9]+[A-Za-z0-9_]*)\s*(?::\s*[^=]+)?\s*=\s*(.*)", code_part)
            if m_const:
                const_name = m_const.group(1)
                if not const_name.startswith("_"):
                    decl = code_part
                    if len(decl) > 100:
                        decl = decl[:97] + "..."
                    api.constants.append(decl)
                i += 1
                continue

            # public func or static func
            m_func = re.match(r"^(?:static\s+)?func\s+([A-Za-z0-9_]+)\s*\(", code_part)
            if m_func:
                func_name = m_func.group(1)
                if not func_name.startswith("_"):
                    full_sig = code_part
                    while not full_sig.endswith(":") and i + 1 < num_lines:
                        i += 1
                        next_line = lines[i].strip()
                        if "#" in next_line:
                            next_line = next_line.split("#", 1)[0].strip()
                        full_sig += " " + next_line
                    if full_sig.endswith(":"):
                        full_sig = full_sig[:-1].strip()
                    api.public_methods.append(full_sig)
                i += 1
                continue

        i += 1

    return api


def generate_markdown(apis: List[ScriptAPI]) -> str:
    by_layer: Dict[int, List[ScriptAPI]] = {1: [], 2: [], 3: [], 4: [], 5: []}
    total_methods = 0
    total_signals = 0
    total_exports = 0

    for api in sorted(apis, key=lambda x: x.rel_path):
        layer = get_layer_for_path(api.rel_path)
        by_layer[layer].append(api)
        total_methods += len(api.public_methods)
        total_signals += len(api.signals)
        total_exports += len(api.exports)

    md = []
    md.append("# PowerFootball-2D — Public API Surface Map")
    md.append("")
    md.append("> **Auto-generated by `tools/dump_api.py`**")
    md.append("> **Architecture & Verification:** Godot 4.7-stable · GDScript 2.0 Strict Typing · 5-Layer Simulation Stack")
    md.append("")
    md.append(f"**Total Scripts:** {len(apis)} | **Public Methods:** {total_methods} | **Signals:** {total_signals} | **Exported Properties:** {total_exports}")
    md.append("")
    md.append("---")
    md.append("")
    md.append("## Table of Contents")
    for l_id in range(1, 6):
        meta = LAYER_METADATA[l_id]
        md.append(f"- [{meta['name']}](#{meta['name'].lower().replace(' ', '-').replace('—', '').replace('&', '').replace('  ', '-')}) ({len(by_layer[l_id])} scripts)")
    md.append("")
    md.append("---")
    md.append("")

    for l_id in range(1, 6):
        meta = LAYER_METADATA[l_id]
        md.append(f"<{meta['tag']}>")
        md.append(f"## {meta['name']}")
        md.append(f"*{meta['desc']}*")
        md.append("")

        for api in by_layer[l_id]:
            md.append(f"### `{api.rel_path}`")
            headers = []
            if api.class_name:
                headers.append(f"**class_name:** `{api.class_name}`")
            if api.extends:
                headers.append(f"**extends:** `{api.extends}`")
            if headers:
                md.append(" · ".join(headers))
                md.append("")

            has_members = False

            if api.signals:
                has_members = True
                md.append("**Signals:**")
                for s in api.signals:
                    md.append(f"- `{s}`")
                md.append("")

            if api.enums:
                has_members = True
                md.append("**Enums:**")
                for e in api.enums:
                    md.append(f"- `{e}`")
                md.append("")

            if api.constants:
                has_members = True
                md.append("**Constants:**")
                for c in api.constants:
                    md.append(f"- `{c}`")
                md.append("")

            if api.exports:
                has_members = True
                md.append("**Exported Properties:**")
                for exp in api.exports:
                    md.append(f"- `{exp}`")
                md.append("")

            if api.public_methods:
                has_members = True
                md.append("**Public Methods:**")
                for m in api.public_methods:
                    md.append(f"- `{m}`")
                md.append("")

            if not has_members:
                md.append("*No public signals, exports, or methods (internal lifecycle/state).*")
                md.append("")

            md.append("---")
            md.append("")

        md.append(f"</{meta['tag']}>")
        md.append("")

    return "\n".join(md)


def main() -> int:
    target_output = sys.argv[1] if len(sys.argv) > 1 else OUTPUT_PATH
    scripts = []

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in (".git", "addons", ".claude")]
        for name in filenames:
            if name.endswith(".gd"):
                full_path = os.path.join(dirpath, name)
                rel_path = os.path.relpath(full_path, ROOT)
                scripts.append((full_path, rel_path))

    apis = []
    for full_path, rel_path in scripts:
        apis.append(parse_gd_file(full_path, rel_path))

    md_content = generate_markdown(apis)

    os.makedirs(os.path.dirname(target_output), exist_ok=True)
    with open(target_output, "w", encoding="utf-8") as f:
        f.write(md_content)

    print(f"[dump-api] Successfully generated API surface for {len(apis)} scripts -> {os.path.relpath(target_output, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
