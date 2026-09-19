#!/usr/bin/env python3
"""
data_pipeline/balance_team_finances_and_facilities.py

Mathematically balances and enriches club reputation, stature tier, transfer budget,
weekly wage budget, and facility levels (training, youth, medical) across all teams
in PowerFootball-2D.

Integrates:
  1. SportMonks Football API v3 (live UEFA coefficient rankings, points, trophies, venues)
  2. Master database domestic pyramid league tiers and national prestige
  3. Continental tournament participation records (UCL, UEL, UECL, Libertadores)
  4. Squad player ability aggregates from contracts & players tables
  5. Venue capacities from the venues table
  6. Curated world-elite brands and prestigious youth academies

Outputs:
  - SQLite table update in data/powerfootball_master.db & data_pipeline/powerfootball_master.db
  - Export snapshot in data_pipeline/data_lake_2026/team_finances_facilities_2026.json
"""

import argparse
import json
import math
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

# Key European and Global Seasons (2026/2027) in data_lake_2026/raw_seasons.jsonl
KEY_SEASONS = [
    {"season_id": 28155, "name": "UEFA Champions League", "league_id": 2},
    {"season_id": 27913, "name": "UEFA Europa League", "league_id": 5},
    {"season_id": 28083, "name": "Premier League (England)", "league_id": 8},
    {"season_id": 27903, "name": "Championship (England)", "league_id": 9},
    {"season_id": 27965, "name": "La Liga (Spain)", "league_id": 564},
    {"season_id": 27895, "name": "Serie A (Italy)", "league_id": 384},
    {"season_id": 28321, "name": "Bundesliga (Germany)", "league_id": 82},
    {"season_id": 28082, "name": "Ligue 1 (France)", "league_id": 301},
    {"season_id": 27958, "name": "Eredivisie (Netherlands)", "league_id": 72},
    {"season_id": 27947, "name": "Primeira Liga (Portugal)", "league_id": 462},
    {"season_id": 28003, "name": "Scottish Premiership", "league_id": 181},
    {"season_id": 27897, "name": "Belgian Pro League", "league_id": 271},
    {"season_id": 28203, "name": "Süper Lig (Turkey)", "league_id": 600},
    {"season_id": 26806, "name": "Allsvenskan (Sweden)", "league_id": 573},
]

# Exact lowercase names of curated global elite clubs
CURATED_ELITE_REPUTATION: Dict[str, float] = {
    "real madrid": 0.98,
    "real madrid cf": 0.98,
    "manchester city": 0.96,
    "man city": 0.96,
    "bayern münchen": 0.95,
    "fc bayern münchen": 0.95,
    "bayern munich": 0.95,
    "liverpool": 0.94,
    "liverpool fc": 0.94,
    "arsenal": 0.93,
    "arsenal fc": 0.93,
    "barcelona": 0.93,
    "fc barcelona": 0.93,
    "paris saint-germain": 0.92,
    "paris saint-germain fc": 0.92,
    "psg": 0.92,
    "inter": 0.91,
    "internazionale": 0.91,
    "inter milan": 0.91,
    "bayer 04 leverkusen": 0.89,
    "bayer leverkusen": 0.89,
    "borussia dortmund": 0.89,
    "bvb": 0.89,
    "chelsea": 0.88,
    "chelsea fc": 0.88,
    "atletico madrid": 0.88,
    "atlético madrid": 0.88,
    "club atlético de madrid": 0.88,
    "juventus": 0.87,
    "juventus fc": 0.87,
    "manchester united": 0.87,
    "manchester united fc": 0.87,
    "ac milan": 0.86,
    "tottenham hotspur": 0.86,
    "tottenham": 0.86,
    "newcastle united": 0.82,
    "aston villa": 0.82,
    "sporting cp": 0.83,
    "sporting lisbon": 0.83,
    "benfica": 0.83,
    "sl benfica": 0.83,
    "porto": 0.82,
    "fc porto": 0.82,
    "atalanta": 0.81,
    "napoli": 0.82,
    "ssc napoli": 0.82,
    "as roma": 0.80,
    "roma": 0.80,
    "lazio": 0.79,
    "ss lazio": 0.79,
    "ajax": 0.80,
    "afc ajax": 0.80,
    "monaco": 0.80,
    "as monaco": 0.80,
    "athletic club": 0.79,
    "athletic bilbao": 0.79,
    "real sociedad": 0.79,
    "rb leipzig": 0.81,
    "eintracht frankfurt": 0.78,
    "villarreal": 0.78,
    "villarreal cf": 0.78,
    "psv": 0.79,
    "psv eindhoven": 0.79,
    "feyenoord": 0.78,
    "galatasaray": 0.77,
    "fenerbahçe": 0.76,
    "fenerbahce": 0.76,
    "celtic": 0.76,
    "celtic fc": 0.76,
    "rangers": 0.75,
    "rangers fc": 0.75,
    "al-hilal": 0.78,
    "al nassr": 0.77,
    "al-nassr": 0.77,
    "al-ittihad": 0.76,
    "flamengo": 0.77,
    "palmeiras": 0.77,
    "river plate": 0.76,
    "boca juniors": 0.76,
    "inter miami": 0.72,
    "inter miami cf": 0.72,
}

