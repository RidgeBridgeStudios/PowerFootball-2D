#!/usr/bin/env python3
"""
refactor_competitions.py

Klassificerar ligor och cuper i powerfootball_master.db.
Skapar tournament_participants för dynamiskt kvalificerande turneringar
(Champions League, inhemska cuper) och säkrar att klubbar enbart har
inhemska seriesystem som sin permanenta league_id.
"""

import re
import sqlite3
from pathlib import Path
from typing import Tuple

DB_PATH = Path("powerfootball_master.db")

# Mönster för att skilja cuper och internationella turneringar från ligor
CUP_PATTERNS = [
    r"cup", r"pokal", r"coppa", r"copa", r"coupe", r"trophy",
    r"taça", r"knvb", r"play-off", r"supercup", r"shield"
]

CONTINENTAL_PATTERNS = [
    r"champions league", r"europa league", r"conference league",
    r"copa libertadores", r"copa sudamericana", r"caf champions",
    r"afc champions", r"uefa", r"fifa", r"concacaf"
]

class CompetitionRefactorer:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        if not self.db_path.exists():
            raise FileNotFoundError(f"Databas saknas: {self.db_path.resolve()}")
        self.conn = sqlite3.connect(self.db_path)
        self.cursor = self.conn.cursor()

    def classify_competition(self, name: str, sub_type: str) -> str:
        """Klassificerar tävlingstyp baserat på namn och Sportmonks sub_type."""
        n = name.lower()
        
        # Kontinentala / Internationella
        if any(re.search(p, n) for p in CONTINENTAL_PATTERNS) or sub_type == "international":
            return "CONTINENTAL_CUP"
            
        # Inhemska cuper och slutspel
        if any(re.search(p, n) for p in CUP_PATTERNS) or sub_type == "cup":
            return "DOMESTIC_CUP"
            
        # Standard: Inhemskt seriesystem
        return "DOMESTIC_LEAGUE"

    def run_refactoring(self):
        print("==========================================================")
        print("STARTAR OMSTRUKTURERING AV TÄVLINGAR & CUPER")
        print("==========================================================")

        # 1. Lägg till competition_type i leagues om den saknas
        try:
            self.cursor.execute("ALTER TABLE leagues ADD COLUMN competition_type TEXT DEFAULT 'DOMESTIC_LEAGUE'")
            print("Lade till kolumnen 'competition_type' i leagues.")
        except sqlite3.OperationalError:
            pass

        # 2. Skapa tabellen för dynamiska turneringsdeltagare
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS tournament_participants (
                participant_id INTEGER PRIMARY KEY AUTOINCREMENT,
                season_id INTEGER NOT NULL,
                competition_id INTEGER NOT NULL,
                team_id INTEGER NOT NULL,
                seed_status TEXT DEFAULT 'QUALIFIED',
                stage_reached TEXT DEFAULT 'GROUP_STAGE',
                FOREIGN KEY (season_id) REFERENCES seasons(season_id),
                FOREIGN KEY (competition_id) REFERENCES leagues(league_id),
                FOREIGN KEY (team_id) REFERENCES teams(team_id),
                UNIQUE(season_id, competition_id, team_id)
            )
        """)
        self.cursor.execute("CREATE INDEX IF NOT EXISTS idx_tournament_lookup ON tournament_participants(season_id, competition_id);")
        print("Tabellen 'tournament_participants' är initierad.")

        # 3. Klassificera samtliga tävlingar i databasen
        self.cursor.execute("SELECT league_id, name, sub_type FROM leagues")
        competitions = self.cursor.fetchall()

        type_counts = {"DOMESTIC_LEAGUE": 0, "DOMESTIC_CUP": 0, "CONTINENTAL_CUP": 0}
        cup_ids = set()

        for c_id, name, sub_type in competitions:
            c_type = self.classify_competition(name, sub_type or "")
            type_counts[c_type] += 1
            if c_type in ["DOMESTIC_CUP", "CONTINENTAL_CUP"]:
                cup_ids.add(c_id)

            self.cursor.execute("UPDATE leagues SET competition_type = ? WHERE league_id = ?", (c_type, c_id))

        self.conn.commit()
        print(f"\nKlassificeringsresultat:")
        print(f"  * Inhemska ligor   : {type_counts['DOMESTIC_LEAGUE']} st")
        print(f"  * Inhemska cuper   : {type_counts['DOMESTIC_CUP']} st")
        print(f"  * Kontinentala     : {type_counts['CONTINENTAL_CUP']} st\n")

        # 4. Registrera nuvarande cup-deltagare i tournament_participants
        print("Registrerar säsongsdeltagande för cuper och internationella turneringar...")
        self.cursor.execute("""
            SELECT DISTINCT c.season_id, s.league_id, c.team_id
            FROM contracts c
            JOIN seasons s ON c.season_id = s.season_id
            JOIN leagues l ON s.league_id = l.league_id
            WHERE l.competition_type IN ('DOMESTIC_CUP', 'CONTINENTAL_CUP')
        """)
        cup_entries = self.cursor.fetchall()

        self.cursor.executemany("""
            INSERT OR IGNORE INTO tournament_participants (season_id, competition_id, team_id)
            VALUES (?, ?, ?)
        """, cup_entries)
        self.conn.commit()
        print(f"Lade till {len(cup_entries)} säsongsposter i 'tournament_participants'.")

        # 5. Rätta teams.league_id så att den enbart pekar på riktiga ligor
        print("Rensar felaktiga cup-kopplingar från teams.league_id...")
        self.cursor.execute("""
            UPDATE teams
            SET league_id = (
                SELECT s.league_id
                FROM contracts c
                JOIN seasons s ON c.season_id = s.season_id
                JOIN leagues l ON s.league_id = l.league_id
                WHERE c.team_id = teams.team_id
                  AND l.competition_type = 'DOMESTIC_LEAGUE'
                LIMIT 1
            )
            WHERE league_id IN (
                SELECT league_id FROM leagues WHERE competition_type != 'DOMESTIC_LEAGUE'
            ) OR league_id IS NULL;
        """)
        self.conn.commit()
        print("Klubbarnas ordinarie ligatillhörighet har renodlats.\n")

        print("==========================================================")
        print("DATABASEN ÄR NU ANPASSAD FÖR DYNAMISKA TURNERINGAR!")
        print("==========================================================")

    def close(self):
        self.conn.close()

if __name__ == "__main__":
    refactorer = CompetitionRefactorer(DB_PATH)
    refactorer.run_refactoring()
    refactorer.close()