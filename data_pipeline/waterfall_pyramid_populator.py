#!/usr/bin/env python3
"""
waterfall_pyramid_populator.py

Avancerad vattenfalls-hydrering för nationella ligapyramider.
Prioritetsordning:
  1. EA Sports FC 26 (via powerfootball.db)
  2. Football Manager 2023 (via FM23.csv)
  3. Proceduriell positionskalibrerad generator
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
# SÖKVÄGSHANTERING
# =============================================================================
def resolve_paths() -> Tuple[Path, Path, Path]:
    cwd = Path.cwd()
    if (cwd / "powerfootball_master.db").exists():
        base = cwd
    elif (cwd.parent / "powerfootball_master.db").exists():
        base = cwd.parent
    else:
        base = Path(__file__).resolve().parent

    return (
        base / "powerfootball_master.db",
        base / "powerfootball.db",
        base / "FM23.csv"
    )

MASTER_DB_PATH, EAFC_DB_PATH, FM23_CSV_PATH = resolve_paths()

# =============================================================================
# PYRAMIDREGLER OCH BASLINJER FÖR GENERATORN
# =============================================================================
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

    # Övriga
    (r"eredivisie", "Nederländerna", 1, 0.65),
    (r"eerste divisie", "Nederländerna", 2, 0.44),
    (r"primeira liga", "Portugal", 1, 0.66),
    (r"liga portugal 2", "Portugal", 2, 0.45),
    (r"premiership$", "Skottland", 1, 0.58),
    (r"championship.*scotland", "Skottland", 2, 0.40)
]


class WaterfallPyramidPopulator:
    def __init__(self, master_path: Path, eafc_path: Path, fm23_path: Path):
        self.master_path = master_path
        self.eafc_path = eafc_path
        self.fm23_path = fm23_path

        print(f"Master Databas : {self.master_path.resolve()}")
        print(f"EA FC26 Källa  : {self.eafc_path.resolve()}")
        print(f"FM23 Källa     : {self.fm23_path.resolve()}\n")

        self.conn_master = sqlite3.connect(self.master_path)
        self.cur_master = self.conn_master.cursor()

        # 1. Ladda EA FC 26
        self.eafc_exact, self.eafc_pool, self.eafc_names = self._load_eafc_pool()

        # 2. Ladda FM23
        self.fm_exact, self.fm_pool, self.fm_names = self._load_fm23_pool()

    @staticmethod
    def normalize_name(name: str) -> str:
        if not isinstance(name, str):
            return ""
        n = "".join(c for c in unicodedata.normalize("NFD", name) if unicodedata.category(c) != "Mn")
        n = re.sub(r"[^\w\s]", " ", n.lower())
        return re.sub(r"\s+", " ", n).strip()

    def _load_eafc_pool(self):
        print("Läser in EA Sports FC 26-poolen från powerfootball.db...")
        exact_map = {}
        pool = []

        if not self.eafc_path.exists():
            print("  [Varning] powerfootball.db hittades inte.")
            return exact_map, pool, []

        conn = sqlite3.connect(self.eafc_path)
        cur = conn.cursor()
        query = """
            SELECT p.player_name, p.mass, p.top_speed, p.stamina_max,
                   a.vision, a.composure, a.aggression, a.close_control, 
                   a.reflexes, a.determination, a.work_rate
            FROM players p
            JOIN player_attributes a ON p.player_id = a.player_id
        """
        cur.execute(query)
        rows = cur.fetchall()

        for r in rows:
            norm = self.normalize_name(r[0])
            stats = {
                "mass": r[1], "top_speed": r[2], "stamina_max": r[3],
                "vision": r[4], "composure": r[5], "aggression": r[6],
                "close_control": r[7], "reflexes": r[8], "determination": r[9],
                "work_rate": r[10]
            }
            if norm not in exact_map:
                exact_map[norm] = stats
            pool.append((norm, stats))

        conn.close()
        names = [item[0] for item in pool]
        print(f"  -> Laddade {len(pool)} spelarprofiler från EA FC 26.\n")
        return exact_map, pool, names

    def _load_fm23_pool(self):
        print("Läser in Football Manager 2023-poolen från FM23.csv...")
        exact_map = {}
        pool = []

        if not self.fm23_path.exists():
            print("  [Varning] FM23.csv hittades inte.")
            return exact_map, pool, []

        df = pd.read_csv(self.fm23_path, low_memory=False)
        name_col = "Name" if "Name" in df.columns else df.columns[0]

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

            norm = self.normalize_name(name)
            stats = {
                "pace": get_stat("Pac"),
                "stamina": get_stat("Sta"),
                "vision": get_stat("Vis"),
                "composure": get_stat("Cmp"),
                "aggression": get_stat("Agg"),
                "close_control": get_stat("Tec"),
                "reflexes": get_stat("Ref"),
                "determination": get_stat("Det"),
                "work_rate": get_stat("Wor")
            }
            if norm not in exact_map:
                exact_map[norm] = stats
            pool.append((norm, stats))

        names = [item[0] for item in pool]
        print(f"  -> Laddade {len(pool)} spelarprofiler från FM23.\n")
        return exact_map, pool, names

    def generate_procedural(self, pos: str, baseline: float) -> Dict[str, float]:
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
        else:
            return {
                "mass": random.uniform(68.0, 80.0),
                "top_speed": 205.0 + sample(1.05) * 40.0,
                "stamina_max": 85.0 + sample(1.1) * 15.0,
                "vision": sample(1.15), "composure": sample(1.05), "aggression": sample(1.00),
                "close_control": sample(1.10), "reflexes": sample(0.60),
                "determination": sample(1.00), "work_rate": sample(1.15)
            }

    def match_league_rule(self, league_name: str) -> Tuple[str, int, float]:
        name_clean = league_name.lower().strip()
        for pattern, country, tier, baseline in PYRAMID_RULES:
            if re.search(pattern, name_clean):
                return country, tier, baseline
        return "Övriga", 3, 0.40

    def run(self):
        print("==========================================================")
        print("STARTAR VATTENFALLS-HYDRERING (EAFC -> FM23 -> GENERATOR)")
        print("==========================================================")

        self.cur_master.execute("SELECT league_id, name FROM leagues")
        all_leagues = self.cur_master.fetchall()

        total_eafc_hits = 0
        total_fm_hits = 0
        total_proc_hits = 0

        for l_id, l_name in all_leagues:
            country, tier, baseline = self.match_league_rule(l_name)

            # Hämta o-hydrerade spelare (de som fortfarande har standardvärden)
            self.cur_master.execute("""
                SELECT DISTINCT p.player_id, p.player_name, p.position_role
                FROM players p
                JOIN contracts c ON p.player_id = c.player_id
                JOIN teams t ON c.team_id = t.team_id
                JOIN seasons s ON c.season_id = s.season_id
                WHERE (s.league_id = ? OR t.league_id = ?)
                  AND (p.vision = 0.65 AND p.composure = 0.60)
            """, (l_id, l_id))
            unhydrated = self.cur_master.fetchall()

            if not unhydrated:
                continue

            print(f"[{country} Tier {tier}] {l_name}: Bearbetar {len(unhydrated)} spelare...")

            batch_updates = []
            eafc_count = 0
            fm_count = 0
            proc_count = 0

            for p_id, p_name, pos in unhydrated:
                p_norm = self.normalize_name(p_name)
                final_stats = None

                # -------------------------------------------------------------
                # 1. EA SPORTS FC 26 (PRIORITET 1)
                # -------------------------------------------------------------
                if p_norm in self.eafc_exact:
                    final_stats = self.eafc_exact[p_norm]
                    eafc_count += 1
                elif self.eafc_names:
                    match = process.extractOne(p_norm, self.eafc_names, scorer=fuzz.token_sort_ratio, score_cutoff=88)
                    if match:
                        _, score, idx = match
                        final_stats = self.eafc_pool[idx][1]
                        eafc_count += 1

                # -------------------------------------------------------------
                # 2. FOOTBALL MANAGER 2023 (PRIORITET 2 - FALLBACK)
                # -------------------------------------------------------------
                if not final_stats:
                    fm_cand = None
                    if p_norm in self.fm_exact:
                        fm_cand = self.fm_exact[p_norm]
                    elif self.fm_names:
                        match_fm = process.extractOne(p_norm, self.fm_names, scorer=fuzz.token_sort_ratio, score_cutoff=88)
                        if match_fm:
                            _, score, idx = match_fm
                            fm_cand = self.fm_pool[idx][1]

                    if fm_cand and fm_cand.get("vision") is not None:
                        final_stats = {
                            "mass": 75.0,
                            "top_speed": 205.0 + ((fm_cand.get("pace") or 0.5) * 40.0),
                            "stamina_max": 80.0 + ((fm_cand.get("stamina") or 0.5) * 20.0),
                            "vision": fm_cand.get("vision") or baseline,
                            "composure": fm_cand.get("composure") or baseline,
                            "aggression": fm_cand.get("aggression") or baseline,
                            "close_control": fm_cand.get("close_control") or baseline,
                            "reflexes": fm_cand.get("reflexes") or 0.50,
                            "determination": fm_cand.get("determination") or baseline,
                            "work_rate": fm_cand.get("work_rate") or baseline
                        }
                        fm_count += 1

                # -------------------------------------------------------------
                # 3. PROCEDURIELL GENERATOR (PRIORITET 3 - FALLBACK)
                # -------------------------------------------------------------
                if not final_stats:
                    final_stats = self.generate_procedural(pos, baseline)
                    proc_count += 1

                batch_updates.append((
                    final_stats["mass"], final_stats["top_speed"], final_stats["stamina_max"],
                    final_stats["vision"], final_stats["composure"], final_stats["aggression"],
                    final_stats["close_control"], final_stats["reflexes"], final_stats["determination"],
                    final_stats["work_rate"], p_id
                ))

            # Spara ändringarna till SQLite
            self.cur_master.executemany("""
                UPDATE players
                SET mass = ?, top_speed = ?, stamina_max = ?,
                    vision = ?, composure = ?, aggression = ?,
                    close_control = ?, reflexes = ?, determination = ?, work_rate = ?
                WHERE player_id = ?
            """, batch_updates)
            self.conn_master.commit()

            total_eafc_hits += eafc_count
            total_fm_hits += fm_count
            total_proc_hits += proc_count
            print(f"  -> Klart: {eafc_count} EA FC, {fm_count} FM23, {proc_count} genererade.\n")

        print("==========================================================")
        print("VATTENFALLS-HYDRERING SLUTFÖRD!")
        print(f"EA Sports FC 26 träffar : {total_eafc_hits} st")
        print(f"Football Manager träffar: {total_fm_hits} st")
        print(f"Proceduriellt genererade: {total_proc_hits} st")
        print("==========================================================")

    def close(self):
        self.conn_master.close()


if __name__ == "__main__":
    populator = WaterfallPyramidPopulator(MASTER_DB_PATH, EAFC_DB_PATH, FM23_CSV_PATH)
    populator.run()
    populator.close()