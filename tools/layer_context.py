#!/usr/bin/env python3
"""
layer_context.py — Targeted Simulation Layer Context Extractor.

Extracts layer-specific invariant rules, key file paths, choke points, and
rulebook excerpts for zero-waste prompt injection into autonomous LLM turns.

Usage:
  python tools/layer_context.py [1|2|3|4|5|physics|ai|social|club|narrative]
"""

from __future__ import annotations

import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LAYER_ALIASES = {
    "1": 1, "physics": 1, "kinematics": 1,
    "2": 2, "ai": 2, "match_ai": 2, "spatial": 2,
    "3": 3, "social": 3, "match_social": 3, "psychology": 3,
    "4": 4, "club": 4, "club_world": 4, "data": 4, "database": 4,
    "5": 5, "narrative": 5, "ui": 5, "presentation": 5,
}

LAYER_DATA = {
    1: {
        "title": "Layer 1 — Physics & Kinematics",
        "description": "Ball physics, pseudo-3D height trajectory, player kinematic bodies, turning penalties, pitch boundaries, and collision matrices.",
        "invariants": [
            "Direct velocity assignment on players is FORBIDDEN. Always use: v_t = move_toward(v_{t-1}, v_target, a_eff * delta).",
            "Turning penalty formula: a_eff = a_base * (1.0 - γ * (θ / π)) where θ = arccos(v̂_current · v̂_target).",
            "Pseudo-3D Ball: z(t+Δt) = z(t) + vz(t)*Δt - 0.5*g*(Δt)². Sprite Y offset = -z, Shadow scale = clamp(1.0 - z/300.0, 0.35, 1.0).",
            "Ball friction is proportional (velocity * coefficient + REST_DRAG_FLAT), NOT a constant deceleration.",
            "Collision Matrix: CharacterBody2D masks Layer 1 (World) + Layer 2 (Players) ONLY. NEVER mask Layer 3 (Ball) in CharacterBody2D.",
            "Ball interaction is sensed via Area2D on Layer 4 detecting Layer 3.",
            "Ball ownership: possessor (Node2D, active carrier) vs last_touched_by (HeavyPlayerController, last kicker)."
        ],
        "choke_points": [
            "entities/player/HeavyPlayerController.gd — Physics execution body. Reads movement_intent and wants_sprint from PlayerBrain. Never contains tactical utility logic.",
            "entities/ball/Pseudo3DBall.gd — Pseudo-3D ball solver. Manages z-axis gravity, bounce restitution, and proportional drag.",
            "shared/CollisionLayers.gd — Bitmask constants (Layer 1 World, Layer 2 Players, Layer 3 Ball, Layer 4 Hitboxes)."
        ],
        "key_files": [
            "entities/ball/Pseudo3DBall.gd",
            "entities/ball/BallState.gd",
            "entities/ball/BallStateFactory.gd",
            "entities/ball/states/FlightState.gd",
            "entities/ball/states/GroundRollState.gd",
            "entities/ball/states/PossessionState.gd",
            "entities/player/HeavyPlayerController.gd",
            "entities/player/PlayerState.gd",
            "entities/player/states/MoveState.gd",
            "entities/player/states/DribbleState.gd",
            "entities/player/states/ChargeKickState.gd",
            "entities/player/states/TackleState.gd",
            "entities/player/states/AerialState.gd",
            "pitch/PitchBoundary.gd",
            "pitch/GoalZone.gd",
            "pitch/PitchScene.gd",
            "shared/CollisionLayers.gd"
        ],
        "rule_file": ".claude/rules/soccer-physics.md"
    },
    2: {
        "title": "Layer 2 — Match AI & Spatial Navigation",
        "description": "Spatial indexing, utility scoring, time-sliced decision engines, dynamic formation anchors, goalkeeper dive AI, and officiating crew.",
        "invariants": [
            "Zero scene-tree polling: Calling get_tree().get_nodes_in_group() in _process or _physics_process is FORBIDDEN.",
            "All spatial reads must query MatchWorldModel.player_positions[i].",
            "Time-sliced decision updates: NPC tactical updates run on 15-frame stagger: (player_index + frame_count) % 15 == 0.",
            "Zero allocations in hot paths: Vector2(), Array(), RandomNumberGenerator.new() inside decision loops are FORBIDDEN.",
            "Defensive line depth: MatchWorldModel.defensive_line_x is computed ONCE per frame for each team, never per-defender.",
            "PlayerBrain writes ONLY player.movement_intent (Vector2) and player.wants_sprint (bool/scale) — never velocity or acceleration.",
            "PlayerRoleConfig.anchor_weight (0-1): 1.0 = rigid anchor, 0.0 = roam freely (the inverse of PlayerBrain roam alpha). Guard with `if player.role_config != null`."
        ],
        "choke_points": [
            "autoloads/MatchWorldModel.gd — ALL spatial reads route here. Owns 22-player cache + ball + defensive_line_x.",
            "entities/player/PlayerBrain.gd — Utility decision engine. Reads world model; writes ONLY movement_intent and wants_sprint.",
            "shared/PlayerRoleConfig.gd — Data-driven role tuning resource. Inverts anchor_weight when calculating open space roam alpha."
        ],
        "key_files": [
            "autoloads/MatchWorldModel.gd",
            "entities/player/PlayerBrain.gd",
            "shared/PassUtilityScorer.gd",
            "shared/UtilityMath.gd",
            "shared/FormationAnchorMath.gd",
            "shared/FormationLibrary.gd",
            "shared/FormationRegistry.gd",
            "shared/PlayerRoleConfig.gd",
            "entities/goalkeeper/GoalkeeperDiveBrain.gd",
            "entities/referee/MatchReferee.gd",
            "entities/referee/OffsideDetector.gd",
            "entities/manager/ManagerDirector.gd"
        ],
        "rule_file": ".claude/rules/ai-architect.md"
    },
    3: {
        "title": "Layer 3 — Match Social & Dynamic Psychology",
        "description": "Player form/mood dynamics (SLUMP/NORMAL/STREAK), passing trust dynamics, dynamic player performance ratings, and match event stats tracking.",
        "invariants": [
            "MoodSystem modifies scatter and confidence: SLUMP increases scatter (+35%), STREAK sharpens execution (-25%).",
            "TrustSystem tracks dynamic in-match passer-receiver trust based on pass completions, turnovers, and assists.",
            "Player ratings dynamically calculate between 1.0 and 10.0 based on positive/negative actions (passes, tackles, saves, goals, fouls).",
            "MatchStatsTracker accumulates per-player and per-team event metrics without interfering with physics processing."
        ],
        "choke_points": [
            "entities/player/MoodSystem.gd — Manages player psychological momentum and modifiers to physical actions.",
            "entities/player/TrustSystem.gd — Dynamic trust matrix biasing pass selection in PassUtilityScorer.",
            "autoloads/MatchStatsTracker.gd — Aggregates match events dispatched from GameEvents."
        ],
        "key_files": [
            "entities/player/MoodSystem.gd",
            "entities/player/TrustSystem.gd",
            "shared/PlayerRatingCalculator.gd",
            "autoloads/MatchStatsTracker.gd"
        ],
        "rule_file": None
    },
    4: {
        "title": "Layer 4 — Club World & Persistent Entities",
        "description": "Persistent player profiles, team rosters, manager personalities with trait bitmasks, referee officiating profiles, and JSON database loaders.",
        "invariants": [
            "Database integrity: All data files (data/league.json, data/managers.json, data/referees.json) must pass verify_db.py with 0 errors.",
            "Every squad in league.json contains 16-22 players with exactly 11 distinct starting lineup_indices (GK first).",
            "Manager data enforces 10-bit trait masks, prized attributes, and preferred playstyles.",
            "Referee data enforces personality spectrums (strictness, composure, unprofessionalism, incoherence).",
            "DataLoader, ManagerLoader, and RefereeLoader provide fallback hierarchy and bounds-safe queries."
        ],
        "choke_points": [
            "autoloads/DataLoader.gd — Single source of truth for player data, squads, and league database ingestion.",
            "autoloads/ManagerLoader.gd — Tactical manager profile catalog and persistence.",
            "autoloads/RefereeLoader.gd — Match referee personality catalog.",
            "shared/PlayerData.gd — Persistent player attributes, traits, and physical parameters.",
            "docs/json-schema.md — Formal schema specifications for external databases."
        ],
        "key_files": [
            "autoloads/DataLoader.gd",
            "autoloads/ManagerLoader.gd",
            "autoloads/RefereeLoader.gd",
            "shared/PlayerData.gd",
            "shared/TeamData.gd",
            "shared/TeamManagementData.gd",
            "shared/LeagueData.gd",
            "shared/ManagerData.gd",
            "shared/RefereeData.gd",
            "shared/PlayerFactory.gd",
            "docs/json-schema.md",
            "tools/verify_db.py"
        ],
        "rule_file": None
    },
    5: {
        "title": "Layer 5 — Narrative, Presentation & User Interface",
        "description": "Global event bus, match lifecycle manager, camera tracking modes, broadcast HUD, floating action text, touchline bubbles, and UI menus.",
        "invariants": [
            "GameEvents.gd is the ONLY inter-system signal hub. Cross-layer signals must never be emitted directly between components.",
            "GameManager.gd is the single source of truth for match state, score, clock, and set-piece phases.",
            "InputHelper.gd abstracts human keyboard and gamepad inputs uniformly.",
            "HUD, minimap, and action text render cleanly without altering simulation or physics state."
        ],
        "choke_points": [
            "autoloads/GameEvents.gd — ALL inter-system events propagate via signals on this bus.",
            "autoloads/GameManager.gd — Single source of truth for match lifecycle, score, clock, and set-piece states.",
            "autoloads/InputHelper.gd — Controller input mapping and device abstraction."
        ],
        "key_files": [
            "autoloads/GameEvents.gd",
            "autoloads/GameManager.gd",
            "autoloads/InputHelper.gd",
            "entities/manager/PressOffice.gd",
            "pitch/MatchCamera.gd",
            "pitch/Minimap.gd",
            "ui/HUD.gd",
            "ui/ActionText.gd",
            "ui/TouchlineBubble.gd",
            "ui/FormationDiagram.gd",
            "ui/MatchStatsUI.gd",
            "ui/pregame/PreGameScreen.gd",
            "ui/pause/PauseMenu.gd"
        ],
        "rule_file": None
    }
}


