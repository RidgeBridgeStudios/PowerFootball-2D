#!/usr/bin/env python3
"""
validate_schemas.py — Strict JSON Schema & Invariant Validator for PowerFootball-2D Databases.

Validates data/league.json, data/managers.json, and data/referees.json against
strict schema definitions, physical parameter bounds, trait bitmasks, and team associations.

Usage:
    python tools/validate_schemas.py [--xml]
"""

from __future__ import annotations

import argparse
import html
import json
import os
import sys
from typing import Any, Dict, List, Set, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, "data")


class SchemaViolation:
    def __init__(self, rule_id: str, file_path: str, entity_name: str, message: str, severity: str = "ERROR") -> None:
        self.rule_id = rule_id
        self.file_path = file_path
        self.entity_name = entity_name
        self.message = message
        self.severity = severity

    def __str__(self) -> str:
        rel = os.path.relpath(self.file_path, ROOT).replace("\\", "/")
        return f"{self.severity:<5} [{self.rule_id}] {rel} ({self.entity_name}): {self.message}"


def validate_league_schema(league_path: str) -> tuple[list[SchemaViolation], set[str]]:
    violations: list[SchemaViolation] = []
    team_names: set[str] = set()

    if not os.path.exists(league_path):
        return [SchemaViolation("SCHEMA-01-MISSING-FILE", league_path, "league", "File data/league.json is missing")], team_names

    try:
        with open(league_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return [SchemaViolation("SCHEMA-02-INVALID-JSON", league_path, "league", f"Invalid JSON syntax: {e}")], team_names

    if "league_name" not in data or not isinstance(data["league_name"], str) or not data["league_name"]:
        violations.append(SchemaViolation("SCHEMA-03-LEAGUE-PROP", league_path, "league", "Missing or invalid 'league_name'"))

    teams = data.get("teams", [])
    if not isinstance(teams, list) or len(teams) < 8:
        violations.append(SchemaViolation("SCHEMA-04-TEAM-COUNT", league_path, "league", f"Expected >= 8 teams, got {len(teams)}"))

    for t_idx, team in enumerate(teams):
        tname = team.get("team_name", "")
        if not tname or not isinstance(tname, str):
            violations.append(SchemaViolation("SCHEMA-05-TEAM-NAME", league_path, f"team_{t_idx}", "Missing or empty 'team_name'"))
            continue
        if tname in team_names:
            violations.append(SchemaViolation("SCHEMA-06-DUPLICATE-TEAM", league_path, tname, f"Duplicate team name: '{tname}'"))
        team_names.add(tname)

        squad = team.get("squad", [])
        if not isinstance(squad, list) or not (16 <= len(squad) <= 22):
            violations.append(SchemaViolation("SCHEMA-07-SQUAD-SIZE", league_path, tname, f"Squad size {len(squad)} out of range [16, 22]"))

        lineup = team.get("lineup_indices", [])
        if not isinstance(lineup, list) or len(lineup) != 11:
            violations.append(SchemaViolation("SCHEMA-08-LINEUP-SIZE", league_path, tname, f"lineup_indices must contain 11 starters, got {len(lineup)}"))
        elif len(set(lineup)) != 11:
            violations.append(SchemaViolation("SCHEMA-09-LINEUP-DUPLICATES", league_path, tname, f"lineup_indices contains duplicates: {lineup}"))
        else:
            for l_idx in lineup:
                if not isinstance(l_idx, int) or l_idx < 0 or l_idx >= len(squad):
                    violations.append(SchemaViolation("SCHEMA-10-LINEUP-BOUNDS", league_path, tname, f"Lineup index {l_idx} out of squad bounds [0, {len(squad)-1}]"))

            # GK must be at index 0 of lineup
            if len(squad) > 0 and 0 <= lineup[0] < len(squad):
                gk = squad[lineup[0]]
                if gk.get("position_role") != "GK":
                    violations.append(SchemaViolation("SCHEMA-11-GK-FIRST", league_path, tname, f"Starter 0 must have position_role 'GK', got '{gk.get('position_role')}'"))

        shirt_numbers: set[int] = set()
        player_names: set[str] = set()
        for p_idx, player in enumerate(squad):
            pname = player.get("player_name", "")
            if not pname and player.get("first_name"):
                pname = f"{player.get('first_name')} {player.get('last_name', '')}".strip()

            if not pname:
                violations.append(SchemaViolation("SCHEMA-12-PLAYER-NAME", league_path, f"{tname}/player_{p_idx}", "Missing player name"))
                continue

            if pname in player_names:
                violations.append(SchemaViolation("SCHEMA-13-DUPLICATE-PLAYER", league_path, f"{tname}/{pname}", f"Duplicate player name '{pname}' in squad"))
            player_names.add(pname)

            snum = player.get("shirt_number")
            if not isinstance(snum, int) or snum < 1 or snum > 99:
                violations.append(SchemaViolation("SCHEMA-14-SHIRT-NUMBER", league_path, f"{tname}/{pname}", f"Invalid shirt number: {snum}"))
            elif snum in shirt_numbers:
                violations.append(SchemaViolation("SCHEMA-15-DUPLICATE-SHIRT", league_path, f"{tname}/{pname}", f"Duplicate shirt number {snum} in team"))
            else:
                shirt_numbers.add(snum)

            # Invariant bounds
            mass = player.get("mass", 0.0)
            if not (60.0 <= mass <= 95.0):
                violations.append(SchemaViolation("SCHEMA-16-PHYSICAL-BOUNDS", league_path, f"{tname}/{pname}", f"mass {mass} not in [60.0, 95.0]"))

            speed = player.get("top_speed", 0.0)
            if not (170.0 <= speed <= 260.0):
                violations.append(SchemaViolation("SCHEMA-16-PHYSICAL-BOUNDS", league_path, f"{tname}/{pname}", f"top_speed {speed} not in [170.0, 260.0]"))

            accel = player.get("acceleration_time", 0.0)
            if not (0.12 <= accel <= 0.38):
                violations.append(SchemaViolation("SCHEMA-16-PHYSICAL-BOUNDS", league_path, f"{tname}/{pname}", f"acceleration_time {accel} not in [0.12, 0.38]"))

            turn = player.get("turning_penalty", 0.0)
            if not (0.18 <= turn <= 0.55):
                violations.append(SchemaViolation("SCHEMA-16-PHYSICAL-BOUNDS", league_path, f"{tname}/{pname}", f"turning_penalty {turn} not in [0.18, 0.55]"))

            stam = player.get("stamina_max", 0.0)
            if not (75.0 <= stam <= 125.0):
                violations.append(SchemaViolation("SCHEMA-16-PHYSICAL-BOUNDS", league_path, f"{tname}/{pname}", f"stamina_max {stam} not in [75.0, 125.0]"))

            for attr in ("vision", "composure", "aggression", "close_control", "reflexes"):
                val = player.get(attr, 0.0)
                if not (0.0 <= val <= 1.0):
                    violations.append(SchemaViolation("SCHEMA-17-ATTRIBUTE-BOUNDS", league_path, f"{tname}/{pname}", f"Attribute '{attr}'={val} not in [0.0, 1.0]"))

            form = player.get("form", 0.0)
            if not (0.0 <= form <= 10.0):
                violations.append(SchemaViolation("SCHEMA-18-FORM-BOUNDS", league_path, f"{tname}/{pname}", f"form {form} not in [0.0, 10.0]"))

            if "trait_bits" in player:
                trait_bits = player.get("trait_bits", 0)
                if not isinstance(trait_bits, int) or not (0 <= trait_bits <= 8191):
                    violations.append(SchemaViolation("SCHEMA-19-TRAIT-BITS", league_path, f"{tname}/{pname}", f"trait_bits {trait_bits} out of range [0, 8191]"))

    return violations, team_names


def validate_managers_schema(managers_path: str, valid_teams: set[str]) -> list[SchemaViolation]:
    violations: list[SchemaViolation] = []
    if not os.path.exists(managers_path):
        return [SchemaViolation("SCHEMA-01-MISSING-FILE", managers_path, "managers", "File data/managers.json is missing")]

    try:
        with open(managers_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return [SchemaViolation("SCHEMA-02-INVALID-JSON", managers_path, "managers", f"Invalid JSON syntax: {e}")]

    managers = data.get("managers", [])
    if not isinstance(managers, list) or len(managers) < 10:
        violations.append(SchemaViolation("SCHEMA-20-MANAGER-COUNT", managers_path, "managers", f"Expected >= 10 managers, got {len(managers)}"))

    VALID_TRAIT_BITS = 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128 | 256 | 512
    VALID_PRIZED = {"vision", "composure", "aggression", "none"}
    VALID_PLAYSTYLES = {"technical", "physical", "pace", "aerial", "engine", "none"}

    mgr_names: set[str] = set()
    assigned_teams: set[str] = set()

    for m_idx, m in enumerate(managers):
        mname = m.get("name", f"manager_{m_idx}")
        if not mname:
            violations.append(SchemaViolation("SCHEMA-21-MANAGER-NAME", managers_path, f"manager_{m_idx}", "Missing manager 'name'"))
            continue
        if mname in mgr_names:
            violations.append(SchemaViolation("SCHEMA-22-DUPLICATE-MANAGER", managers_path, mname, f"Duplicate manager name: '{mname}'"))
        mgr_names.add(mname)

        exp = m.get("experience", 0)
        if not (1 <= exp <= 100):
            violations.append(SchemaViolation("SCHEMA-23-MANAGER-EXP", managers_path, mname, f"experience {exp} not in [1, 100]"))

        team = m.get("current_team", "")
        if team:
            if team not in valid_teams:
                violations.append(SchemaViolation("SCHEMA-24-UNKNOWN-TEAM", managers_path, mname, f"Assigned to unknown team: '{team}'"))
            if team in assigned_teams:
                violations.append(SchemaViolation("SCHEMA-25-TEAM-DUPLICATE-MGR", managers_path, mname, f"Multiple managers assigned to team '{team}'"))
            assigned_teams.add(team)

        for param in ("defensive_line", "tempo", "width", "pressing_intensity", "physicality", "youth_trust", "loyalty_bias", "form_sensitivity"):
            val = m.get(param, 0.0)
            if not (0.0 <= val <= 1.0):
                violations.append(SchemaViolation("SCHEMA-26-TACTICAL-PARAM", managers_path, mname, f"Tactical parameter '{param}'={val} not in [0.0, 1.0]"))

        traits = m.get("traits", 0)
        if (traits & ~VALID_TRAIT_BITS) != 0:
            violations.append(SchemaViolation("SCHEMA-27-MANAGER-TRAITS", managers_path, mname, f"Invalid trait bits: {traits}"))

        prized = m.get("prized_attribute", "")
        if prized not in VALID_PRIZED:
            violations.append(SchemaViolation("SCHEMA-28-PRIZED-ATTR", managers_path, mname, f"Invalid prized_attribute: '{prized}'"))

        style = m.get("preferred_playstyle", "")
        if style not in VALID_PLAYSTYLES:
            violations.append(SchemaViolation("SCHEMA-29-PLAYSTYLE", managers_path, mname, f"Invalid preferred_playstyle: '{style}'"))

    return violations


def validate_referees_schema(referees_path: str) -> list[SchemaViolation]:
    violations: list[SchemaViolation] = []
    if not os.path.exists(referees_path):
        return [SchemaViolation("SCHEMA-01-MISSING-FILE", referees_path, "referees", "File data/referees.json is missing")]

    try:
        with open(referees_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return [SchemaViolation("SCHEMA-02-INVALID-JSON", referees_path, "referees", f"Invalid JSON syntax: {e}")]

    referees = data.get("referees", [])
    if not isinstance(referees, list) or len(referees) < 8:
        violations.append(SchemaViolation("SCHEMA-30-REFEREE-COUNT", referees_path, "referees", f"Expected >= 8 referees, got {len(referees)}"))

    ref_names: set[str] = set()

    for r_idx, r in enumerate(referees):
        rname = r.get("name", f"referee_{r_idx}")
        if not rname:
            violations.append(SchemaViolation("SCHEMA-31-REF-NAME", referees_path, f"referee_{r_idx}", "Missing referee 'name'"))
            continue
        if rname in ref_names:
            violations.append(SchemaViolation("SCHEMA-32-DUPLICATE-REF", referees_path, rname, f"Duplicate referee name: '{rname}'"))
        ref_names.add(rname)

        exp = r.get("experience", 0)
        if not (1 <= exp <= 100):
            violations.append(SchemaViolation("SCHEMA-33-REF-EXP", referees_path, rname, f"experience {exp} not in [1, 100]"))

        for spectrum in ("strictness", "consistency", "composure", "unprofessionalism", "incoherence", "reputation"):
            val = r.get(spectrum, 0.0)
            if not (0.0 <= val <= 1.0):
                violations.append(SchemaViolation("SCHEMA-34-REF-SPECTRUM", referees_path, rname, f"Personality spectrum '{spectrum}'={val} not in [0.0, 1.0]"))

        for stat in ("matches_officiated", "fouls_awarded", "penalties_awarded"):
            if stat not in r or not isinstance(r[stat], int) or r[stat] < 0:
                violations.append(SchemaViolation("SCHEMA-35-REF-STATS", referees_path, rname, f"Missing or invalid career stat '{stat}'"))

    return violations


def format_xml_output(violations: list[SchemaViolation]) -> str:
    xml_lines = ['<verification_failure tool="validate_schemas">']
    for v in violations:
        rel = html.escape(os.path.relpath(v.file_path, ROOT).replace("\\", "/"))
        xml_lines.append(
            f'  <diagnostic file="{rel}" line="1" severity="{v.severity}" rule="{v.rule_id}">'
            f'{html.escape(f"[{v.entity_name}] {v.message}")}'
            f'</diagnostic>'
        )
    xml_lines.append('</verification_failure>')
    return "\n".join(xml_lines)


def run_all_schema_validations() -> list[SchemaViolation]:
    all_violations: list[SchemaViolation] = []

    league_path = os.path.join(DATA_DIR, "league.json")
    managers_path = os.path.join(DATA_DIR, "managers.json")
    referees_path = os.path.join(DATA_DIR, "referees.json")

    league_violations, valid_teams = validate_league_schema(league_path)
    all_violations.extend(league_violations)

    mgr_violations = validate_managers_schema(managers_path, valid_teams)
    all_violations.extend(mgr_violations)

    ref_violations = validate_referees_schema(referees_path)
    all_violations.extend(ref_violations)

    return all_violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Strict JSON Database Schema Validator")
    parser.add_argument("--xml", action="store_true", help="Output failures in structured XML format")
    args = parser.parse_args()

    violations = run_all_schema_validations()

    if violations:
        if args.xml:
            print(format_xml_output(violations), file=sys.stderr)
        else:
            print(f"=== Database Schema Validation Failures ({len(violations)} errors) ===")
            for v in violations:
                print(str(v))
            print("=========================================================================")
        return 1

    if not args.xml:
        print("validate_schemas: All database schemas (league, managers, referees) verified successfully with 0 errors.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
