#!/usr/bin/env python3
"""
build_master_database.py

Robust transformationsmotor för PowerFootball-2D.
Identifierar automatiskt sökvägen till data_lake_2026 och bygger en
normaliserad SQLite-databas i data_pipeline oavsett arbetskatalog.
"""

import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, Any, Optional

# =============================================================================
# AUTOMATISK SÖKVÄGSHANTERING
# =============================================================================
def resolve_directories() -> tuple[Path, Path]:
    """Identifierar var JSONL-filerna ligger och var databasen ska sparas."""
    current_dir = Path.cwd()
    
    # Alternativ 1: Skriptet körs inuti data_lake_2026
    if (current_dir / "raw_teams_call_a.jsonl").exists():
        lake_dir = current_dir
        db_path = current_dir.parent / "powerfootball_master.db"
    # Alternativ 2: Skriptet körs från data_pipeline
    elif (current_dir / "data_lake_2026" / "raw_teams_call_a.jsonl").exists():
        lake_dir = current_dir / "data_lake_2026"
        db_path = current_dir / "powerfootball_master.db"
    # Alternativ 3: Reserv via skriptets faktiska placering på disk
    else:
        script_dir = Path(__file__).resolve().parent
        if (script_dir / "data_lake_2026" / "raw_teams_call_a.jsonl").exists():
            lake_dir = script_dir / "data_lake_2026"
            db_path = script_dir / "powerfootball_master.db"
        else:
            lake_dir = script_dir
            db_path = script_dir / "powerfootball_master.db"
            
    return lake_dir, db_path

DATA_LAKE_DIR, DB_OUTPUT_PATH = resolve_directories()

# =============================================================================
# SÄKER PARSNING
# =============================================================================
class SafeDataParser:
    @staticmethod
    def parse_int(val: Any, default: Optional[int] = None) -> Optional[int]:
        if val is None:
            return default
        if isinstance(val, int):
            return val
        m = re.search(r"\d+", str(val))
        return int(m.group(0)) if m else default

    @staticmethod
    def parse_float(val: Any, default: float = 75.0) -> float:
        if val is None:
            return default
        if isinstance(val, (int, float)):
            return float(val)
        m = re.search(r"(\d+(\.\d+)?)", str(val))
        return float(m.group(1)) if m else default


