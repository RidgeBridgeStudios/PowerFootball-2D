#!/usr/bin/env python3
"""
data_pipeline/harvest_managers_2026.py

Harvests and enriches real-world team managers for the 2026/2027 season
using the SportMonks Football API v3. Extracts authentic coach identities,
contracts, favorite tactical formations, tactical philosophy sliders,
and personality trait bitmasks for PowerFootball-2D (ManagerData.gd).

Outputs:
  - JSON database ready for autoloads/ManagerLoader.gd (res://data/managers.json)
  - Optional SQLite sync with powerfootball_master.db (coaches table)
"""

import argparse
import datetime
import json
import os
import re
import sqlite3
import sys
import time
import urllib.request
import urllib.parse
import urllib.error
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
        sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")
    except Exception:
        pass


# =============================================================================
# CONFIGURATION & CONSTANTS
# =============================================================================

DEFAULT_API_TOKEN = "WF5neL4jRErhZvad8hJpq3a9MNS2hk9jgkU6b8wCFqbOh8EnXHFdCqzMYEdT"
BASE_URL = "https://api.sportmonks.com/v3/football"

# PowerFootball-2D ManagerData.gd Traits Bitmask
TRAIT_HOTHEAD = 1
TRAIT_LOYALIST = 2
TRAIT_PRAGMATIST = 4
TRAIT_VISIONARY = 8
TRAIT_DISCIPLINARIAN = 16
TRAIT_MINDGAMES = 32
TRAIT_SENTIMENTAL = 64
TRAIT_MEDIASAVVY = 128
TRAIT_VOLATILE = 256
TRAIT_IDEALIST = 512

# Top leagues default mapping (SportMonks League ID -> League Name)
TOP_LEAGUE_MAP: Dict[int, str] = {
    8: "Premier League (England)",
    9: "Championship (England)",
    72: "Eredivisie (Netherlands)",
    82: "Bundesliga (Germany)",
    301: "Ligue 1 (France)",
    384: "Serie A (Italy)",
    564: "La Liga (Spain)",
    573: "Allsvenskan (Sweden)",
    2: "UEFA Champions League",
    5: "UEFA Europa League",
    24: "Primeira Liga (Portugal)",
    271: "Belgian Pro League",
    181: "Scottish Premiership"
}

