#!/usr/bin/env python3
"""
mass_pyramid_populator.py

Storskalig attribut-hydrering för hela nationella seriesystem (England, Sverige,
Tyskland, Spanien, Italien, Frankrike m.fl.) i powerfootball_master.db via FM23.csv
och dynamisk positionsbaserad generering.
"""

import random
import re
import sqlite3
import unicodedata
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import pandas as pd
from rapidfuzz import fuzz, process

# =============================================================================
# AUTOMATISK SÖKVÄGSHANTERING
# =============================================================================
def resolve_paths() -> Tuple[Path, Path]:
    cwd = Path.cwd()
    if (cwd / "powerfootball_master.db").exists():
        return cwd / "powerfootball_master.db", cwd / "FM23.csv"
    if (cwd.parent / "powerfootball_master.db").exists():
        return cwd.parent / "powerfootball_master.db", cwd.parent / "FM23.csv"
    script_dir = Path(__file__).resolve().parent
    return script_dir / "powerfootball_master.db", script_dir / "FM23.csv"

DB_PATH, FM23_PATH = resolve_paths()

# =============================================================================
# PYRAMIDMÖNSTER OCH BASLINJER
# =============================================================================
# Regelverk: (regex-mönster, land/system, division-nivå, basbetyg)
PYRAMID_RULES = [
    # Sverige
    (r"allsvenskan", "Sverige", 1, 0.56),
    (r"superettan", "Sverige", 2, 0.44),
    (r"ettan", "Sverige", 3, 0.36),
    (r"division 1.*sweden", "Sverige", 3, 0.36),
    (r"division 2.*sweden", "Sverige", 4, 0.28),

    # England
    (r"premier league$", "England", 1, 0.76),
    (r"championship$", "England", 2, 0.58),
    (r"league one", "England", 3, 0.45),
    (r"league two", "England", 4, 0.36),
    (r"national league$", "England", 5, 0.28),
    (r"national league north", "England", 6, 0.22),
    (r"national league south", "England", 6, 0.22),

    # Tyskland
    (r"^bundesliga$", "Tyskland", 1, 0.74),
    (r"2\. bundesliga", "Tyskland", 2, 0.56),
    (r"3\. liga", "Tyskland", 3, 0.44),
    (r"regionalliga", "Tyskland", 4, 0.34),

    # Spanien
    (r"la liga$", "Spanien", 1, 0.75),
    (r"la liga 2", "Spanien", 2, 0.55),
    (r"segunda divisi[oó]n", "Spanien", 2, 0.55),
    (r"primera federaci[oó]n", "Spanien", 3, 0.42),
    (r"segunda federaci[oó]n", "Spanien", 4, 0.32),

    # Italien
    (r"^serie a$", "Italien", 1, 0.74),
    (r"^serie b$", "Italien", 2, 0.54),
    (r"^serie c", "Italien", 3, 0.41),

    # Frankrike
    (r"^ligue 1$", "Frankrike", 1, 0.73),
    (r"^ligue 2$", "Frankrike", 2, 0.52),
    (r"^national 1$", "Frankrike", 3, 0.40),
    (r"^national 2$", "Frankrike", 4, 0.30),

    # Övriga FM-toppligor
    (r"eredivisie", "Nederländerna", 1, 0.65),
    (r"eerste divisie", "Nederländerna", 2, 0.44),
    (r"primeira liga", "Portugal", 1, 0.66),
    (r"liga portugal 2", "Portugal", 2, 0.45),
    (r"premiership$", "Skottland", 1, 0.58),
    (r"championship.*scotland", "Skottland", 2, 0.40)
]