def read_rule_excerpt(rule_rel_path: str) -> str:
    full_path = os.path.join(ROOT, rule_rel_path)
    if not os.path.exists(full_path):
        return ""
    with open(full_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    return content


def print_layer_context(layer_id: int) -> None:
    data = LAYER_DATA[layer_id]
    print("=" * 80)
    print(f"[{data['title'].upper()}]")
    print("=" * 80)
    print(f"\nDESCRIPTION:\n  {data['description']}\n")

    print("CORE INVARIANTS & RULES:")
    for inv in data["invariants"]:
        print(f"  * {inv}")
    print("")

    print("CRITICAL CHOKE POINTS & CONTRACTS:")
    for cp in data["choke_points"]:
        print(f"  * {cp}")
    print("")

    print("KEY REPOSITORY FILES:")
    for kf in data["key_files"]:
        full_kf = os.path.join(ROOT, kf)
        status = "EXISTS" if os.path.exists(full_kf) else "MISSING"
        print(f"  - {kf} [{status}]")
    print("")

    if data.get("rule_file"):
        print(f"RELEVANT RULE EXCERPT ({data['rule_file']}):")
        excerpt = read_rule_excerpt(data["rule_file"])
        if excerpt:
            # Print indented
            for line in excerpt.splitlines():
                print(f"  | {line}")
            print("")
    print("=" * 80)


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python tools/layer_context.py [1|2|3|4|5|physics|ai|social|club|narrative]", file=sys.stderr)
        print("\nAvailable Layers:")
        for lid in range(1, 6):
            print(f"  {lid}: {LAYER_DATA[lid]['title']}")
        return 1

    query = sys.argv[1].lower().strip()
    layer_id = LAYER_ALIASES.get(query)
    if not layer_id or layer_id not in LAYER_DATA:
        print(f"[layer-context] Unknown layer: '{query}'. Choose 1, 2, 3, 4, or 5.", file=sys.stderr)
        return 1

    print_layer_context(layer_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
