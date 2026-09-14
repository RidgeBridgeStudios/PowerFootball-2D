#!/usr/bin/env python3
"""
layer_context.py — Targeted Simulation Layer Context Extractor.

Extracts layer-specific invariant rules, key file paths, choke points, and
rulebook excerpts for zero-waste prompt injection into autonomous LLM turns.

This tool exposes the CURRENT 3-layer stack. The pre-pivot 1-5 taxonomy is gone:
Layers 1-3 (Physics & Kinematics / Match AI & Spatial / Match Social) collapsed
into the single Quick-Sim Match layer, the old Layer 4 (Club World) is now
Layer 1 (Career World), and the old Layer 5 (Narrative & Presentation) is now
Layer 3. The retired real-time match layer is archived under legacy/ behind
legacy/.gdignore and is intentionally absent from every key-file list below.

Pre-pivot id/name -> current layer:
    pre-pivot 1 physics, kinematics      -> 2 (Quick-Sim Match)
    pre-pivot 2 ai, match_ai, spatial    -> 2 (Quick-Sim Match)
    pre-pivot 3 social, match_social     -> 2 (Quick-Sim Match)
    pre-pivot 4 club, club_world, data   -> 1 (Career World)
    pre-pivot 5 narrative, ui            -> 3 (Narrative & Presentation)

Usage:
  python tools/layer_context.py [1|2|3|career|quicksim|narrative|...]
"""

from __future__ import annotations

import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Aliases: current 3-layer names, plus the pre-pivot 1-5 ids and names remapped
# onto their closest live layer so existing callers keep working. Note the
# numeric ids always mean the CURRENT taxonomy: "3" is Narrative, while the
# pre-pivot name "social" maps to Quick-Sim Match (2).
LAYER_ALIASES = {
    # Layer 1 — Career World
    "1": 1, "career": 1, "career_world": 1,
    "4": 1, "club": 1, "club_world": 1, "data": 1, "database": 1,
    # Layer 2 — Quick-Sim Match
    "2": 2, "quicksim": 2, "quick_sim": 2, "match": 2, "simulation": 2, "math": 2,
    "physics": 2, "kinematics": 2,
    "ai": 2, "match_ai": 2, "spatial": 2,
    "social": 2, "match_social": 2, "psychology": 2,
    # Layer 3 — Narrative & Presentation
    "3": 3, "narrative": 3, "presentation": 3, "ui": 3, "press": 3, "events": 3,
    "5": 3,
}

