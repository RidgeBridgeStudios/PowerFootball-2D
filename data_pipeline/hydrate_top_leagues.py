#!/usr/bin/env python3
"""
hydrate_top_leagues.py

Reparerar automatiskt league_id-relationer i powerfootball_master.db och
berikar spelare i toppligorna med autentiska betyg från powerfootball.db.
"""

import re
import sqlite3
import unicodedata
from pathlib import Path
from typing import Dict, List, Tuple
from rapidfuzz import fuzz, process

# =============================================================================
# AUTOMATISK SÖKVÄGSHANTERING
# =============================================================================
def resolve_databases() -> Tuple[Path, Path]:
    """Lokaliserar databaserna oavsett varifrån terminalen startas."""
    cwd = Path.cwd()
    if (cwd.parent / "powerfootball_master.db").exists() and (cwd.parent / "powerfootball.db").exists():
        return cwd.parent / "powerfootball_master.db", cwd.parent / "powerfootball.db"
    if (cwd / "powerfootball_master.db").exists() and (cwd / "powerfootball.db").exists():
        return cwd / "powerfootball_master.db", cwd / "powerfootball.db"
    script_dir = Path(__file__).resolve().parent
    return script_dir / "powerfootball_master.db", script_dir / "powerfootball.db"

MASTER_DB_PATH, ATTRIBUTES_DB_PATH = resolve_databases()

# Specifika liga-ID:n för att träffa rätt tävlingar direkt
TARGET_LEAGUE_IDS = [
    8,    # Premier League (England)
    9,    # Championship (England)
    72,   # Eredivisie (Nederländerna)
    82,   # Bundesliga (Tyskland)
    301,  # Ligue 1 (Frankrike)
    384,  # Serie A (Italien)
    564,  # La Liga (Spanien)
    573   # Allsvenskan (Sverige)
]