# Prestigious youth academies renowned for world-class talent development (Youth Facility = 5)
PRESTIGIOUS_YOUTH_ACADEMIES: Set[str] = {
    "barcelona", "fc barcelona", "ajax", "afc ajax", "sporting cp", "benfica",
    "sl benfica", "southampton", "southampton fc", "lyon", "olympique lyonnais",
    "atalanta", "anderlecht", "rsc anderlecht", "dinamo zagreb", "gnk dinamo zagreb",
    "river plate", "ca river plate", "boca juniors", "athletic club", "athletic bilbao",
    "real sociedad", "santos", "santos fc", "são paulo", "sao paulo fc",
    "red bull salzburg", "fc red bull salzburg", "stade rennais", "rennes",
    "partizan", "fk partizan", "crvena zvezda", "fluminense", "arsenal",
    "chelsea", "manchester city", "real madrid", "bayern münchen", "bayern munich",
    "paris saint-germain", "psg"
}

# League pyramid base reputations by known League ID or naming pattern
LEAGUE_TIER_BASE: Dict[int, float] = {
    # England
    8: 0.48,    # Premier League
    9: 0.32,    # Championship
    12: 0.20,   # League One
    14: 0.14,   # League Two
    17: 0.09,   # National League
    20: 0.06,   # National League North
    # Spain
    564: 0.46,  # La Liga
    567: 0.28,  # La Liga 2
    570: 0.18,  # Primera Federacion
    # Italy
    384: 0.46,  # Serie A
    387: 0.28,  # Serie B
    391: 0.18,  # Serie C
    # Germany
    82: 0.46,   # Bundesliga
    85: 0.30,   # 2. Bundesliga
    88: 0.19,   # 3. Liga
    91: 0.10,   # Regionalliga Nord
    94: 0.10,   # Regionalliga Bayern
    97: 0.10,   # Regionalliga Nordost
    103: 0.10,  # Regionalliga Sudwest
    106: 0.10,  # Regionalliga West
    # France
    301: 0.40,  # Ligue 1
    304: 0.25,  # Ligue 2
    307: 0.15,  # National
    # Portugal
    462: 0.36,  # Primeira Liga
    465: 0.20,  # Liga Portugal 2
    # Netherlands
    72: 0.36,   # Eredivisie
    74: 0.20,   # Eerste Divisie
    77: 0.12,   # Tweede Divisie
    # Scotland
    181: 0.32,  # Premiership
    504: 0.18,  # Championship
    508: 0.12,  # League One
    511: 0.08,  # League Two
    # Belgium
    271: 0.35,  # Pro League
    274: 0.20,  # Challenger Pro League
    # Turkey
    600: 0.36,  # Super Lig
    # Sweden
    573: 0.30,  # Allsvenskan
    576: 0.17,  # Superettan
    # USA
    779: 0.36,  # Major League Soccer
    # Saudi Arabia
    948: 0.40,  # Saudi Pro League
    # Argentina & Brazil
    636: 0.38,  # Liga Profesional Argentina
    648: 0.40,  # Serie A Brazil
}


# =============================================================================
# SPORTMONKS API FETCHER
# =============================================================================

