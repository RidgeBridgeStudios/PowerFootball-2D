#!/usr/bin/env python3
"""
separate_gender_modes.py

Partitionerar powerfootball_master.db i två isolerade spellägen (herr och dam).
Lägger till 'gender'-kolumner och propagerar könstillhörighet från ligor
ner till lag och kontrakterade spelare.
"""

import re
import sqlite3
from pathlib import Path

DB_PATH = Path("powerfootball_master.db")

# Mönster för att identifiera damtävlingar
WOMEN_PATTERNS = [
    r"women", r"frauen", r"féminine", r"damallsvenskan",
    r"feminin", r"femenina", r"w-league", r"nwsl", r"superettan dam"
]

class GenderModeSeparator:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        if not self.db_path.exists():
            raise FileNotFoundError(f"Hittade inte databasen: {self.db_path.resolve()}")
        self.conn = sqlite3.connect(self.db_path)
        self.cursor = self.conn.cursor()

    def run_migration(self):
        print("==========================================================")
        print("STARTAR PARTITIONERING AV SPELLÄGEN (HERR / DAM)")
        print("==========================================================")

        # 1. Lägg till gender-kolumner med index
        tables = ["leagues", "teams", "players"]
        for tbl in tables:
            try:
                self.cursor.execute(f"ALTER TABLE {tbl} ADD COLUMN gender TEXT DEFAULT 'men'")
                print(f"Lade till kolumnen 'gender' i {tbl}.")
            except sqlite3.OperationalError:
                pass
            self.cursor.execute(f"CREATE INDEX IF NOT EXISTS idx_{tbl}_gender ON {tbl}(gender)")

        self.conn.commit()

        # 2. Tagga damligor
        self.cursor.execute("SELECT league_id, name FROM leagues")
        leagues = self.cursor.fetchall()
        
        women_league_ids = []
        for l_id, l_name in leagues:
            clean_name = l_name.lower()
            if any(re.search(pat, clean_name) for pat in WOMEN_PATTERNS):
                women_league_ids.append(l_id)
                self.cursor.execute("UPDATE leagues SET gender = 'women' WHERE league_id = ?", (l_id,))

        self.conn.commit()
        print(f"\nIdentifierade {len(women_league_ids)} damtävlingar bland {len(leagues)} totala ligor.")

        # 3. Propagera till lag via ligatillhörighet och säsongskontrakt
        print("Uppdaterar klubbarnas könstillhörighet...")
        self.cursor.execute("""
            UPDATE teams
            SET gender = 'women'
            WHERE league_id IN (SELECT league_id FROM leagues WHERE gender = 'women')
               OR team_id IN (
                   SELECT DISTINCT c.team_id
                   FROM contracts c
                   JOIN seasons s ON c.season_id = s.season_id
                   JOIN leagues l ON s.league_id = l.league_id
                   WHERE l.gender = 'women'
               );
        """)
        self.conn.commit()

        # 4. Propagera till spelare via deras kontrakt
        print("Uppdaterar spelarnas könstillhörighet via aktiva kontrakt...")
        self.cursor.execute("""
            UPDATE players
            SET gender = 'women'
            WHERE player_id IN (
                SELECT DISTINCT c.player_id
                FROM contracts c
                JOIN teams t ON c.team_id = t.team_id
                WHERE t.gender = 'women'
            );
        """)
        self.conn.commit()

        # 5. Sammanställ statistik
        print("\n--- Resultat av partitioneringen ---")
        for tbl in ["leagues", "teams", "players"]:
            self.cursor.execute(f"SELECT gender, COUNT(*) FROM {tbl} GROUP BY gender")
            counts = dict(self.cursor.fetchall())
            print(f"  * {tbl:<10}: Herrar = {counts.get('men', 0):>6}, Damer = {counts.get('women', 0):>6}")

        self.conn.close()
        print("\n==========================================================")
        print("DATABASEN ÄR NU UPPDELAD I TVÅ SEPARATA SPELLÄGEN!")
        print("==========================================================")

if __name__ == "__main__":
    separator = GenderModeSeparator(DB_PATH)
    separator.run_migration()