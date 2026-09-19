#!/usr/bin/env python3
"""
powerfootball_database_builder.py

Detta skript kombinerar spelardata från två källor (FC26 och FM23), matchar spelarna,
konverterar attributen till PowerFootball-2D:s format (0.0-1.0) och bygger en
normaliserad SQLite-databas redo för Godot 4.7.
"""

import argparse
import ast
import re
import sqlite3
import unicodedata
from pathlib import Path

import pandas as pd
from rapidfuzz import fuzz, process

# =============================================================================
# KONFIGURATION & ALIAS
# =============================================================================
FM23_ALIASES = {
    "uid": ["UID"], "name": ["Name"], "dob_raw": ["DOB"], "nationality": ["Nat"],
    "age": ["Age"], "height_raw": ["Height"], "weight_raw": ["Weight"],
    "club": ["Club"], "position": ["Position"], "based": ["Based"],
    "transfer_value": ["Transfer Value"], "preferred_foot": ["Preferred Foot"],
    "acceleration": ["Acc"], "work_rate": ["Wor"], "vision": ["Vis"],
    "technique": ["Tec"], "teamwork": ["Tea"], "tackling": ["Tck"],
    "strength": ["Str"], "stamina": ["Sta"], "reflexes": ["Ref"],
    "positioning": ["Pos"], "passing": ["Pas"], "pace": ["Pac"],
    "off_the_ball": ["OtB"], "finishing": ["Fin"], "dribbling": ["Dri"],
    "composure": ["Cmp"], "decisions": ["Dec"], "anticipation": ["Ant"],
    "aggression": ["Agg"], "determination": ["Det"], "injury_proneness": ["Inj Pr"],
    "consistency": ["Cons"], "important_matches": ["Imp M"], "dirtiness": ["Dirt"],
    "professionalism": ["Prof"], "ambition": ["Amb"], "loyalty": ["Loy"]
}

FC26_ALIASES = {
    "name": ["Name"], "age": ["Age"], "nation": ["Nation"], "league": ["League"],
    "team": ["Team"], "position": ["Position"], "height_raw": ["Height"],
    "weight_raw": ["Weight"], "ovr": ["OVR"]
}

NAT_ALIASES = {
    "eng": "england", "sco": "scotland", "wal": "wales", "ger": "germany",
    "ned": "holland", "sui": "switzerland", "den": "denmark", "por": "portugal",
    "arg": "argentina", "bra": "brazil", "uru": "uruguay", "usa": "united states",
    "netherlands": "holland", "south korea": "korea republic", 
    "united states of america": "united states", "ireland": "republic of ireland"
}

# =============================================================================
# DATA NORMALISERING
# =============================================================================
class DataNormalizer:
    @staticmethod
    def strip_accents(s: str) -> str:
        if not isinstance(s, str): return ""
        return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")

    @classmethod
    def normalize_name(cls, name: str) -> str:
        n = cls.strip_accents(name).lower()
        n = re.sub(r"[^\w\s]", " ", n)
        return re.sub(r"\s+", " ", n).strip()

    @classmethod
    def normalize_nationality(cls, nat: str) -> str:
        nat_norm = cls.normalize_name(nat)
        return NAT_ALIASES.get(nat_norm, nat_norm)

    @staticmethod
    def parse_fm23_dob(s: str) -> pd.Timestamp:
        if not isinstance(s, str): return pd.NaT
        m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{4})", s)
        if not m: return pd.NaT
        d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if mo > 12 and d <= 12: d, mo = mo, d
        try: return pd.Timestamp(year=y, month=mo, day=d)
        except ValueError: return pd.NaT

    @staticmethod
    def parse_weight(s) -> float:
        if not isinstance(s, str): return 75.0
        m = re.search(r"(\d+)", s)
        return float(m.group(1)) if m else 75.0

    @staticmethod
    def resolve_columns(df: pd.DataFrame, aliases: dict, source: str) -> dict:
        resolved = {}
        for canonical, options in aliases.items():
            for opt in options:
                if opt in df.columns:
                    resolved[canonical] = opt
                    break
        return resolved