class SportMonksDataHarvester:
    def __init__(self, api_token: str, cache_file: Path):
        self.api_token = api_token
        self.cache_file = cache_file
        self.headers = {
            "Authorization": self.api_token,
            "Accept": "application/json",
            "User-Agent": "PowerFootball-Balancing/1.0"
        }
        self.cache: Dict[str, Any] = self._load_cache()

    def _load_cache(self) -> Dict[str, Any]:
        if self.cache_file.exists():
            try:
                with open(self.cache_file, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def _save_cache(self) -> None:
        self.cache_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.cache_file, "w", encoding="utf-8") as f:
            json.dump(self.cache, f, indent=2, ensure_ascii=False)

    def _get(self, endpoint: str, params: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        if params is None:
            params = {}
        query_str = "?" + urllib.parse.urlencode(params) if params else ""
        url = f"{BASE_URL}/{endpoint}{query_str}"
        req = urllib.request.Request(url, headers=self.headers)

        backoff = 1.0
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=20) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    print(f"    [Rate Limit 429] Pacing API request for {backoff:.1f}s...")
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

    def fetch_season_teams_bulk(self, season_id: int) -> List[Dict[str, Any]]:
        cache_key = f"season_{season_id}"
        if cache_key in self.cache:
            return self.cache[cache_key]

        print(f"  Fetching SportMonks season {season_id} (rankings, trophies, venue)...")
        payload = self._get(f"teams/seasons/{season_id}", {"include": "rankings;trophies;venue"})
        if not payload or "data" not in payload:
            return []

        teams = payload["data"]
        extracted: List[Dict[str, Any]] = []
        for t in teams:
            t_id = t.get("id")
            if not t_id:
                continue
            rankings = t.get("rankings", [])
            trophies = t.get("trophies", [])
            venue = t.get("venue") or {}

            best_points = 0
            best_pos = 999
            for r in rankings:
                pts = r.get("points") or 0
                pos = r.get("position") or 999
                if pts > best_points:
                    best_points = pts
                if pos < best_pos:
                    best_pos = pos

            extracted.append({
                "team_id": t_id,
                "name": t.get("name"),
                "ranking_points": best_points,
                "ranking_position": best_pos if best_pos < 999 else None,
                "trophies_count": len(trophies),
                "venue_capacity": venue.get("capacity")
            })

        self.cache[cache_key] = extracted
        self._save_cache()
        return extracted


# =============================================================================
# BALANCING MATHEMATICAL MODEL
# =============================================================================

def resolve_stature(reputation: float) -> str:
    """Matches shared/TeamData.gd::get_stature_from_reputation()."""
    if reputation >= 0.85:
        return "Continental Giant"
    elif reputation >= 0.70:
        return "Top Flight Heavyweight"
    elif reputation >= 0.45:
        return "Mid-Table Regular"
    elif reputation >= 0.25:
        return "Relegation Battler"
    return "Lower League Underdog"


def round_to_multiple(val: int, multiple: int) -> int:
    return max(multiple, int(round(val / float(multiple))) * multiple)


def compute_weekly_wage_budget(reputation: float) -> int:
    """
    Weekly payroll budget scaling across the 5 stature tiers:
      Continental Giant:     €600k – €1.6M / wk
      Top Flight Heavyweight: €250k – €600k / wk
      Mid-Table Regular:     €90k  – €250k / wk
      Relegation Battler:    €25k  – €90k  / wk
      Lower League Underdog: €3.5k – €25k  / wk
    """
    raw = 3000.0 + 1750000.0 * math.pow(reputation, 3.2)
    if reputation >= 0.70:
        return round_to_multiple(int(raw), 10000)
    elif reputation >= 0.40:
        return round_to_multiple(int(raw), 5000)
    elif reputation >= 0.25:
        return round_to_multiple(int(raw), 1000)
    return round_to_multiple(int(raw), 500)


def compute_transfer_budget(reputation: float) -> int:
    """
    Transfer kitty scaling across the 5 stature tiers:
      Continental Giant:     €45M – €150M
      Top Flight Heavyweight: €15M – €45M
      Mid-Table Regular:     €4M  – €15M
      Relegation Battler:    €1M  – €4M
      Lower League Underdog: €50k – €1M
    """
    raw = 50000.0 + 150000000.0 * math.pow(reputation, 3.5)
    if reputation >= 0.80:
        return round_to_multiple(int(raw), 1000000)
    elif reputation >= 0.60:
        return round_to_multiple(int(raw), 500000)
    elif reputation >= 0.40:
        return round_to_multiple(int(raw), 250000)
    elif reputation >= 0.25:
        return round_to_multiple(int(raw), 50000)
    return round_to_multiple(int(raw), 25000)