# Curated profiles for prominent managers (tactics & traits matching reality)
CURATED_MANAGERS: Dict[str, Dict[str, Any]] = {
    "mikel arteta": {
        "preferred_formation": "4-2-3-1", "attacking_formation": "4-3-3", "defensive_formation": "5-3-2",
        "defensive_line": 0.82, "tempo": 0.58, "width": 0.72, "pressing_intensity": 0.86, "physicality": 0.68,
        "traits": TRAIT_VISIONARY | TRAIT_DISCIPLINARIAN | TRAIT_MEDIASAVVY,
        "reputation": 0.89, "youth_trust": 0.78, "loyalty_bias": 0.65, "form_sensitivity": 0.72,
        "prized_attribute": "composure", "preferred_playstyle": "technical"
    },
    "pep guardiola": {
        "preferred_formation": "4-3-3", "attacking_formation": "3-2-4-1", "defensive_formation": "4-3-3",
        "defensive_line": 0.90, "tempo": 0.42, "width": 0.78, "pressing_intensity": 0.88, "physicality": 0.45,
        "traits": TRAIT_VISIONARY | TRAIT_IDEALIST | TRAIT_DISCIPLINARIAN,
        "reputation": 0.98, "youth_trust": 0.70, "loyalty_bias": 0.50, "form_sensitivity": 0.85,
        "prized_attribute": "vision", "preferred_playstyle": "technical"
    },
    "diego simeone": {
        "preferred_formation": "4-4-2", "attacking_formation": "4-3-3", "defensive_formation": "5-3-2",
        "defensive_line": 0.32, "tempo": 0.76, "width": 0.45, "pressing_intensity": 0.75, "physicality": 0.92,
        "traits": TRAIT_PRAGMATIST | TRAIT_HOTHEAD | TRAIT_DISCIPLINARIAN,
        "reputation": 0.91, "youth_trust": 0.45, "loyalty_bias": 0.85, "form_sensitivity": 0.40,
        "prized_attribute": "aggression", "preferred_playstyle": "physical"
    },
    "jürgen klopp": {
        "preferred_formation": "4-3-3", "attacking_formation": "4-2-4", "defensive_formation": "4-3-3",
        "defensive_line": 0.85, "tempo": 0.82, "width": 0.75, "pressing_intensity": 0.95, "physicality": 0.80,
        "traits": TRAIT_VISIONARY | TRAIT_HOTHEAD | TRAIT_MEDIASAVVY,
        "reputation": 0.96, "youth_trust": 0.80, "loyalty_bias": 0.75, "form_sensitivity": 0.60,
        "prized_attribute": "work_rate", "preferred_playstyle": "engine"
    },
    "xabi alonso": {
        "preferred_formation": "3-4-2-1", "attacking_formation": "3-4-3", "defensive_formation": "5-4-1",
        "defensive_line": 0.78, "tempo": 0.65, "width": 0.70, "pressing_intensity": 0.82, "physicality": 0.65,
        "traits": TRAIT_VISIONARY | TRAIT_MEDIASAVVY | TRAIT_LOYALIST,
        "reputation": 0.92, "youth_trust": 0.75, "loyalty_bias": 0.60, "form_sensitivity": 0.65,
        "prized_attribute": "vision", "preferred_playstyle": "technical"
    },
    "ruben amorim": {
        "preferred_formation": "3-4-3", "attacking_formation": "3-4-2-1", "defensive_formation": "5-2-3",
        "defensive_line": 0.75, "tempo": 0.70, "width": 0.75, "pressing_intensity": 0.84, "physicality": 0.72,
        "traits": TRAIT_VISIONARY | TRAIT_DISCIPLINARIAN | TRAIT_MEDIASAVVY,
        "reputation": 0.88, "youth_trust": 0.85, "loyalty_bias": 0.60, "form_sensitivity": 0.70,
        "prized_attribute": "vision", "preferred_playstyle": "engine"
    },
    "carlo ancelotti": {
        "preferred_formation": "4-3-1-2", "attacking_formation": "4-3-3", "defensive_formation": "4-4-2",
        "defensive_line": 0.60, "tempo": 0.55, "width": 0.60, "pressing_intensity": 0.52, "physicality": 0.58,
        "traits": TRAIT_PRAGMATIST | TRAIT_LOYALIST | TRAIT_MEDIASAVVY,
        "reputation": 0.96, "youth_trust": 0.50, "loyalty_bias": 0.82, "form_sensitivity": 0.45,
        "prized_attribute": "composure", "preferred_playstyle": "technical"
    },
    "fabian hürzeler": {
        "preferred_formation": "4-2-3-1", "attacking_formation": "3-4-3", "defensive_formation": "4-4-2",
        "defensive_line": 0.80, "tempo": 0.68, "width": 0.68, "pressing_intensity": 0.86, "physicality": 0.62,
        "traits": TRAIT_VISIONARY | TRAIT_VOLATILE,
        "reputation": 0.80, "youth_trust": 0.88, "loyalty_bias": 0.48, "form_sensitivity": 0.75,
        "prized_attribute": "vision", "preferred_playstyle": "technical"
    },
    "andoni iraola": {
        "preferred_formation": "4-2-3-1", "attacking_formation": "4-3-3", "defensive_formation": "4-4-2",
        "defensive_line": 0.84, "tempo": 0.78, "width": 0.72, "pressing_intensity": 0.92, "physicality": 0.75,
        "traits": TRAIT_VISIONARY | TRAIT_DISCIPLINARIAN,
        "reputation": 0.84, "youth_trust": 0.76, "loyalty_bias": 0.52, "form_sensitivity": 0.70,
        "prized_attribute": "aggression", "preferred_playstyle": "engine"
    },
    "ange postecoglou": {
        "preferred_formation": "4-3-3", "attacking_formation": "4-2-4", "defensive_formation": "4-3-3",
        "defensive_line": 0.92, "tempo": 0.85, "width": 0.80, "pressing_intensity": 0.88, "physicality": 0.70,
        "traits": TRAIT_IDEALIST | TRAIT_MEDIASAVVY,
        "reputation": 0.86, "youth_trust": 0.72, "loyalty_bias": 0.50, "form_sensitivity": 0.75,
        "prized_attribute": "work_rate", "preferred_playstyle": "engine"
    },
    "unai emery": {
        "preferred_formation": "4-4-2", "attacking_formation": "4-2-3-1", "defensive_formation": "4-4-2",
        "defensive_line": 0.68, "tempo": 0.60, "width": 0.55, "pressing_intensity": 0.70, "physicality": 0.65,
        "traits": TRAIT_DISCIPLINARIAN | TRAIT_PRAGMATIST,
        "reputation": 0.88, "youth_trust": 0.60, "loyalty_bias": 0.65, "form_sensitivity": 0.75,
        "prized_attribute": "composure", "preferred_playstyle": "technical"
    },
    "antonio conte": {
        "preferred_formation": "3-5-2", "attacking_formation": "3-4-3", "defensive_formation": "5-3-2",
        "defensive_line": 0.55, "tempo": 0.75, "width": 0.65, "pressing_intensity": 0.82, "physicality": 0.88,
        "traits": TRAIT_HOTHEAD | TRAIT_DISCIPLINARIAN | TRAIT_PRAGMATIST,
        "reputation": 0.91, "youth_trust": 0.40, "loyalty_bias": 0.75, "form_sensitivity": 0.80,
        "prized_attribute": "aggression", "preferred_playstyle": "physical"
    }
}


