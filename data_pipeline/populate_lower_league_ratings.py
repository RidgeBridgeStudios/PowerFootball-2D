#!/usr/bin/env python3
"""
populate_lower_league_ratings.py

Kombinerar direkt FM23-matchning med positionsbaserad algoritmisk
generering för att fullborda alla spelarbetyg i Superettan.
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
    """Hittar databasen och CSV-filen oavsett aktiv katalog i terminalen."""
    cwd = Path.cwd()
    
    # Om vi står i data_pipeline
    if (cwd / "powerfootball_master.db").exists():
        return cwd / "powerfootball_master.db", cwd / "FM23.csv"
    # Om vi står i en undermapp (t.ex. data_lake_2026)
    if (cwd.parent / "powerfootball_master.db").exists():
        return cwd.parent / "powerfootball_master.db", cwd.parent / "FM23.csv"
        
    script_dir = Path(__file__).resolve().parent
    return script_dir / "powerfootball_master.db", script_dir / "FM23.csv"

DB_PATH, FM23_PATH = resolve_paths()

# Målnivå för Superettans genomsnittliga spelarstyrka (0.0 - 1.0)
SUPERETTAN_BASELINE = 0.44

class LowerLeagueRatingPopulator:
    def __init__(self, db_path: Path, fm23_path: Path):
        self.db_path = db_path
        self.fm23_path = fm23_path
        
        print(f"Ansluter till Master DB: {self.db_path.resolve()}")
        self.conn = sqlite3.connect(self.db_path)
        self.cursor = self.conn.cursor()
        self.fm_pool = self._load_fm23_pool()

    @staticmethod
    def normalize_name(name: str) -> str:
        """Tvättar accenter, specialtecken och gemener för exakt matchning."""
        if not isinstance(name, str):
            return ""
        n = "".join(c for c in unicodedata.normalize("NFD", name) if unicodedata.category(c) != "Mn")
        n = re.sub(r"[^\w\s]", " ", n.lower())
        return re.sub(r"\s+", " ", n).strip()

    def _load_fm23_pool(self) -> List[Dict]:
        """Läser in FM23.csv till en sökbar minnespool om filen existerar."""
        if not self.fm23_path.exists():
            print(f"[Info] {self.fm23_path.name} hittades inte. Kör 100% positionsanpassad generering.")
            return []

        print(f"Läser in FM23-databasen från: {self.fm23_path.resolve()}...")
        try:
            df = pd.read_csv(self.fm23_path, low_memory=False)
        except Exception as e:
            print(f"[Varning] Kunde inte läsa {self.fm23_path.name}: {e}")
            return []

        name_col = "Name" if "Name" in df.columns else df.columns[0]
        pool = []

        for _, row in df.iterrows():
            name = str(row.get(name_col, ""))
            if not name or name == "nan":
                continue

            def get_fm_stat(col_name: str) -> Optional[float]:
                val = row.get(col_name)
                try:
                    v = float(val)
                    return min(max(v / 20.0, 0.05), 1.0)
                except (ValueError, TypeError):
                    return None

            pool.append({
                "name_norm": self.normalize_name(name),
                "raw_name": name,
                "vision": get_fm_stat("Vis"),
                "composure": get_fm_stat("Cmp"),
                "aggression": get_fm_stat("Agg"),
                "close_control": get_fm_stat("Tec"),
                "reflexes": get_fm_stat("Ref"),
                "determination": get_fm_stat("Det"),
                "work_rate": get_fm_stat("Wor"),
                "pace": get_fm_stat("Pac"),
                "stamina": get_fm_stat("Sta")
            })

        print(f"Laddade {len(pool)} spelare från FM23 till matchningspoolen.\n")
        return pool

    def generate_procedural_attributes(self, position: str, baseline: float) -> Dict[str, float]:
        """Skapar balanserade attribut anpassade efter positionens profil."""
        pos = (position or "CM").upper()

        def sample(weight: float = 1.0, spread: float = 0.05) -> float:
            target = baseline * weight
            val = random.gauss(target, spread)
            return round(min(max(val, 0.15), 0.85), 3)

        if "GK" in pos:
            return {
                "mass": random.uniform(80.0, 92.0),
                "top_speed": 190.0 + sample(0.8) * 35.0,
                "stamina_max": 80.0 + sample(0.9) * 15.0,
                "vision": sample(0.80),
                "composure": sample(1.05),
                "aggression": sample(0.80),
                "close_control": sample(0.55),
                "reflexes": sample(1.30),
                "determination": sample(1.00),
                "work_rate": sample(0.90)
            }
        elif any(cb in pos for cb in ["CB", "DEF", "BACK"]):
            return {
                "mass": random.uniform(76.0, 88.0),
                "top_speed": 205.0 + sample(0.95) * 40.0,
                "stamina_max": 85.0 + sample(1.0) * 15.0,
                "vision": sample(0.85),
                "composure": sample(0.95),
                "aggression": sample(1.20),
                "close_control": sample(0.80),
                "reflexes": sample(0.60),
                "determination": sample(1.10),
                "work_rate": sample(1.05)
            }
        elif any(st in pos for st in ["ST", "CF", "FWD", "ATT"]):
            return {
                "mass": random.uniform(72.0, 84.0),
                "top_speed": 215.0 + sample(1.15) * 40.0,
                "stamina_max": 85.0 + sample(0.95) * 15.0,
                "vision": sample(0.90),
                "composure": sample(1.15),
                "aggression": sample(0.95),
                "close_control": sample(1.15),
                "reflexes": sample(0.55),
                "determination": sample(1.05),
                "work_rate": sample(0.95)
            }
        else:  # Mittfält (CM, DM, AM, W)
            return {
                "mass": random.uniform(68.0, 80.0),
                "top_speed": 210.0 + sample(1.05) * 40.0,
                "stamina_max": 90.0 + sample(1.1) * 10.0,
                "vision": sample(1.15),
                "composure": sample(1.05),
                "aggression": sample(1.00),
                "close_control": sample(1.10),
                "reflexes": sample(0.60),
                "determination": sample(1.00),
                "work_rate": sample(1.15)
            }

    def run(self):
        print("==========================================================")
        print("STARTAR ATTRIBUT-HYDRERING FÖR SUPERETTAN")
        print("==========================================================")

        # Sök efter Superettan i ligatabellen
        self.cursor.execute("SELECT league_id, name FROM leagues WHERE name LIKE '%Superettan%'")
        leagues = self.cursor.fetchall()

        if not leagues:
            print("Kunde inte hitta 'Superettan' i leagues-tabellen.")
            return

        fm_names = [p["name_norm"] for p in self.fm_pool] if self.fm_pool else []

        for league_id, league_name in leagues:
            print(f"--- Behandlar: {league_name} (ID: {league_id}) ---")
            
            # Hämta samtliga spelare som har kontrakt i Superettan
            self.cursor.execute("""
                SELECT DISTINCT p.player_id, p.player_name, p.position_role, t.name
                FROM players p
                JOIN contracts c ON p.player_id = c.player_id
                JOIN teams t ON c.team_id = t.team_id
                JOIN seasons s ON c.season_id = s.season_id
                WHERE s.league_id = ? OR t.league_id = ?
            """, (league_id, league_id))
            players = self.cursor.fetchall()

            if not players:
                print("  Inga spelare hittades för denna liga.\n")
                continue

            print(f"Hittade {len(players)} spelare i {league_name}. Beräknar attribut...")

            fm_count = 0
            proc_count = 0

            for p_id, p_name, pos, team_name in players:
                p_norm = self.normalize_name(p_name)
                matched_stats = None

                # 1. Testa FM23-matchning
                if fm_names and p_norm:
                    match = process.extractOne(p_norm, fm_names, scorer=fuzz.token_sort_ratio, score_cutoff=88)
                    if match:
                        _, score, idx = match
                        cand = self.fm_pool[idx]
                        if cand.get("vision") is not None:
                            matched_stats = {
                                "mass": 75.0,
                                "top_speed": 210.0 + ((cand.get("pace") or 0.5) * 40.0),
                                "stamina_max": 80.0 + ((cand.get("stamina") or 0.5) * 20.0),
                                "vision": cand.get("vision") or SUPERETTAN_BASELINE,
                                "composure": cand.get("composure") or SUPERETTAN_BASELINE,
                                "aggression": cand.get("aggression") or SUPERETTAN_BASELINE,
                                "close_control": cand.get("close_control") or SUPERETTAN_BASELINE,
                                "reflexes": cand.get("reflexes") or 0.5,
                                "determination": cand.get("determination") or SUPERETTAN_BASELINE,
                                "work_rate": cand.get("work_rate") or SUPERETTAN_BASELINE
                            }
                            fm_count += 1

                # 2. Generera positionsbaserat om FM23 saknar spelaren
                if not matched_stats:
                    matched_stats = self.generate_procedural_attributes(pos, SUPERETTAN_BASELINE)
                    proc_count += 1

                # 3. Uppdatera raden i masterdatabasen
                self.cursor.execute("""
                    UPDATE players
                    SET mass = ?, top_speed = ?, stamina_max = ?,
                        vision = ?, composure = ?, aggression = ?,
                        close_control = ?, reflexes = ?, determination = ?, work_rate = ?
                    WHERE player_id = ?
                """, (
                    matched_stats["mass"], matched_stats["top_speed"], matched_stats["stamina_max"],
                    matched_stats["vision"], matched_stats["composure"], matched_stats["aggression"],
                    matched_stats["close_control"], matched_stats["reflexes"], matched_stats["determination"],
                    matched_stats["work_rate"], p_id
                ))

            self.conn.commit()
            print(f"  -> Resultat för {league_name}:")
            print(f"     - FM23-matchade: {fm_count} spelare")
            print(f"     - Proceduriellt genererade: {proc_count} spelare")
            print(f"     - Total täckning: 100% ({len(players)}/{len(players)})\n")

        print("==========================================================")
        print("SUPERETTAN ÄR NU FULLT INTEGRERAD OCH SPELBAR!")
        print("==========================================================")

    def close(self):
        self.conn.close()


if __name__ == "__main__":
    populator = LowerLeagueRatingPopulator(DB_PATH, FM23_PATH)
    populator.run()
    populator.close()