def compute_facilities(
    reputation: float,
    capacity: int,
    team_name_lower: str
) -> Tuple[int, int, int]:
    """
    Calculates (training_facilities, youth_facilities, medical_facilities) in 1..5.
    Accounts for stature, stadium scale, and legendary youth academies.
    """
    # 1. Base training facilities derived from reputation (1 to 5)
    training = max(1, min(5, int(round(reputation * 4.5)) + 1))
    if capacity >= 60000:
        training = max(training, 5)
    elif capacity >= 45000:
        training = max(training, 4)

    # 2. Medical facility tier follows training standard closely
    medical = training if reputation >= 0.68 else max(1, training - 1)
    if capacity >= 55000:
        medical = max(medical, 4)

    # 3. Youth facility tier
    youth = training if reputation >= 0.78 else max(1, training - 1)

    # Academy prestige boost for renowned developer clubs
    if team_name_lower in PRESTIGIOUS_YOUTH_ACADEMIES:
        youth = 5

    return training, youth, medical


# =============================================================================
# DATA PIPELINE BALANCER ENGINE
# =============================================================================

class TeamFinancesAndFacilitiesBalancer:
    def __init__(self, db_path: Path, api_token: str, cache_file: Path):
        self.db_path = db_path
        self.api_token = api_token
        self.cache_file = cache_file
        self.harvester = SportMonksDataHarvester(api_token, cache_file)

    def _ensure_columns_exist(self, conn: sqlite3.Connection) -> None:
        """Adds finance and facility columns to teams table if absent."""
        cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(teams);")
        existing_cols = {row[1] for row in cursor.fetchall()}

        new_columns = [
            ("reputation", "REAL DEFAULT 0.50"),
            ("stature", "TEXT DEFAULT 'Mid-Table Regular'"),
            ("transfer_budget", "INTEGER DEFAULT 10000000"),
            ("wage_budget_weekly", "INTEGER DEFAULT 250000"),
            ("training_facilities", "INTEGER DEFAULT 3"),
            ("youth_facilities", "INTEGER DEFAULT 3"),
            ("medical_facilities", "INTEGER DEFAULT 3")
        ]

        for col_name, col_def in new_columns:
            if col_name not in existing_cols:
                print(f"  Adding column '{col_name}' to teams table...")
                cursor.execute(f"ALTER TABLE teams ADD COLUMN {col_name} {col_def};")
        conn.commit()

    def run(self, harvest_api: bool = True) -> Dict[str, Any]:
        print(f"\nBalancing club finances & facilities for: {self.db_path.resolve()}")
        if not self.db_path.exists():
            raise FileNotFoundError(f"Database not found at {self.db_path}")

        conn = sqlite3.connect(self.db_path)
        self._ensure_columns_exist(conn)
        cursor = conn.cursor()

        # 1. Harvest SportMonks data for key leagues/tournaments if requested
        api_data_by_team_id: Dict[int, Dict[str, Any]] = {}
        if harvest_api:
            print("\n[Step 1/5] Harvesting real-world rankings, trophies & venues via SportMonks API...")
            for s in KEY_SEASONS:
                season_teams = self.harvester.fetch_season_teams_bulk(s["season_id"])
                for st in season_teams:
                    api_data_by_team_id[st["team_id"]] = st
            print(f"  SportMonks data cached for {len(api_data_by_team_id)} prominent clubs.")
        else:
            print("\n[Step 1/5] Skipping live SportMonks harvest (using local cache).")
            for k, season_teams in self.harvester.cache.items():
                if isinstance(season_teams, list):
                    for st in season_teams:
                        if isinstance(st, dict) and "team_id" in st:
                            api_data_by_team_id[st["team_id"]] = st

        # 2. Pre-load venues capacity
        print("\n[Step 2/5] Loading venue stadium capacities...")
        cursor.execute("SELECT venue_id, capacity FROM venues;")
        venue_capacities: Dict[int, int] = {row[0]: (row[1] or 0) for row in cursor.fetchall()}

        # 3. Pre-load continental tournament participants
        print("\n[Step 3/5] Loading tournament participant history...")
        cursor.execute("SELECT team_id, competition_id, stage_reached FROM tournament_participants;")
        tournaments_by_team: Dict[int, List[Tuple[int, str]]] = {}
        for tid, cid, stage in cursor.fetchall():
            tournaments_by_team.setdefault(tid, []).append((cid, stage or ""))

        # 4. Pre-load squad player attribute averages
        print("\n[Step 4/5] Computing squad player attribute aggregates from players table...")
        cursor.execute("""
            SELECT c.team_id,
                   COUNT(p.player_id),
                   AVG(p.vision),
                   AVG(p.composure),
                   AVG(p.determination),
                   AVG(p.work_rate),
                   AVG(p.close_control)
            FROM contracts c
            JOIN players p ON c.player_id = p.player_id
            GROUP BY c.team_id;
        """)
        squad_stats: Dict[int, Dict[str, float]] = {}
        for tid, count, vis, comp, det, wr, cc in cursor.fetchall():
            squad_stats[tid] = {
                "count": count,
                "avg_vision": vis or 0.5,
                "avg_composure": comp or 0.5,
                "avg_determination": det or 0.5,
                "avg_work_rate": wr or 0.5,
                "avg_close_control": cc or 0.5,
            }

        # 5. Fetch all teams and compute balanced values
        print("\n[Step 5/5] Executing mathematical calibration across all teams...")
        cursor.execute("SELECT team_id, league_id, venue_id, name, gender FROM teams;")
        all_teams = cursor.fetchall()

        update_batch: List[Tuple[float, str, int, int, int, int, int, int]] = []
        stature_counts: Dict[str, int] = {
            "Continental Giant": 0,
            "Top Flight Heavyweight": 0,
            "Mid-Table Regular": 0,
            "Relegation Battler": 0,
            "Lower League Underdog": 0,
        }
        results_snapshot: List[Dict[str, Any]] = []

        for tid, lid, vid, name, gender in all_teams:
            name_clean = (name or "").strip()
            name_lower = name_clean.lower()

            # Check curated elite override by exact match
            curated_rep = CURATED_ELITE_REPUTATION.get(name_lower)

            # Capacity
            capacity = venue_capacities.get(vid, 0)
            sm_team = api_data_by_team_id.get(tid)
            if sm_team and sm_team.get("venue_capacity"):
                capacity = max(capacity, sm_team["venue_capacity"] or 0)

            if curated_rep is not None:
                rep = curated_rep
            else:
                # Base reputation from league pyramid
                base_rep = LEAGUE_TIER_BASE.get(lid, 0.22)

                # SportMonks UEFA coefficient ranking points modifier
                sm_pts_mod = 0.0
                if sm_team:
                    pts = sm_team.get("ranking_points") or 0
                    if pts >= 100000:
                        sm_pts_mod = 0.35
                    elif pts >= 70000:
                        sm_pts_mod = 0.28
                    elif pts >= 40000:
                        sm_pts_mod = 0.20
                    elif pts >= 20000:
                        sm_pts_mod = 0.12
                    elif pts >= 5000:
                        sm_pts_mod = 0.06

                    # Trophies bonus
                    trophies = sm_team.get("trophies_count") or 0
                    if trophies > 0:
                        sm_pts_mod += min(0.04, math.log10(trophies + 1) * 0.025)

                # Tournament participant modifier (small boost for active qualification)
                tourn_mod = 0.0
                for cid, stage in tournaments_by_team.get(tid, []):
                    if cid == 2:  # Champions League
                        tourn_mod = max(tourn_mod, 0.06)
                    elif cid == 5:  # Europa League
                        tourn_mod = max(tourn_mod, 0.03)
                    elif cid == 2286:  # Conference League
                        tourn_mod = max(tourn_mod, 0.02)
                    elif cid == 1122:  # Copa Libertadores
                        tourn_mod = max(tourn_mod, 0.05)

                # Capacity modifier
                cap_mod = 0.0
                if capacity >= 70000:
                    cap_mod = 0.05
                elif capacity >= 50000:
                    cap_mod = 0.03
                elif capacity >= 35000:
                    cap_mod = 0.01
                elif capacity < 8000 and capacity > 0:
                    cap_mod = -0.02
                elif capacity < 3000 and capacity > 0:
                    cap_mod = -0.04

                # Squad ability aggregate modifier
                squad_mod = 0.0
                sq = squad_stats.get(tid)
                if sq and sq["count"] >= 11:
                    overall_score = (
                        sq["avg_vision"] * 0.25 +
                        sq["avg_composure"] * 0.25 +
                        sq["avg_determination"] * 0.20 +
                        sq["avg_work_rate"] * 0.15 +
                        sq["avg_close_control"] * 0.15
                    )
                    # Baseline squad talent sits at ~0.50
                    squad_mod = (overall_score - 0.50) * 0.25

                raw_rep = base_rep + sm_pts_mod + tourn_mod + cap_mod + squad_mod
                rep = max(0.05, min(0.97, raw_rep))

            rep = round(rep, 2)
            stature = resolve_stature(rep)
            wage_weekly = compute_weekly_wage_budget(rep)
            transfer_budget = compute_transfer_budget(rep)
            training_fac, youth_fac, med_fac = compute_facilities(rep, capacity, name_lower)

            stature_counts[stature] += 1
            update_batch.append((
                rep,
                stature,
                transfer_budget,
                wage_weekly,
                training_fac,
                youth_fac,
                med_fac,
                tid
            ))

            if len(results_snapshot) < 500 or stature in ("Continental Giant", "Top Flight Heavyweight"):
                results_snapshot.append({
                    "team_id": tid,
                    "name": name_clean,
                    "league_id": lid,
                    "reputation": rep,
                    "stature": stature,
                    "transfer_budget": transfer_budget,
                    "wage_budget_weekly": wage_weekly,
                    "training_facilities": training_fac,
                    "youth_facilities": youth_fac,
                    "medical_facilities": med_fac,
                    "stadium_capacity": capacity
                })

        # Execute batch update
        print(f"  Committing {len(update_batch)} club updates to SQLite...")
        cursor.executemany("""
            UPDATE teams
            SET reputation = ?,
                stature = ?,
                transfer_budget = ?,
                wage_budget_weekly = ?,
                training_facilities = ?,
                youth_facilities = ?,
                medical_facilities = ?
            WHERE team_id = ?;
        """, update_batch)
        conn.commit()
        conn.close()

        print("\n==========================================================")
        print("CLUB REPUTATION & FINANCES BALANCING COMPLETE")
        print("==========================================================")
        for stat, count in sorted(stature_counts.items(), key=lambda x: x[1], reverse=True):
            pct = (count / len(all_teams)) * 100.0
            print(f"  {stat:24} : {count:5} clubs ({pct:5.1f}%)")
        print("==========================================================")

        return {
            "total_teams": len(all_teams),
            "stature_counts": stature_counts,
            "snapshot": results_snapshot
        }