# =============================================================================
# MATCHNINGS-MOTOR
# =============================================================================
class PlayerMatcher:
    def __init__(self, min_score: int = 92):
        self.min_score = min_score

    def match(self, base_row: pd.Series, enrichment_pool: pd.DataFrame) -> tuple:
        if enrichment_pool.empty:
            return None, 0, "empty_pool"

        birth_year = base_row.get("birth_year")
        
        # 1. Filtrera på födelseår (±1 år)
        if pd.notna(birth_year):
            dob_band = enrichment_pool[
                enrichment_pool["dob"].notna() &
                ((enrichment_pool["dob"].dt.year - birth_year).abs() <= 1)
            ]
            pool = dob_band if not dob_band.empty else enrichment_pool
        else:
            pool = enrichment_pool

        # 2. Fuzzy match på namnet
        choice = process.extractOne(
            base_row["name_norm"],
            pool["name_norm"].tolist(),
            scorer=fuzz.token_sort_ratio,
        )
        if not choice: return None, 0, "no_choice"

        score = choice[1]
        candidate = pool.iloc[choice[2]]

        # 3. Slutgiltig utvärdering och tie-breakers
        if score < self.min_score: return None, score, "below_min"
        if score < 95:
            fc_last = base_row["name_norm"].split()[-1] if base_row["name_norm"] else ""
            fm_last = candidate["name_norm"].split()[-1] if candidate["name_norm"] else ""
            same_last = bool(fc_last) and fc_last == fm_last
            
            fc_pos = str(base_row.get("position", "")).lower()
            fm_pos = str(candidate.get("position", "")).lower()
            same_position = (fc_pos in fm_pos) or (fm_pos in fc_pos) if fc_pos and fm_pos else False
            
            if not (same_last or same_position):
                return None, score, "no_secondary_signal"

        return candidate, score, "ok"