class MassPyramidPopulator:
    def __init__(self, db_path: Path, fm23_path: Path):
        self.db_path = db_path
        self.fm23_path = fm23_path
        
        print(f"Ansluter till Master DB: {self.db_path.resolve()}")
        self.conn = sqlite3.connect(self.db_path)
        self.cursor = self.conn.cursor()
        self.fm_pool = self._load_fm23_pool()

    @staticmethod
    def normalize_name(name: str) -> str:
        if not isinstance(name, str):
            return ""
        n = "".join(c for c in unicodedata.normalize("NFD", name) if unicodedata.category(c) != "Mn")
        n = re.sub(r"[^\w\s]", " ", n.lower())
        return re.sub(r"\s+", " ", n).strip()

    def _load_fm23_pool(self) -> List[Dict]:
        if not self.fm23_path.exists():
            print(f"[Info] {self.fm23_path.name} saknas. Kör enbart algoritmisk generering.")
            return []

        print(f"Läser in FM23-databasen ({self.fm23_path.name})...")
        try:
            df = pd.read_csv(self.fm23_path, low_memory=False)
        except Exception as e:
            print(f"[Fel] Kunde inte läsa FM23.csv: {e}")
            return []

        name_col = "Name" if "Name" in df.columns else df.columns[0]
        pool = []

        for _, row in df.iterrows():
            name = str(row.get(name_col, ""))
            if not name or name == "nan":
                continue

            def get_stat(col: str) -> Optional[float]:
                val = row.get(col)
                try:
                    v = float(val)
                    return min(max(v / 20.0, 0.05), 1.0)
                except (ValueError, TypeError):
                    return None

            pool.append({
                "name_norm": self.normalize_name(name),
                "vision": get_stat("Vis"),
                "composure": get_stat("Cmp"),
                "aggression": get_stat("Agg"),
                "close_control": get_stat("Tec"),
                "reflexes": get_stat("Ref"),
                "determination": get_stat("Det"),
                "work_rate": get_stat("Wor"),
                "pace": get_stat("Pac"),
                "stamina": get_stat("Sta")
            })

        print(f"Laddade {len(pool)} profiler från FM23 till snabbminnet.\n")
        return pool

    def generate_attributes(self, pos: str, baseline: float) -> Dict[str, float]:
        p = (pos or "CM").upper()

        def sample(weight: float = 1.0, spread: float = 0.05) -> float:
            target = baseline * weight
            val = random.gauss(target, spread)
            return round(min(max(val, 0.10), 0.95), 3)

        if "GK" in p:
            return {
                "mass": random.uniform(80.0, 92.0),
                "top_speed": 185.0 + sample(0.8) * 35.0,
                "stamina_max": 75.0 + sample(0.9) * 20.0,
                "vision": sample(0.80), "composure": sample(1.05), "aggression": sample(0.80),
                "close_control": sample(0.55), "reflexes": sample(1.30),
                "determination": sample(1.00), "work_rate": sample(0.90)
            }
        elif any(cb in p for cb in ["CB", "DEF", "BACK"]):
            return {
                "mass": random.uniform(76.0, 88.0),
                "top_speed": 200.0 + sample(0.95) * 40.0,
                "stamina_max": 80.0 + sample(1.0) * 20.0,
                "vision": sample(0.85), "composure": sample(0.95), "aggression": sample(1.20),
                "close_control": sample(0.80), "reflexes": sample(0.60),
                "determination": sample(1.10), "work_rate": sample(1.05)
            }
        elif any(st in p for st in ["ST", "CF", "FWD", "ATT"]):
            return {
                "mass": random.uniform(72.0, 84.0),
                "top_speed": 210.0 + sample(1.15) * 40.0,
                "stamina_max": 80.0 + sample(0.95) * 20.0,
                "vision": sample(0.90), "composure": sample(1.15), "aggression": sample(0.95),
                "close_control": sample(1.15), "reflexes": sample(0.55),
                "determination": sample(1.05), "work_rate": sample(0.95)
            }
        else:  # Mittfält
            return {
                "mass": random.uniform(68.0, 80.0),
                "top_speed": 205.0 + sample(1.05) * 40.0,
                "stamina_max": 85.0 + sample(1.1) * 15.0,
                "vision": sample(1.15), "composure": sample(1.05), "aggression": sample(1.00),
                "close_control": sample(1.10), "reflexes": sample(0.60),
                "determination": sample(1.00), "work_rate": sample(1.15)
            }

    def match_league_rule(self, league_name: str) -> Optional[Tuple[str, int, float]]:
        name_clean = league_name.lower().strip()
        for pattern, country, tier, baseline in PYRAMID_RULES:
            if re.search(pattern, name_clean):
                return country, tier, baseline
        return None

    def run(self):
        print("==========================================================")
        print("STARTAR MASS-HYDRERING FÖR NATIONELLA PYRAMIDER")
        print("==========================================================")

        self.cursor.execute("SELECT league_id, name FROM leagues")
        all_leagues = self.cursor.fetchall()

        matched_leagues = []
        for l_id, l_name in all_leagues:
            rule = self.match_league_rule(l_name)
            if rule:
                country, tier, baseline = rule
                matched_leagues.append((l_id, l_name, country, tier, baseline))

        print(f"Identifierade {len(matched_leagues)} ligor som ingår i pyramidreglerna.\n")

        fm_names = [p["name_norm"] for p in self.fm_pool] if self.fm_pool else []
        total_players_processed = 0
        total_fm_hits = 0

        for l_id, l_name, country, tier, baseline in matched_leagues:
            # Hämtar enbart spelare som fortfarande har standardattribut (vision=0.65 och composure=0.60)
            self.cursor.execute("""
                SELECT DISTINCT p.player_id, p.player_name, p.position_role
                FROM players p
                JOIN contracts c ON p.player_id = c.player_id
                JOIN teams t ON c.team_id = t.team_id
                JOIN seasons s ON c.season_id = s.season_id
                WHERE (s.league_id = ? OR t.league_id = ?)
                  AND (p.vision = 0.65 AND p.composure = 0.60)
            """, (l_id, l_id))
            unhydrated_players = self.cursor.fetchall()

            if not unhydrated_players:
                continue

            print(f"[{country} Tier {tier}] {l_name}: Berikar {len(unhydrated_players)} spelare (Baslinje: {baseline})...")

            batch_updates = []
            fm_hits = 0

            for p_id, p_name, pos in unhydrated_players:
                p_norm = self.normalize_name(p_name)
                stats = None

                if fm_names and p_norm:
                    match = process.extractOne(p_norm, fm_names, scorer=fuzz.token_sort_ratio, score_cutoff=88)
                    if match:
                        _, score, idx = match
                        cand = self.fm_pool[idx]
                        if cand.get("vision") is not None:
                            stats = {
                                "mass": 75.0,
                                "top_speed": 205.0 + ((cand.get("pace") or 0.5) * 40.0),
                                "stamina_max": 80.0 + ((cand.get("stamina") or 0.5) * 20.0),
                                "vision": cand.get("vision") or baseline,
                                "composure": cand.get("composure") or baseline,
                                "aggression": cand.get("aggression") or baseline,
                                "close_control": cand.get("close_control") or baseline,
                                "reflexes": cand.get("reflexes") or 0.50,
                                "determination": cand.get("determination") or baseline,
                                "work_rate": cand.get("work_rate") or baseline
                            }
                            fm_hits += 1

                if not stats:
                    stats = self.generate_attributes(pos, baseline)

                batch_updates.append((
                    stats["mass"], stats["top_speed"], stats["stamina_max"],
                    stats["vision"], stats["composure"], stats["aggression"],
                    stats["close_control"], stats["reflexes"], stats["determination"],
                    stats["work_rate"], p_id
                ))

            self.cursor.executemany("""
                UPDATE players
                SET mass = ?, top_speed = ?, stamina_max = ?,
                    vision = ?, composure = ?, aggression = ?,
                    close_control = ?, reflexes = ?, determination = ?, work_rate = ?
                WHERE player_id = ?
            """, batch_updates)
            self.conn.commit()

            total_players_processed += len(unhydrated_players)
            total_fm_hits += fm_hits
            print(f"  -> Klart: {fm_hits} FM23-träffar, {len(unhydrated_players) - fm_hits} proceduriella.\n")

        print("==========================================================")
        print(f"MASS-HYDRERING SLUTFÖRD!")
        print(f"Totalt berikades {total_players_processed} spelare över alla pyramider.")
        print(f"FM23-matchningar: {total_fm_hits} st.")
        print("==========================================================")

    def close(self):
        self.conn.close()


if __name__ == "__main__":
    populator = MassPyramidPopulator(DB_PATH, FM23_PATH)
    populator.run()
    populator.close()