class LeagueHydrator:
    def __init__(self, master_db: Path, attr_db: Path):
        self.master_db = master_db
        self.attr_db = attr_db
        
        print(f"Ansluter till Master DB: {self.master_db.resolve()}")
        print(f"Ansluter till Attribut DB: {self.attr_db.resolve()}\n")

        self.conn_master = sqlite3.connect(self.master_db)
        self.conn_attr = sqlite3.connect(self.attr_db)
        self.cur_master = self.conn_master.cursor()
        self.cur_attr = self.conn_attr.cursor()

    @staticmethod
    def normalize_name(name: str) -> str:
        """Tvättar namn för tillförlitlig fuzzy-matchning."""
        if not name:
            return ""
        n = "".join(c for c in unicodedata.normalize("NFD", name) if unicodedata.category(c) != "Mn")
        n = re.sub(r"[^\w\s]", " ", n.lower())
        return re.sub(r"\s+", " ", n).strip()

    def repair_team_leagues(self):
        """Kopplar ihop lag med rätt liga via säsongskontrakten om fältet är tomt."""
        print("Kontrollerar och reparerar tabellrelationer (teams.league_id)...")
        self.cur_master.execute("""
            UPDATE teams
            SET league_id = (
                SELECT s.league_id
                FROM contracts c
                JOIN seasons s ON c.season_id = s.season_id
                WHERE c.team_id = teams.team_id
                LIMIT 1
            )
            WHERE league_id IS NULL;
        """)
        self.conn_master.commit()
        print("Tabellrelationer verifierade och reparerade.\n")

    def load_enriched_attribute_pool(self) -> List[Dict]:
        """Läser in alla spelare med FM+FC-attribut från powerfootball.db."""
        print("Läser in attributpool från powerfootball.db...")
        query = """
            SELECT p.player_id, p.player_name, p.position_role, p.nationality,
                   p.mass, p.top_speed, p.stamina_max,
                   a.vision, a.composure, a.aggression, a.close_control, 
                   a.reflexes, a.determination, a.work_rate
            FROM players p
            JOIN player_attributes a ON p.player_id = a.player_id
        """
        self.cur_attr.execute(query)
        rows = self.cur_attr.fetchall()
        
        pool = []
        for r in rows:
            pool.append({
                "name_norm": self.normalize_name(r[1]),
                "raw_name": r[1],
                "position": r[2],
                "nationality": self.normalize_name(r[3]),
                "mass": r[4],
                "top_speed": r[5],
                "stamina_max": r[6],
                "vision": r[7],
                "composure": r[8],
                "aggression": r[9],
                "close_control": r[10],
                "reflexes": r[11],
                "determination": r[12],
                "work_rate": r[13]
            })
        print(f"Laddade {len(pool)} berikade profiler från FC26/FM23.\n")
        return pool

    def run(self):
        print("==========================================================")
        print("STARTAR ATTRIBUT-HYDRERING FÖR TOPPLIGOR")
        print("==========================================================")

        # 1. Säkerställ att relationerna är hela
        self.repair_team_leagues()

        # 2. Läs in attribut från förra databasen
        attribute_pool = self.load_enriched_attribute_pool()
        pool_names = [p["name_norm"] for p in attribute_pool]

        # 3. Hämta ligorna vi vill berika
        placeholders = ",".join(["?"] * len(TARGET_LEAGUE_IDS))
        self.cur_master.execute(f"""
            SELECT league_id, name FROM leagues 
            WHERE league_id IN ({placeholders})
        """, TARGET_LEAGUE_IDS)
        target_leagues = self.cur_master.fetchall()

        total_matched = 0
        total_squad_players = 0

        for league_id, league_name in target_leagues:
            print(f"--- Behandlar liga: {league_name} (ID: {league_id}) ---")
            
            # Hämta spelare via kontrakt och säsonger
            self.cur_master.execute("""
                SELECT DISTINCT p.player_id, p.player_name, t.name
                FROM players p
                JOIN contracts c ON p.player_id = c.player_id
                JOIN teams t ON c.team_id = t.team_id
                JOIN seasons s ON c.season_id = s.season_id
                WHERE s.league_id = ? OR t.league_id = ?
            """, (league_id, league_id))
            players_in_league = self.cur_master.fetchall()

            league_matches = 0
            for p_id, p_name, t_name in players_in_league:
                p_norm = self.normalize_name(p_name)
                if not p_norm:
                    continue

                # Fuzzy-sökning med token_sort_ratio
                match = process.extractOne(
                    p_norm,
                    pool_names,
                    scorer=fuzz.token_sort_ratio,
                    score_cutoff=88
                )

                if match:
                    _, score, match_idx = match
                    cand = attribute_pool[match_idx]

                    self.cur_master.execute("""
                        UPDATE players
                        SET mass = ?, top_speed = ?, stamina_max = ?,
                            vision = ?, composure = ?, aggression = ?,
                            close_control = ?, reflexes = ?, determination = ?, work_rate = ?
                        WHERE player_id = ?
                    """, (
                        cand["mass"], cand["top_speed"], cand["stamina_max"],
                        cand["vision"], cand["composure"], cand["aggression"],
                        cand["close_control"], cand["reflexes"], cand["determination"],
                        cand["work_rate"], p_id
                    ))
                    league_matches += 1

            self.conn_master.commit()
            count = len(players_in_league)
            pct = (league_matches / count * 100) if count > 0 else 0
            print(f"  -> Resultat: {league_matches}/{count} spelare uppdaterade ({pct:.1f}%)\n")
            
            total_matched += league_matches
            total_squad_players += count

        print("==========================================================")
        overall_pct = (total_matched / total_squad_players * 100) if total_squad_players > 0 else 0
        print(f"FÄRDIG! Totalt berikades {total_matched} av {total_squad_players} spelare ({overall_pct:.1f}%).")
        print("Toppligorna i powerfootball_master.db har nu autentiska betyg!")
        print("==========================================================")

    def close(self):
        self.conn_master.close()
        self.conn_attr.close()


if __name__ == "__main__":
    hydrator = LeagueHydrator(MASTER_DB_PATH, ATTRIBUTES_DB_PATH)
    hydrator.run()
    hydrator.close()