# =============================================================================
# CLI ENTRY POINT
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Balance club reputation, stature, budgets and facilities")
    parser.add_argument("--token", type=str, default=os.environ.get("SPORTMONKS_API_TOKEN", DEFAULT_API_TOKEN), help="SportMonks API token")
    parser.add_argument("--no-api", action="store_true", help="Skip live API requests and rely on local cache")
    parser.add_argument("--sync-sqlite", action="store_true", default=True, help="Update master SQLite databases")
    args = parser.parse_args()

    cache_file = Path("data_pipeline/data_lake_2026/sportmonks_rankings_cache.json")

    # Target both master databases
    db_paths = [
        Path("data/powerfootball_master.db"),
        Path("data_pipeline/powerfootball_master.db")
    ]

    last_summary = None
    for p in db_paths:
        if p.exists():
            balancer = TeamFinancesAndFacilitiesBalancer(
                db_path=p,
                api_token=args.token,
                cache_file=cache_file
            )
            # Only do the live API fetch on the first database pass; second pass reuses cache
            do_api = not args.no_api and (last_summary is None)
            last_summary = balancer.run(harvest_api=do_api)

    # Save snapshot JSON
    export_path = Path("data_pipeline/data_lake_2026/team_finances_facilities_2026.json")
    if last_summary and "snapshot" in last_summary:
        export_path.parent.mkdir(parents=True, exist_ok=True)
        with open(export_path, "w", encoding="utf-8") as f:
            json.dump({
                "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "total_clubs_balanced": last_summary["total_teams"],
                "stature_distribution": last_summary["stature_counts"],
                "teams": last_summary["snapshot"]
            }, f, indent=2, ensure_ascii=False)
        print(f"\nSaved export snapshot to {export_path.resolve()}")


if __name__ == "__main__":
    main()