# =============================================================================
# DATABASBYGGARE
# =============================================================================
class MasterDatabaseBuilder:
    def __init__(self, lake_dir: Path, db_path: Path):
        self.lake_dir = lake_dir
        self.db_path = db_path
        
        print(f"Läser rådata från: {self.lake_dir.resolve()}")
        print(f"Skapar databas vid: {self.db_path.resolve()}\n")

        if self.db_path.exists():
            self.db_path.unlink()
            
        self.conn = sqlite3.connect(self.db_path)
        self.conn.execute("PRAGMA foreign_keys = OFF;")
        self.conn.execute("PRAGMA journal_mode = WAL;")
        self.conn.execute("PRAGMA synchronous = NORMAL;")
        
        self.cursor = self.conn.cursor()
        self._create_tables()

    def _create_tables(self):
        self.cursor.execute('''
        CREATE TABLE leagues (
            league_id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            country_code TEXT,
            sub_type TEXT,
            logo_url TEXT
        );''')

        self.cursor.execute('''
        CREATE TABLE seasons (
            season_id INTEGER PRIMARY KEY,
            league_id INTEGER,
            name TEXT NOT NULL,
            is_current INTEGER DEFAULT 1,
            start_date TEXT,
            end_date TEXT
        );''')

        self.cursor.execute('''
        CREATE TABLE venues (
            venue_id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            city TEXT,
            capacity INTEGER,
            surface_type TEXT,
            image_url TEXT
        );''')

        self.cursor.execute('''
        CREATE TABLE teams (
            team_id INTEGER PRIMARY KEY,
            venue_id INTEGER,
            league_id INTEGER,
            name TEXT NOT NULL,
            short_code TEXT,
            founded_year INTEGER,
            official_website TEXT,
            logo_url TEXT,
            wikipedia_extract TEXT,
            wikidata_qid TEXT
        );''')

        self.cursor.execute('''
        CREATE TABLE coaches (
            coach_id INTEGER PRIMARY KEY,
            team_id INTEGER,
            common_name TEXT NOT NULL,
            first_name TEXT,
            last_name TEXT,
            nationality TEXT,
            date_of_birth TEXT,
            image_url TEXT
        );''')

        self.cursor.execute('''
        CREATE TABLE team_rivals (
            team_id INTEGER NOT NULL,
            rival_team_id INTEGER NOT NULL,
            PRIMARY KEY (team_id, rival_team_id)
        );''')

        self.cursor.execute('''
        CREATE TABLE players (
            player_id INTEGER PRIMARY KEY,
            player_name TEXT NOT NULL,
            first_name TEXT,
            last_name TEXT,
            position_role TEXT,
            nationality TEXT,
            date_of_birth TEXT,
            height_cm INTEGER,
            weight_kg REAL,
            image_url TEXT,
            mass REAL DEFAULT 75.0,
            top_speed REAL DEFAULT 210.0,
            stamina_max REAL DEFAULT 100.0,
            vision REAL DEFAULT 0.65,
            composure REAL DEFAULT 0.60,
            aggression REAL DEFAULT 0.60,
            close_control REAL DEFAULT 0.65,
            reflexes REAL DEFAULT 0.60,
            determination REAL DEFAULT 0.65,
            work_rate REAL DEFAULT 0.65
        );''')

        self.cursor.execute('''
        CREATE TABLE contracts (
            contract_id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER NOT NULL,
            team_id INTEGER NOT NULL,
            season_id INTEGER NOT NULL,
            jersey_number INTEGER,
            position_name TEXT,
            contract_start TEXT,
            contract_end TEXT
        );''')

        self.cursor.execute("CREATE INDEX idx_teams_league ON teams(league_id);")
        self.cursor.execute("CREATE INDEX idx_contracts_team ON contracts(team_id);")
        self.cursor.execute("CREATE INDEX idx_contracts_player ON contracts(player_id);")
        self.conn.commit()

    def build_database(self):
        print("==========================================================")
        print("BYGGER NORMALISERAD MASTER-DATABAS FÖR GODOT 4.7")
        print("==========================================================")

        wiki_data = self._load_wikidata_lookup()
        wiki_extracts = self._load_wikipedia_lookup()

        self._import_leagues_and_seasons()
        self._import_teams_and_topology(wiki_data, wiki_extracts)
        self._import_players_and_contracts()

        self.conn.commit()
        self.conn.execute("PRAGMA optimize;")
        self.conn.close()

        file_size_mb = self.db_path.stat().st_size / (1024 * 1024)
        print("\n==========================================================")
        print(f"KLART! Databas sparad: {self.db_path.resolve()}")
        print(f"Slutgiltig filstorlek: {file_size_mb:.2f} MB")
        print("==========================================================")

    def _load_wikidata_lookup(self) -> Dict[str, dict]:
        lookup = {}
        wiki_file = self.lake_dir / "raw_wikidata_clubs.jsonl"
        if not wiki_file.exists():
            return lookup

        with open(wiki_file, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    d = json.loads(line.strip())
                    label = d.get("club_label")
                    if label:
                        lookup[label.lower()] = d
                except Exception:
                    pass
        print(f"Läste in {len(lookup)} uppslag från Wikidata.")
        return lookup

    def _load_wikipedia_lookup(self) -> Dict[str, str]:
        lookup = {}
        wiki_file = self.lake_dir / "raw_wikipedia_extracts.jsonl"
        if not wiki_file.exists():
            return lookup

        with open(wiki_file, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    d = json.loads(line.strip())
                    title = d.get("wikipedia_title")
                    extract = d.get("extract")
                    if title and extract:
                        lookup[title] = extract
                except Exception:
                    pass
        print(f"Läste in {len(lookup)} sammanfattningar från Wikipedia.")
        return lookup

    def _import_leagues_and_seasons(self):
        leagues_file = self.lake_dir / "raw_leagues.jsonl"
        seasons_file = self.lake_dir / "raw_seasons.jsonl"
        l_count = 0
        s_count = 0

        if leagues_file.exists():
            with open(leagues_file, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        l = json.loads(line.strip())
                        self.cursor.execute('''
                            INSERT OR IGNORE INTO leagues (league_id, name, country_code, sub_type, logo_url)
                            VALUES (?, ?, ?, ?, ?)
                        ''', (l.get("id"), l.get("name"), str(l.get("country_id")), l.get("sub_type"), l.get("image_path")))
                        l_count += 1
                    except Exception:
                        pass

        if seasons_file.exists():
            with open(seasons_file, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        s = json.loads(line.strip())
                        self.cursor.execute('''
                            INSERT OR IGNORE INTO seasons (season_id, league_id, name, is_current, start_date, end_date)
                            VALUES (?, ?, ?, 1, ?, ?)
                        ''', (s.get("id"), s.get("league_id"), s.get("name"), s.get("starting_at"), s.get("ending_at")))
                        s_count += 1
                    except Exception:
                        pass
                        
        self.conn.commit()
        print(f"Importerade {l_count} ligor och {s_count} säsonger.")

    def _import_teams_and_topology(self, wiki_data: dict, wiki_extracts: dict):
        teams_file = self.lake_dir / "raw_teams_call_a.jsonl"
        if not teams_file.exists():
            print(f"Fel: Hittade inte {teams_file}")
            return

        team_count = 0
        venue_count = 0
        coach_count = 0

        with open(teams_file, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    record = json.loads(line.strip())
                    team = record.get("team_data", {})
                    meta = record.get("_meta", {})
                    
                    t_id = team.get("id")
                    t_name = team.get("name")
                    if not t_id or not t_name:
                        continue

                    v_id = None
                    v = team.get("venue")
                    if isinstance(v, dict) and v.get("id"):
                        v_id = v.get("id")
                        self.cursor.execute('''
                            INSERT OR IGNORE INTO venues (venue_id, name, city, capacity, surface_type, image_url)
                            VALUES (?, ?, ?, ?, ?, ?)
                        ''', (
                            v_id, 
                            v.get("name") or "Okänd arena", 
                            v.get("city_name"), 
                            SafeDataParser.parse_int(v.get("capacity")), 
                            v.get("surface"), 
                            v.get("image_path")
                        ))
                        venue_count += 1

                    w_info = wiki_data.get(t_name.lower(), {})
                    w_title = w_info.get("wikipedia_title")
                    blurb = wiki_extracts.get(w_title) if w_title else None
                    founded_raw = team.get("founded") or w_info.get("inception")
                    founded_year = SafeDataParser.parse_int(founded_raw)

                    self.cursor.execute('''
                        INSERT OR REPLACE INTO teams 
                        (team_id, venue_id, league_id, name, short_code, founded_year, official_website, logo_url, wikipedia_extract, wikidata_qid)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ''', (
                        t_id, v_id, meta.get("league_id"), t_name, team.get("short_code"),
                        founded_year, w_info.get("website"), team.get("image_path"), blurb, w_info.get("wikidata_qid")
                    ))
                    team_count += 1

                    coaches = team.get("coaches", [])
                    if isinstance(coaches, list):
                        for coach in coaches:
                            if isinstance(coach, dict) and coach.get("id"):
                                self.cursor.execute('''
                                    INSERT OR IGNORE INTO coaches 
                                    (coach_id, team_id, common_name, first_name, last_name, nationality, date_of_birth, image_url)
                                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                                ''', (
                                    coach.get("id"), t_id,
                                    coach.get("common_name") or coach.get("name") or "Okänd",
                                    coach.get("firstname"), coach.get("lastname"),
                                    str(coach.get("nationality_id")), coach.get("date_of_birth"), coach.get("image_path")
                                ))
                                coach_count += 1

                    rivals = team.get("rivals", [])
                    if isinstance(rivals, list):
                        for rival in rivals:
                            if isinstance(rival, dict) and rival.get("id"):
                                self.cursor.execute('''
                                    INSERT OR IGNORE INTO team_rivals (team_id, rival_team_id)
                                    VALUES (?, ?)
                                ''', (t_id, rival.get("id")))

                except Exception:
                    pass

        self.conn.commit()
        print(f"Importerade {team_count} lag, {venue_count} arenor och {coach_count} tränare.")

    def _import_players_and_contracts(self):
        squads_file = self.lake_dir / "raw_squads_call_b.jsonl"
        if not squads_file.exists():
            print(f"Fel: Hittade inte {squads_file}")
            return

        print("Strömmar 121 MB spelartrupper...")
        inserted_players = set()
        contract_count = 0
        squad_lines = 0

        with open(squads_file, "r", encoding="utf-8") as f:
            for line in f:
                squad_lines += 1
                try:
                    record = json.loads(line.strip())
                    meta = record.get("_meta", {})
                    team_id = meta.get("team_id")
                    season_id = meta.get("season_id")
                    squad = record.get("squad_members", [])

                    if not isinstance(squad, list) or not team_id or not season_id:
                        continue

                    for member in squad:
                        if not isinstance(member, dict):
                            continue
                            
                        p = member.get("player")
                        if not isinstance(p, dict) or not p.get("id"):
                            continue

                        p_id = p.get("id")

                        if p_id not in inserted_players:
                            weight = SafeDataParser.parse_float(p.get("weight"), default=75.0)
                            height = SafeDataParser.parse_int(p.get("height"), default=180)
                            
                            self.cursor.execute('''
                                INSERT OR IGNORE INTO players 
                                (player_id, player_name, first_name, last_name, position_role, nationality, 
                                 date_of_birth, height_cm, weight_kg, image_url, mass)
                                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ''', (
                                p_id,
                                p.get("display_name") or p.get("name") or "Okänd",
                                p.get("firstname"),
                                p.get("lastname"),
                                member.get("position_name") or "CM",
                                str(p.get("nationality_id")),
                                p.get("date_of_birth"),
                                height,
                                weight,
                                p.get("image_path"),
                                weight
                            ))
                            inserted_players.add(p_id)

                        self.cursor.execute('''
                            INSERT INTO contracts 
                            (player_id, team_id, season_id, jersey_number, position_name, contract_start, contract_end)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                        ''', (
                            p_id, team_id, season_id,
                            SafeDataParser.parse_int(member.get("jersey_number")),
                            member.get("position_name"),
                            member.get("start"),
                            member.get("end")
                        ))
                        contract_count += 1

                except Exception:
                    pass

                if squad_lines % 500 == 0:
                    print(f"  Bearbetat {squad_lines} lagtrupper...")

        self.conn.commit()
        print(f"Totalt importerades {len(inserted_players)} unika spelare och {contract_count} kontrakt!")


if __name__ == "__main__":
    builder = MasterDatabaseBuilder(
        lake_dir=DATA_LAKE_DIR,
        db_path=DB_OUTPUT_PATH
    )
    builder.build_database()