# =============================================================================
# DATA STRUCTURES & HELPERS
# =============================================================================

def calculate_age(dob: str, ref_year: int = 2026, ref_month: int = 9, ref_day: int = 1) -> int:
    """Calculates age as of season 2026/2027."""
    if not dob:
        return 48
    parts = dob.split("-")
    if len(parts) < 3:
        return 48
    try:
        b_year = int(parts[0])
        b_month = int(parts[1])
        b_day = int(parts[2])
        age = ref_year - b_year
        if ref_month < b_month or (ref_month == b_month and ref_day < b_day):
            age -= 1
        return max(28, age)
    except Exception:
        return 48


def calculate_experience(age: int, start_date: Optional[str]) -> int:
    """Calculates managerial experience (1-100) based on age and career start."""
    base_exp = max(10, min(95, int((age - 30) * 2.5)))
    if start_date:
        try:
            start_year = int(start_date.split("-")[0])
            tenure = max(1, 2026 - start_year)
            base_exp = min(99, base_exp + int(tenure * 2))
        except Exception:
            pass
    return base_exp


def infer_tactics_from_formation(formation: str) -> Dict[str, Any]:
    """Infers tactical sliders (0.0 to 1.0) and counter formations from primary formation."""
    f = formation.strip()
    if f in ("4-3-3", "4-3-3 Attacking", "4-1-2-3"):
        return {
            "preferred_formation": "4-3-3",
            "attacking_formation": "4-2-4",
            "defensive_formation": "4-5-1",
            "defensive_line": 0.78, "tempo": 0.65, "width": 0.75,
            "pressing_intensity": 0.80, "physicality": 0.58,
            "prized_attribute": "vision", "preferred_playstyle": "technical"
        }
    elif f in ("4-2-3-1", "4-2-3-1 Wide"):
        return {
            "preferred_formation": "4-2-3-1",
            "attacking_formation": "4-3-3",
            "defensive_formation": "4-4-2",
            "defensive_line": 0.72, "tempo": 0.62, "width": 0.68,
            "pressing_intensity": 0.76, "physicality": 0.62,
            "prized_attribute": "composure", "preferred_playstyle": "technical"
        }
    elif f in ("3-5-2", "5-3-2", "3-5-1-1"):
        return {
            "preferred_formation": "3-5-2",
            "attacking_formation": "3-4-3",
            "defensive_formation": "5-3-2",
            "defensive_line": 0.48, "tempo": 0.68, "width": 0.62,
            "pressing_intensity": 0.65, "physicality": 0.78,
            "prized_attribute": "work_rate", "preferred_playstyle": "engine"
        }
    elif f in ("3-4-3", "3-4-2-1"):
        return {
            "preferred_formation": "3-4-3",
            "attacking_formation": "3-4-3",
            "defensive_formation": "5-4-1",
            "defensive_line": 0.75, "tempo": 0.72, "width": 0.75,
            "pressing_intensity": 0.82, "physicality": 0.68,
            "prized_attribute": "vision", "preferred_playstyle": "technical"
        }
    else:  # Default 4-4-2 / Balanced
        return {
            "preferred_formation": "4-4-2",
            "attacking_formation": "4-3-3",
            "defensive_formation": "5-3-2",
            "defensive_line": 0.50, "tempo": 0.55, "width": 0.52,
            "pressing_intensity": 0.55, "physicality": 0.68,
            "prized_attribute": "aggression", "preferred_playstyle": "physical"
        }