# =============================================================================
# SQLITE EXPORT
# =============================================================================
class DatabaseExporter:
    def __init__(self, db_path: str):
        self.db_path = db_path
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(self.db_path)

    def build(self, df: pd.DataFrame):
        self._create_schema()
        self._populate_database(df)
        self.conn.close()

    def _create_schema(self):
        cursor = self.conn.cursor()
        
        # Tabeller designade för PowerFootball-2D:s GDScript-struktur
        cursor.execute('''CREATE TABLE IF NOT EXISTS clubs (
            club_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_name TEXT UNIQUE NOT NULL,
            reputation REAL DEFAULT 0.50,
            transfer_budget INTEGER DEFAULT 10000000,
            wage_budget_weekly INTEGER DEFAULT 250000)''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS players (
            player_id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_name TEXT NOT NULL,
            position_role TEXT,
            nationality TEXT,
            date_of_birth TEXT,
            mass REAL,
            top_speed REAL,
            stamina_max REAL,
            player_reputation REAL)''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS player_attributes (
            player_id INTEGER PRIMARY KEY,
            vision REAL, composure REAL, aggression REAL, close_control REAL,
            reflexes REAL, determination REAL, work_rate REAL,
            FOREIGN KEY(player_id) REFERENCES players(player_id))''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS player_hidden_traits (
            player_id INTEGER PRIMARY KEY,
            injury_proneness REAL, consistency REAL, important_matches REAL,
            dirtiness REAL, professionalism REAL, ambition REAL, loyalty REAL,
            FOREIGN KEY(player_id) REFERENCES players(player_id))''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS contracts (
            contract_id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER, club_id INTEGER,
            wage_weekly INTEGER, contract_years INTEGER, release_clause INTEGER, squad_status TEXT,
            FOREIGN KEY(player_id) REFERENCES players(player_id),
            FOREIGN KEY(club_id) REFERENCES clubs(club_id))''')
        
        self.conn.commit()

    def _populate_database(self, df: pd.DataFrame):
        cursor = self.conn.cursor()
        
        # Hämta in klubbar
        unique_clubs = df['team'].dropna().unique()
        for club in unique_clubs:
            cursor.execute('INSERT OR IGNORE INTO clubs (team_name) VALUES (?)', (club,))
        self.conn.commit()
        club_map = dict(cursor.execute('SELECT team_name, club_id FROM clubs').fetchall())

        # Hjälpfunktion för att hantera None/NaN värden säkert
        def safe_val(val, default):
            if pd.isna(val) or val is None:
                return default
            return val

        # Skala mentala värden (1-20 till 0.0-1.0)
        def scale_1_20(val):
            v = safe_val(val, 10) # Fallback till 10 (vilket ger 0.5) om attribut saknas
            try: return min(max(float(v) / 20.0, 0.0), 1.0)
            except: return 0.5

        for _, row in df.iterrows():
            # 1. Base Player Data
            dob_val = row.get('fm_dob')
            dob_str = dob_val.strftime('%Y-%m-%d') if pd.notna(dob_val) else "2000-01-01"
            
            cursor.execute('''INSERT INTO players 
                (player_name, position_role, nationality, date_of_birth, mass, top_speed, stamina_max, player_reputation)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)''', (
                row['name'], 
                row.get('position', 'CM'),
                row.get('nationality_norm', ''),
                dob_str,
                safe_val(row.get('weight_kg'), 75.0),
                210.0 + (scale_1_20(row.get('fm_pace')) * 40.0), 
                float(safe_val(row.get('fm_stamina'), 10)) * 5.0, # Här säkerställer vi att vi aldrig multiplicerar None
                scale_1_20(row.get('fm_reputation'))
            ))
            player_id = cursor.lastrowid

            # 2. Match Engine Attributes (Synliga)
            cursor.execute('''INSERT INTO player_attributes 
                (player_id, vision, composure, aggression, close_control, reflexes, determination, work_rate)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)''', (
                player_id, scale_1_20(row.get('fm_vision')), scale_1_20(row.get('fm_composure')),
                scale_1_20(row.get('fm_aggression')), scale_1_20(row.get('fm_technique')),
                scale_1_20(row.get('fm_reflexes')), scale_1_20(row.get('fm_determination')),
                scale_1_20(row.get('fm_work_rate'))
            ))

            # 3. Dolda/Karriär Attribut
            cursor.execute('''INSERT INTO player_hidden_traits 
                (player_id, injury_proneness, consistency, important_matches, dirtiness, professionalism, ambition, loyalty)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)''', (
                player_id, scale_1_20(row.get('fm_injury_proneness')), scale_1_20(row.get('fm_consistency')),
                scale_1_20(row.get('fm_important_matches')), scale_1_20(row.get('fm_dirtiness')),
                scale_1_20(row.get('fm_professionalism')), scale_1_20(row.get('fm_ambition')),
                scale_1_20(row.get('fm_loyalty'))
            ))

            # 4. Kontrakt
            club_name = row.get('team')
            if pd.notna(club_name) and club_name in club_map:
                cursor.execute('''INSERT INTO contracts 
                    (player_id, club_id, wage_weekly, contract_years, release_clause, squad_status)
                    VALUES (?, ?, ?, ?, ?, ?)''', (
                    player_id, club_map[club_name],
                    safe_val(row.get('fm_wage'), 15000), 3, 0, "Regular Starter"
                ))

        self.conn.commit()
        print(f"Databas genererad med {len(df)} spelare och normaliserad.")

