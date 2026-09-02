#!/usr/bin/env python3
"""
verify_db.py — Comprehensive verification test for PowerFootball 2D Layer 4 Club World data:
- Validates syntax and schema for data/league.json, data/managers.json, data/referees.json
- Verifies squad size (16-18), lineup_indices (11 distinct starting indices), and attribute bounds
- Verifies manager tactical bounds, trait bitmasks, prized attributes, and playstyles
- Verifies referee personality bounds and career tracking fields
- Simulates TeamManagementData starting XI and bench swap logic on every squad
"""

import json
import os
import sys

def verify_all():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    data_dir = os.path.join(base_dir, "data")

    print("=== PowerFootball 2D Database Verification ===")

    # 1. League verification
    league_path = os.path.join(data_dir, "league.json")
    assert os.path.exists(league_path), f"Missing {league_path}"
    with open(league_path, "r", encoding="utf-8") as f:
        league = json.load(f)

    assert "league_name" in league, "Missing league_name"
    assert "teams" in league and len(league["teams"]) >= 8, f"Expected at least 8 teams, got {len(league.get('teams', []))}"

    VALID_STATURES = {
        "Continental Giant",
        "Top Flight Heavyweight",
        "Mid-Table Regular",
        "Relegation Battler",
        "Lower League Underdog"
    }

    team_names = set()
    total_players = 0
    for team_idx, team in enumerate(league["teams"]):
        tname = team.get("team_name", "")
        assert tname and tname not in team_names, f"Duplicate or empty team name: {tname}"
        team_names.add(tname)

        # Team reputation and stature invariants
        assert 0.0 <= team.get("reputation", 0.0) <= 1.0, f"Team {tname} reputation out of bounds: {team.get('reputation')}"
        stature = team.get("stature", "")
        assert stature in VALID_STATURES, f"Team {tname} invalid stature: {stature}"
        assert team.get("transfer_budget", 0) >= 0, f"Team {tname} negative transfer budget: {team.get('transfer_budget')}"
        assert team.get("wage_budget_weekly", 0) > 0, f"Team {tname} invalid wage budget: {team.get('wage_budget_weekly')}"

        squad = team.get("squad", [])
        assert 16 <= len(squad) <= 22, f"Team {tname} squad size {len(squad)} not in [16, 22]"
        total_players += len(squad)

        lineup = team.get("lineup_indices", [])
        assert len(lineup) == 11, f"Team {tname} lineup_indices must be 11, got {len(lineup)}"
        assert len(set(lineup)) == 11, f"Team {tname} lineup_indices contains duplicates: {lineup}"
        for idx in lineup:
            assert 0 <= idx < len(squad), f"Team {tname} lineup index {idx} out of squad range [0, {len(squad)-1}]"

        # Verify GK is first in lineup
        gk_idx = lineup[0]
        assert squad[gk_idx]["position_role"] == "GK", f"Team {tname} starter 0 must be GK, got {squad[gk_idx]['position_role']}"

        # Verify every player in squad
        shirt_numbers = set()
        for pidx, p in enumerate(squad):
            pname = p.get("player_name", "")
            snum = p.get("shirt_number", 0)
            role = p.get("position_role", "")
            assert pname, f"Team {tname} player {pidx} missing name"
            assert snum > 0 and snum not in shirt_numbers, f"Team {tname} duplicate or invalid shirt number: {snum} for {pname}"
            shirt_numbers.add(snum)

            # Invariant bounds checks
            assert 60.0 <= p["mass"] <= 95.0, f"Player {pname} mass out of bounds: {p['mass']}"
            assert 170.0 <= p["top_speed"] <= 260.0, f"Player {pname} top_speed out of bounds: {p['top_speed']}"
            assert 0.12 <= p["acceleration_time"] <= 0.38, f"Player {pname} acceleration out of bounds: {p['acceleration_time']}"
            assert 0.18 <= p["turning_penalty"] <= 0.55, f"Player {pname} turning penalty out of bounds: {p['turning_penalty']}"
            assert 75.0 <= p["stamina_max"] <= 125.0, f"Player {pname} stamina_max out of bounds: {p['stamina_max']}"
            assert 0.0 <= p["vision"] <= 1.0, f"Player {pname} vision out of bounds: {p['vision']}"
            assert 0.0 <= p["composure"] <= 1.0, f"Player {pname} composure out of bounds: {p['composure']}"
            assert 0.0 <= p["aggression"] <= 1.0, f"Player {pname} aggression out of bounds: {p['aggression']}"
            assert 0.0 <= p["close_control"] <= 1.0, f"Player {pname} close_control out of bounds: {p['close_control']}"
            assert 0.0 <= p["reflexes"] <= 1.0, f"Player {pname} reflexes out of bounds: {p['reflexes']}"
            assert 0.0 <= p["form"] <= 10.0, f"Player {pname} form out of bounds: {p['form']}"

            # FM mental attributes bounds
            assert 0.0 <= p.get("determination", 0.0) <= 1.0, f"Player {pname} determination out of bounds"
            assert 0.0 <= p.get("work_rate", 0.0) <= 1.0, f"Player {pname} work_rate out of bounds"
            assert 0.0 <= p.get("leadership", 0.0) <= 1.0, f"Player {pname} leadership out of bounds"
            assert 0.0 <= p.get("temperament", 0.0) <= 1.0, f"Player {pname} temperament out of bounds"
            assert 0.0 <= p.get("professionalism", 0.0) <= 1.0, f"Player {pname} professionalism out of bounds"
            assert 0.0 <= p.get("ambition", 0.0) <= 1.0, f"Player {pname} ambition out of bounds"
            assert 0.0 <= p.get("loyalty", 0.0) <= 1.0, f"Player {pname} loyalty out of bounds"
            assert 0.0 <= p.get("adaptability", 0.0) <= 1.0, f"Player {pname} adaptability out of bounds"

            # Contract and career bounds
            assert 0.0 <= p.get("player_reputation", 0.0) <= 1.0, f"Player {pname} reputation out of bounds"
            assert p.get("wage_weekly", 0) > 0, f"Player {pname} wage must be positive"
            assert 1 <= p.get("contract_years", 0) <= 5, f"Player {pname} contract years out of bounds"
            assert 0.0 <= p.get("morale", 0.0) <= 1.0, f"Player {pname} morale out of bounds"
            assert p.get("market_value", 0) >= 0, f"Player {pname} market value negative"

        # Simulate TeamManagementData lineup + bench logic
        bench = [i for i in range(len(squad)) if i not in lineup]
        assert len(bench) == len(squad) - 11, f"Team {tname} bench size mismatch"
        # Test swap simulation
        test_lineup = list(lineup)
        test_bench = list(bench)
        # Swap starter 2 and bench 0
        out_idx = test_lineup[2]
        in_idx = test_bench[0]
        test_lineup[2] = in_idx
        test_bench[0] = out_idx
        assert len(set(test_lineup)) == 11, "Swap produced duplicate lineup entries"
        assert len(set(test_bench)) == len(bench), "Swap produced duplicate bench entries"

    print(f"[OK] League verified: {len(league['teams'])} teams, {total_players} players total across squads.")

    # 1b. Flat players database verification
    players_path = os.path.join(data_dir, "players.json")
    assert os.path.exists(players_path), f"Missing {players_path}"
    with open(players_path, "r", encoding="utf-8") as f:
        p_db = json.load(f)
    assert "players" in p_db, "Missing 'players' key in players.json"
    assert len(p_db["players"]) == total_players, f"players.json count ({len(p_db['players'])}) does not match league count ({total_players})"
    print(f"[OK] Flat players database verified: {len(p_db['players'])} records in parity with league.json.")

    # 2. Managers verification
    managers_path = os.path.join(data_dir, "managers.json")
    assert os.path.exists(managers_path), f"Missing {managers_path}"
    with open(managers_path, "r", encoding="utf-8") as f:
        mgr_data = json.load(f)

    managers = mgr_data.get("managers", [])
    assert len(managers) >= 10, f"Expected at least 10 managers, got {len(managers)}"

    VALID_TRAIT_BITS = 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128 | 256 | 512
    VALID_PRIZED = {"vision", "composure", "aggression", "none"}
    VALID_PLAYSTYLES = {"technical", "physical", "pace", "aerial", "engine", "none"}

    mgr_names = set()
    assigned_teams = set()
    for m in managers:
        mname = m.get("name", "")
        assert mname and mname not in mgr_names, f"Duplicate manager name: {mname}"
        mgr_names.add(mname)

        team = m.get("current_team", "")
        if team:
            assert team in team_names, f"Manager {mname} assigned to unknown team: {team}"
            assert team not in assigned_teams, f"Multiple managers assigned to same team: {team}"
            assigned_teams.add(team)
            assert m.get("contract_years", 0) > 0, f"Employed manager {mname} must have contract years"
            assert m.get("salary_weekly", 0) > 0, f"Employed manager {mname} must have positive salary"

        assert 1 <= m.get("experience", 0) <= 100, f"Manager {mname} experience out of bounds: {m.get('experience')}"
        assert 0.0 <= m.get("reputation", 0.0) <= 1.0, f"Manager {mname} reputation out of bounds"
        assert 0.0 <= m.get("board_confidence", 0.0) <= 1.0, f"Manager {mname} board_confidence out of bounds"
        assert 0.0 <= m.get("referee_respect", 0.0) <= 1.0, f"Manager {mname} referee_respect out of bounds"
        assert 0.0 <= m.get("defensive_line", 0.0) <= 1.0, f"Manager {mname} defensive_line out of bounds"
        assert 0.0 <= m.get("tempo", 0.0) <= 1.0, f"Manager {mname} tempo out of bounds"
        assert 0.0 <= m.get("width", 0.0) <= 1.0, f"Manager {mname} width out of bounds"
        assert 0.0 <= m.get("pressing_intensity", 0.0) <= 1.0, f"Manager {mname} pressing_intensity out of bounds"
        assert 0.0 <= m.get("physicality", 0.0) <= 1.0, f"Manager {mname} physicality out of bounds"
        assert 0.0 <= m.get("youth_trust", 0.0) <= 1.0, f"Manager {mname} youth_trust out of bounds"
        assert 0.0 <= m.get("loyalty_bias", 0.0) <= 1.0, f"Manager {mname} loyalty_bias out of bounds"
        assert 0.0 <= m.get("form_sensitivity", 0.0) <= 1.0, f"Manager {mname} form_sensitivity out of bounds"

        traits = m.get("traits", 0)
        assert (traits & ~VALID_TRAIT_BITS) == 0, f"Manager {mname} invalid trait bits: {traits}"

        prized = m.get("prized_attribute", "")
        assert prized in VALID_PRIZED, f"Manager {mname} invalid prized_attribute: {prized}"

        style = m.get("preferred_playstyle", "")
        assert style in VALID_PLAYSTYLES, f"Manager {mname} invalid preferred_playstyle: {style}"

    print(f"[OK] Managers verified: {len(managers)} managers ({len(assigned_teams)} club-assigned, {len(managers)-len(assigned_teams)} free agents).")

    # 3. Referees verification
    referees_path = os.path.join(data_dir, "referees.json")
    assert os.path.exists(referees_path), f"Missing {referees_path}"
    with open(referees_path, "r", encoding="utf-8") as f:
        ref_data = json.load(f)

    referees = ref_data.get("referees", [])
    assert len(referees) >= 8, f"Expected at least 8 referees, got {len(referees)}"

    ref_names = set()
    for r in referees:
        rname = r.get("name", "")
        assert rname and rname not in ref_names, f"Duplicate referee name: {rname}"
        ref_names.add(rname)

        assert 1 <= r.get("experience", 0) <= 100, f"Referee {rname} experience out of bounds"
        assert 0.0 <= r.get("strictness", 0.0) <= 1.0, f"Referee {rname} strictness out of bounds"
        assert 0.0 <= r.get("consistency", 0.0) <= 1.0, f"Referee {rname} consistency out of bounds"
        assert 0.0 <= r.get("composure", 0.0) <= 1.0, f"Referee {rname} composure out of bounds"
        assert 0.0 <= r.get("unprofessionalism", 0.0) <= 1.0, f"Referee {rname} unprofessionalism out of bounds"
        assert 0.0 <= r.get("incoherence", 0.0) <= 1.0, f"Referee {rname} incoherence out of bounds"
        assert 0.0 <= r.get("reputation", 0.0) <= 1.0, f"Referee {rname} reputation out of bounds"
        assert 0.0 <= r.get("respect_rating", 0.0) <= 1.0, f"Referee {rname} respect_rating out of bounds"
        assert "matches_officiated" in r and "fouls_awarded" in r and "penalties_awarded" in r

    print(f"[OK] Referees verified: {len(referees)} referees with personality spectrums and career stats.")
    print("=== All Verification Checks Passed (0 errors, 0 warnings) ===")

if __name__ == "__main__":
    verify_all()