def infer_personality_traits(name: str, age: int, tactics: Dict[str, Any]) -> int:
    """Computes trait bitmask based on curated records or personality heuristics."""
    clean_name = name.lower().strip()
    if clean_name in CURATED_MANAGERS:
        return int(CURATED_MANAGERS[clean_name]["traits"])

    traits = 0
    # Tactical alignment traits
    if tactics.get("pressing_intensity", 0.5) >= 0.78 and tactics.get("defensive_line", 0.5) >= 0.75:
        traits |= TRAIT_VISIONARY
    if tactics.get("physicality", 0.5) >= 0.75:
        traits |= TRAIT_PRAGMATIST

    # Age and tenure alignment
    if age >= 58:
        traits |= TRAIT_LOYALIST
    elif age <= 42:
        traits |= TRAIT_MEDIASAVVY

    # Disciplinarian default for structured setups
    if tactics.get("defensive_line", 0.5) <= 0.45:
        traits |= TRAIT_DISCIPLINARIAN

    if traits == 0:
        traits = TRAIT_PRAGMATIST | TRAIT_MEDIASAVVY

    return traits


def build_spoken_languages(nationality: str) -> List[Dict[str, Any]]:
    """Assigns native language plus international languages."""
    nat = nationality.lower()
    native = "English"
    if "spain" in nat or "spanish" in nat or "argentin" in nat or "chile" in nat or "uruguay" in nat or "colomb" in nat:
        native = "Spanish"
    elif "german" in nat or "austria" in nat:
        native = "German"
    elif "ital" in nat:
        native = "Italian"
    elif "franc" in nat:
        native = "French"
    elif "portug" in nat or "brazil" in nat:
        native = "Portuguese"
    elif "netherland" in nat or "dutch" in nat:
        native = "Dutch"
    elif "swed" in nat:
        native = "Swedish"
    elif "norway" in nat:
        native = "Norwegian"
    elif "denmark" in nat or "danish" in nat:
        native = "Danish"

    langs = [{"language": native, "proficiency": 1.0, "level": "Native"}]
    if native != "English":
        langs.append({"language": "English", "proficiency": 0.85, "level": "Fluent"})
    return langs


# =============================================================================
# HARVESTER ENGINE
# =============================================================================