# =============================================================================
# HUVUDPROGRAM
# =============================================================================
def main():
    ap = argparse.ArgumentParser(description="Bygg SQLite databas för spelet")
    ap.add_argument("--fc", required=True, help="Sökväg till EAFC26 CSV (Spine)")
    ap.add_argument("--fm", required=True, help="Sökväg till FM23 CSV (Enrichment)")
    ap.add_argument("--db-out", default="powerfootball.db", help="Slutgiltig SQLite databas")
    args = ap.parse_args()

    print("--- Laddar data ---")
    fc = pd.read_csv(args.fc, low_memory=False)
    fm = pd.read_csv(args.fm, low_memory=False)

    fc_cols = DataNormalizer.resolve_columns(fc, FC26_ALIASES, "FC26")
    fc.rename(columns={v: k for k, v in fc_cols.items()}, inplace=True)
    fm_cols = DataNormalizer.resolve_columns(fm, FM23_ALIASES, "FM23")
    fm.rename(columns={v: k for k, v in fm_cols.items()}, inplace=True)

    fc["name_norm"] = fc["name"].apply(DataNormalizer.normalize_name)
    fc["birth_year"] = 2025 - pd.to_numeric(fc["age"], errors="coerce")
    fc["nationality_norm"] = fc["nation"].apply(DataNormalizer.normalize_nationality)
    fc["weight_kg"] = fc["weight_raw"].apply(DataNormalizer.parse_weight)

    fm["name_norm"] = fm["name"].apply(DataNormalizer.normalize_name)
    fm["dob"] = fm["dob_raw"].apply(DataNormalizer.parse_fm23_dob)
    if "nationality" in fm.columns:
        fm["nationality_norm"] = fm["nationality"].apply(DataNormalizer.normalize_nationality)

    print("--- Matchar spelare ---")
    matcher = PlayerMatcher(min_score=92)
    fm_by_nat = {n: g for n, g in fm.groupby("nationality_norm")}
    fm_used_indices = set()
    
    # Skapa de kolumner vi behöver hämta från FM23
    for attr in ["pace", "stamina", "reputation", "vision", "composure", "aggression", 
                 "technique", "reflexes", "determination", "work_rate", "injury_proneness", 
                 "consistency", "important_matches", "dirtiness", "professionalism", "ambition", "loyalty", "wage", "dob"]:
        fc[f"fm_{attr}"] = None

    matches_found = 0
    for idx, fc_row in fc.iterrows():
        pool = fm_by_nat.get(fc_row.get("nationality_norm", ""))
        if pool is None or pool.empty: continue

        available = pool[~pool.index.isin(fm_used_indices)]
        match_row, score, _ = matcher.match(fc_row, available)

        if match_row is not None:
            fm_used_indices.add(match_row.name)
            matches_found += 1
            
            # Kartlägg specifika attribut från FM till FC-raden
            fc.at[idx, "fm_pace"] = match_row.get("pace")
            fc.at[idx, "fm_stamina"] = match_row.get("stamina")
            fc.at[idx, "fm_vision"] = match_row.get("vision")
            fc.at[idx, "fm_composure"] = match_row.get("composure")
            fc.at[idx, "fm_aggression"] = match_row.get("aggression")
            fc.at[idx, "fm_technique"] = match_row.get("technique")
            fc.at[idx, "fm_reflexes"] = match_row.get("reflexes")
            fc.at[idx, "fm_determination"] = match_row.get("determination")
            fc.at[idx, "fm_work_rate"] = match_row.get("work_rate")
            fc.at[idx, "fm_injury_proneness"] = match_row.get("injury_proneness")
            fc.at[idx, "fm_consistency"] = match_row.get("consistency")
            fc.at[idx, "fm_professionalism"] = match_row.get("professionalism")
            fc.at[idx, "fm_dob"] = match_row.get("dob")
            # Du kan lägga till wage och reputation här om de existerar i källdatan

    print(f"Hittade {matches_found} matchningar.")
    
    print("--- Genererar SQLite Databas ---")
    exporter = DatabaseExporter(args.db_out)
    exporter.build(fc)
    print(f"Färdig! Databasen sparades som {args.db_out}.")

if __name__ == "__main__":
    main()