LAYER_DATA = {
    1: {
        "title": "Layer 1 — Career World",
        "description": "Persistent manager-only career state: the live CareerSaveData, the league database (squads, staff, attributes), finances, morale, board confidence, transfers, scouting, player development, and the season calendar.",
        "invariants": [
            "CareerManager owns the ONLY live CareerSaveData. The league (squads, staff, attributes) stays owned by DataLoader and is saved per slot via DataLoader.save_league().",
            "A CareerSaveData is constructed only by CareerSaveData.make_new() (called from CareerManager) or CareerSerializer.load_from_slot(). Never build a second save state anywhere else.",
            "Squad index is player identity; transfers repair lineups and player states rather than re-keying players.",
            "Database integrity: data/{league,players,managers,referees,staff}.json must pass tools/verify_db.py with 0 errors; every squad holds 16-22 players and exactly 11 distinct lineup_indices (GK first).",
            "All career randomness flows through CareerManager's seeded _rng (seeded from CareerSaveData.rng_seed); never call the global randf()/randi() in the career layer.",
            "Strict typing on every variable, parameter and return type; no Pythonisms (None/True/False/def/len/isinstance/import) and no object-to-string comparisons.",
        ],
        "choke_points": [
            "autoloads/CareerManager.gd — Owns the live CareerSaveData; simulate_next_fixture() is the match-day entry point and _apply_fixture_result() folds the result into the table, finances, morale, board confidence and cups.",
            "autoloads/DataLoader.gd — Owns DataLoader.league (squads, staff, attributes) and persists it per slot via save_league().",
            "shared/career/CareerSerializer.gd — The only read/write path for a career slot; the only CareerSaveData constructor besides CareerSaveData.make_new().",
            "autoloads/GameEvents.gd — The only cross-layer signal bus; career state never talks to presentation directly.",
        ],
        "key_files": [
            "autoloads/CareerManager.gd",
            "autoloads/DataLoader.gd",
            "autoloads/ManagerLoader.gd",
            "autoloads/RefereeLoader.gd",
            "autoloads/StaffLoader.gd",
            "shared/career/CareerSaveData.gd",
            "shared/career/CareerSerializer.gd",
            "shared/career/CompetitionData.gd",
            "shared/TeamData.gd",
            "shared/PlayerData.gd",
            "shared/LeagueData.gd",
            "shared/ManagerData.gd",
            "shared/RefereeData.gd",
            "shared/StaffData.gd",
            "shared/TeamManagementData.gd",
            "shared/NationDatabase.gd",
            "shared/CareerProgressionEngine.gd",
            "data/league.json"
        ],
        "rule_file": ".claude/rules/career-mode.md"
    },
    2: {
        "title": "Layer 2 — Quick-Sim Match",
        "description": "Statistical match resolution: the QuickSimEngine Poisson/Dixon-Coles model, per-player rating calculation, the shared allocation-free math solvers, the MatchStatsTracker container, and the GameManager scoreboard boundary. There is no player control, ball physics, real-time frames or per-frame AI.",
        "invariants": [
            "Matches resolve entirely by statistics: shared/QuickSimEngine.gd is the only thing that produces a match result.",
            "QuickSimEngine.apply_to_match_stats_tracker() is the single publish point. It writes GameManager (score / current_phase / match_time / simulated_match_time) and fills MatchStatsTracker; no other code may publish a match outcome.",
            "MatchStatsTracker is a passive container (reset(), stop_possession_sampling() no-op, get_player_events(), compute_all_ratings(), get_stats(), get_advanced_stats()). It never polls the scene tree and never subscribes to real-time events; possession_pct reports its neutral 50.0 fallback.",
            "GameManager is a thin scoreboard shell: TEAM_A, TEAM_B, enum MatchPhase { PREGAME, FULL_TIME }, current_phase, score, match_time, match_duration, half_duration_real_sec, simulated_match_time, set_half_duration(). Never reintroduce a phase machine, clock or set-piece state there.",
            "Zero hot-path allocation: no .new(), Array literals or Dictionary literals inside the live shared/UtilityMath.gd solvers (calculate_intercept_point, solve_pass_intercept, closest_point_on_segment, distance_squared_to_segment, distance_to_segment).",
        ],
        "choke_points": [
            "shared/QuickSimEngine.gd — Statistical resolver. calculate_probabilities() / simulate_match() are pure; apply_to_match_stats_tracker() is the single publish point into GameManager + MatchStatsTracker.",
            "autoloads/MatchStatsTracker.gd — Flat stats container written only by QuickSimEngine and read back by MatchStatsUI.",
            "autoloads/GameManager.gd — Scoreboard boundary between the career world and a resolved fixture.",
            "shared/UtilityMath.gd — Live allocation-free math helper class (deliberately KEPT, not archived), used by QuickSimEngine and the solver fuzzers.",
        ],
        "key_files": [
            "shared/QuickSimEngine.gd",
            "shared/PlayerRatingCalculator.gd",
            "shared/UtilityMath.gd",
            "autoloads/MatchStatsTracker.gd",
            "autoloads/GameManager.gd"
        ],
        "rule_file": None
    },
    3: {
        "title": "Layer 3 — Narrative & Presentation",
        "description": "The event log, press office and manager-mode UI: the GameEvents signal bus, narrative generation, and the presentation panels that react to signals instead of polling simulation state.",
        "invariants": [
            "GameEvents.gd is the ONLY inter-system signal hub and carries exactly 11 signals (formation_changed, lineup_changed, career_started, career_day_advanced, career_advance_halted, career_inbox_changed, career_match_ready, career_result_recorded, career_season_ended, career_manager_sacked, world_event_logged).",
            "Never widen an existing signal signature: append a NEW signal instead, because under-declared listeners break silently.",
            "Presentation reacts to GameEvents; it never emits cross-system signals from a component and never polls the scene tree with get_tree().get_nodes_in_group().",
            "The career UI never leaves ui/manager_mode/ManagerModeRoot.gd to play a match: _on_continue_pressed() calls CareerManager.simulate_next_fixture().",
            "WorldEventLog is not the owner of the events: CareerSaveData.world_events is the persisted array, and WorldEventLog.log_event() is the single append path (plus the world_event_logged emit).",
            "UI reads state; it never writes MatchStatsTracker or publishes a GameManager match result.",
        ],
        "choke_points": [
            "autoloads/GameEvents.gd — ALL inter-system events propagate via signals on this bus.",
            "autoloads/WorldEventLog.gd — Live view over CareerSaveData.world_events; bind(), log_event(), record() and the query helpers are the only access path.",
            "ui/manager_mode/ManagerModeRoot.gd — The career shell; the Continue loop resolves fixtures through CareerManager.simulate_next_fixture().",
            "entities/manager/PressOffice.gd — Stateless quote generator driven by the event log.",
        ],
        "key_files": [
            "autoloads/GameEvents.gd",
            "autoloads/WorldEventLog.gd",
            "entities/manager/PressOffice.gd",
            "ui/manager_mode/ManagerModeRoot.gd",
            "ui/manager_mode/TacticsPanel.gd",
            "ui/MainMenu.gd",
            "ui/OptionsMenu.gd",
            "ui/MatchStatsUI.gd",
            "ui/QuickSimModal.gd"
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
        print("Usage: python tools/layer_context.py [1|2|3|career|quicksim|narrative|...]", file=sys.stderr)
        print("\nLive 3-layer stack (pre-pivot ids/names are accepted as aliases):", file=sys.stderr)
        for lid in range(1, 4):
            print(f"  {lid}: {LAYER_DATA[lid]['title']}", file=sys.stderr)
        return 1

    query = sys.argv[1].lower().strip()
    layer_id = LAYER_ALIASES.get(query)
    if not layer_id or layer_id not in LAYER_DATA:
        print(
            f"[layer-context] Unknown layer: '{query}'. Choose 1 (Career World), 2 (Quick-Sim Match), "
            "or 3 (Narrative & Presentation); pre-pivot names such as physics/ai/social/club/narrative are remapped.",
            file=sys.stderr
        )
        return 1

    print_layer_context(layer_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