class SportMonksManagerHarvester:
    def __init__(self, api_token: str):
        self.api_token = api_token
        self.headers = {
            "Authorization": self.api_token,
            "Accept": "application/json"
        }
        self.harvested_managers: List[Dict[str, Any]] = []

    def _get(self, endpoint: str, params: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        """Executes GET request with exponential backoff and rate-limit handling."""
        if params is None:
            params = {}
        query_str = "?" + urllib.parse.urlencode(params) if params else ""
        url = f"{BASE_URL}/{endpoint}{query_str}"
        req = urllib.request.Request(url, headers=self.headers)

        backoff = 1.0
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req, timeout=25) as response:
                    return json.loads(response.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    print(f"    [Rate Limit 429] Backing off for {backoff:.1f}s...")
                    time.sleep(backoff)
                    backoff *= 2.0
                    continue
                elif e.code in (500, 502, 503, 504):
                    time.sleep(backoff)
                    backoff *= 2.0
                    continue
                else:
                    print(f"    [HTTP {e.code}] Error requesting {endpoint}: {e.reason}")
                    return None
            except urllib.error.URLError as e:
                time.sleep(backoff)
                backoff *= 2.0
                continue
        return None

    def harvest_season_managers(self, season_id: int, league_name: str = "") -> List[Dict[str, Any]]:
        """Harvests all teams and active 2026/2027 managers for a specific season."""
        print(f"\n[Season {season_id}] Harvesting teams for {league_name or 'Season'}...")
        payload = self._get(f"teams/seasons/{season_id}", {"include": "coaches.coach.nationality;latest.formations"})
        if not payload or "data" not in payload:
            print("  No data returned.")
            return []

        teams = payload["data"]
        print(f"  Found {len(teams)} teams in season {season_id}.")
        season_managers: List[Dict[str, Any]] = []

        for team in teams:
            team_id = team.get("id")
            team_name = team.get("name")
            if not team_id or not team_name:
                continue

            # 1. Identify active head coach
            active_coach_entry = None
            for c in team.get("coaches", []):
                if c.get("active") and c.get("position_id") == 221:
                    active_coach_entry = c
                    break

            # Fallback if no active flag with 221
            if not active_coach_entry:
                for c in team.get("coaches", []):
                    if c.get("active"):
                        active_coach_entry = c
                        break

            if not active_coach_entry:
                continue

            coach_obj = active_coach_entry.get("coach")
            if not coach_obj:
                continue

            manager_name = (
                coach_obj.get("display_name")
                or coach_obj.get("name")
                or coach_obj.get("common_name")
                or "Unknown Manager"
            )
            nat_obj = coach_obj.get("nationality") or {}
            nationality = nat_obj.get("name") or "Unknown"
            dob = coach_obj.get("date_of_birth") or "1975-01-01"
            start_date = active_coach_entry.get("start")
            end_date = active_coach_entry.get("end")

            # 2. Extract recent formations
            latest_matches = team.get("latest", [])
            formation_counts: Dict[str, int] = {}
            if isinstance(latest_matches, list):
                for match in latest_matches:
                    for f_entry in match.get("formations", []):
                        if f_entry.get("participant_id") == team_id:
                            f_str = f_entry.get("formation")
                            if f_str:
                                formation_counts[f_str] = formation_counts.get(f_str, 0) + 1

            preferred_formation = "4-3-3"
            if formation_counts:
                preferred_formation = max(formation_counts, key=formation_counts.get)

            # 3. Derive tactical philosophy & personality
            tactics = infer_tactics_from_formation(preferred_formation)
            age = calculate_age(dob)
            experience = calculate_experience(age, start_date)

            clean_name = manager_name.lower().strip()
            if clean_name in CURATED_MANAGERS:
                curated = CURATED_MANAGERS[clean_name]
                tactics.update({k: v for k, v in curated.items() if k in tactics or k.startswith("defensive_") or k in ("tempo", "width", "pressing_intensity", "physicality")})
                traits = curated.get("traits", infer_personality_traits(manager_name, age, tactics))
                reputation = curated.get("reputation", 0.85)
                youth_trust = curated.get("youth_trust", 0.70)
                loyalty_bias = curated.get("loyalty_bias", 0.60)
                form_sensitivity = curated.get("form_sensitivity", 0.65)
                prized_attribute = curated.get("prized_attribute", tactics["prized_attribute"])
                preferred_playstyle = curated.get("preferred_playstyle", tactics["preferred_playstyle"])
            else:
                traits = infer_personality_traits(manager_name, age, tactics)
                reputation = max(0.40, min(0.95, 0.45 + (experience / 200.0)))
                youth_trust = 0.50
                loyalty_bias = 0.55
                form_sensitivity = 0.60
                prized_attribute = tactics["prized_attribute"]
                preferred_playstyle = tactics["preferred_playstyle"]

            # Contract calculation
            contract_years = 2
            if end_date:
                try:
                    end_year = int(end_date.split("-")[0])
                    contract_years = max(1, end_year - 2026)
                except Exception:
                    pass

            manager_record = {
                "name": manager_name,
                "nationality": nationality,
                "secondary_nationality": "",
                "date_of_birth": dob,
                "spoken_languages": build_spoken_languages(nationality),
                "experience": experience,
                "current_team": team_name,
                "reputation": round(reputation, 2),
                "board_confidence": 0.70,
                "contract_years": contract_years,
                "salary_weekly": int(20000 + (reputation * 60000)),
                "referee_respect": 0.60,
                "defensive_line": round(tactics["defensive_line"], 2),
                "tempo": round(tactics["tempo"], 2),
                "width": round(tactics["width"], 2),
                "pressing_intensity": round(tactics["pressing_intensity"], 2),
                "physicality": round(tactics["physicality"], 2),
                "preferred_formation": tactics["preferred_formation"],
                "attacking_formation": tactics["attacking_formation"],
                "defensive_formation": tactics["defensive_formation"],
                "youth_trust": round(youth_trust, 2),
                "loyalty_bias": round(loyalty_bias, 2),
                "form_sensitivity": round(form_sensitivity, 2),
                "preferred_min_age": 20,
                "preferred_max_age": 30,
                "budget_flexibility": 0.55,
                "preferred_mass_min": 65.0,
                "preferred_mass_max": 88.0,
                "prized_attribute": prized_attribute,
                "preferred_playstyle": preferred_playstyle,
                "traits": traits,
                "matches_managed": int(experience * 4.5),
                "wins": int(experience * 2.2),
                "draws": int(experience * 1.1),
                "losses": int(experience * 1.2),
                "goals_scored": int(experience * 7.0),
                "goals_conceded": int(experience * 4.5),
                "_meta": {
                    "team_id": team_id,
                    "season_id": season_id,
                    "coach_id": coach_obj.get("id"),
                    "contract_start": start_date,
                    "contract_end": end_date,
                    "image_url": coach_obj.get("image_path")
                }
            }

            season_managers.append(manager_record)
            print(f"    [Manager] {team_name:28} -> {manager_name} ({nationality}), Formation: {tactics['preferred_formation']}, Traits: {traits}")

        return season_managers

    def harvest_all(self, seasons: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Harvests across all provided seasons with rate pacing."""
        total = len(seasons)
        for idx, s in enumerate(seasons, 1):
            s_id = s.get("season_id") or s.get("id")
            s_name = s.get("season_name") or s.get("name", "2026/2027")
            l_name = s.get("league_name", "")
            print(f"\n========================================================")
            print(f"[{idx}/{total}] Processing {l_name} ({s_name}) [ID: {s_id}]")
            print(f"========================================================")

            managers = self.harvest_season_managers(s_id, l_name)
            self.harvested_managers.extend(managers)
            time.sleep(0.4)

        return self.harvested_managers


# =============================================================================
# EXPORT & DATABASE SYNC
# =============================================================================

def save_managers_json(managers: List[Dict[str, Any]], output_path: Path):
    """Exports harvested managers to Godot-compatible JSON format."""
    clean_managers = []
    seen_names = set()

    for m in managers:
        # Deduplicate manager if appearing across multiple seasons
        key = (m["name"], m["current_team"])
        if key in seen_names:
            continue
        seen_names.add(key)
        
        # Omit internal _meta for game distribution
        entry = {k: v for k, v in m.items() if k != "_meta"}
        clean_managers.append(entry)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({"managers": clean_managers}, f, indent=2, ensure_ascii=False)

    print(f"\nSuccessfully wrote {len(clean_managers)} managers to {output_path.resolve()}")


def update_master_sqlite_db(managers: List[Dict[str, Any]], db_path: Path):
    """Updates powerfootball_master.db coaches table with authentic manager data."""
    if not db_path.exists():
        print(f"Database {db_path} does not exist. Skipping SQLite update.")
        return

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Check and add tactical columns if not present
    cur.execute("PRAGMA table_info(coaches);")
    existing_cols = {row[1] for row in cur.fetchall()}

    columns_to_add = [
        ("preferred_formation", "TEXT DEFAULT '4-3-3'"),
        ("traits", "INTEGER DEFAULT 0"),
        ("pressing_intensity", "REAL DEFAULT 0.5"),
        ("defensive_line", "REAL DEFAULT 0.5"),
        ("experience", "INTEGER DEFAULT 30"),
        ("reputation", "REAL DEFAULT 0.5")
    ]
    for col_name, col_def in columns_to_add:
        if col_name not in existing_cols:
            try:
                cur.execute(f"ALTER TABLE coaches ADD COLUMN {col_name} {col_def};")
            except Exception:
                pass

    updated_count = 0

    for m in managers:
        meta = m.get("_meta", {})
        team_id = meta.get("team_id")
        coach_id = meta.get("coach_id")
        if not team_id or not coach_id:
            continue

        # Clean existing placeholder or conflicting entry for this team/coach
        cur.execute("DELETE FROM coaches WHERE team_id = ? OR coach_id = ?;", (team_id, coach_id))

        cur.execute("""
            INSERT INTO coaches (
                coach_id, team_id, common_name, first_name, last_name, nationality,
                date_of_birth, image_url, preferred_formation, traits,
                pressing_intensity, defensive_line, experience, reputation
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, (
            coach_id, team_id,
            m["name"],
            m["name"].split(" ")[0] if " " in m["name"] else m["name"],
            m["name"].split(" ")[-1] if " " in m["name"] else "",
            m["nationality"],
            m["date_of_birth"],
            meta.get("image_url"),
            m["preferred_formation"],
            m["traits"],
            m["pressing_intensity"],
            m["defensive_line"],
            m["experience"],
            m["reputation"]
        ))
        updated_count += 1

    conn.commit()
    conn.close()
    print(f"SQLite Sync Complete: {updated_count} coaches synchronized in {db_path.resolve()}")



# =============================================================================
# CLI ENTRY POINT
# =============================================================================

def load_seasons_from_raw(raw_seasons_file: Path) -> List[Dict[str, Any]]:
    """Loads 2026/2027 seasons list from data_lake_2026/raw_seasons.jsonl."""
    seasons = []
    if not raw_seasons_file.exists():
        return seasons

    with open(raw_seasons_file, "r", encoding="utf-8") as f:
        for line in f:
            try:
                data = json.loads(line.strip())
                seasons.append({
                    "season_id": data.get("id"),
                    "season_name": data.get("name"),
                    "league_id": data.get("league_id"),
                    "league_name": TOP_LEAGUE_MAP.get(data.get("league_id"), f"League {data.get('league_id')}")
                })
            except Exception:
                pass
    return seasons


def main():
    parser = argparse.ArgumentParser(description="Harvest 2026/2027 managers & tactical profiles via SportMonks API")
    parser.add_argument("--token", type=str, default=os.environ.get("SPORTMONKS_API_TOKEN", DEFAULT_API_TOKEN), help="SportMonks API token")
    parser.add_argument("--top-leagues", action="store_true", help="Harvest only premier top leagues (EPL, La Liga, Serie A, Bundesliga, etc.)")
    parser.add_argument("--all", action="store_true", help="Harvest across all 2026/2027 seasons found in raw_seasons.jsonl")
    parser.add_argument("--season-id", type=int, help="Harvest a specific season ID (e.g. 28083 for EPL 2026/2027)")
    parser.add_argument("--output-json", type=Path, default=Path("data_pipeline/data_lake_2026/managers_2026.json"), help="Output path for JSON managers database")
    parser.add_argument("--sync-godot", action="store_true", help="Also write directly to Godot res://data/managers.json")
    parser.add_argument("--sync-sqlite", action="store_true", help="Update coaches table in powerfootball_master.db")
    args = parser.parse_args()

    print("==========================================================")
    print("POWERFOOTBALL-2D: 2026/2027 MANAGER HARVESTER & TACTICS")
    print("==========================================================")

    data_lake_dir = Path("data_pipeline/data_lake_2026")
    raw_seasons_file = data_lake_dir / "raw_seasons.jsonl"
    all_seasons = load_seasons_from_raw(raw_seasons_file)

    target_seasons: List[Dict[str, Any]] = []

    if args.season_id:
        target_seasons = [{"season_id": args.season_id, "season_name": "Target Season", "league_name": "Selected League"}]
    elif args.top_leagues or not args.all:
        # Default to top leagues if not explicitly --all
        top_ids = set(TOP_LEAGUE_MAP.keys())
        target_seasons = [s for s in all_seasons if s.get("league_id") in top_ids]
        if not target_seasons and all_seasons:
            target_seasons = all_seasons[:10]
        print(f"Targeting {len(target_seasons)} top division seasons.")
    else:
        target_seasons = all_seasons
        print(f"Targeting ALL {len(target_seasons)} seasons in data lake.")

    harvester = SportMonksManagerHarvester(api_token=args.token)
    managers = harvester.harvest_all(target_seasons)

    # Export to JSON
    save_managers_json(managers, args.output_json)

    if args.sync_godot:
        godot_json_path = Path("data/managers_2026.json")
        save_managers_json(managers, godot_json_path)

    if args.sync_sqlite:
        for db_loc in [Path("data_pipeline/powerfootball_master.db"), Path("data/powerfootball_master.db")]:
            if db_loc.exists():
                update_master_sqlite_db(managers, db_loc)

    print("\n[DONE] Manager harvesting and tactical enrichment completed.")



if __name__ == "__main__":
    main()
