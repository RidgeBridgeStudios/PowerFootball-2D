#!/usr/bin/env python3
"""
generate_antigravity_context.py

Generates machine-readable and prompt-optimized architectural context
from powerfootball_master.db for Google Antigravity agent integration in Godot 4.7.
"""

import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, List

# =============================================================================
# CONFIGURATION & PATH RESOLUTION
# =============================================================================
def get_db_path() -> Path:
    cwd = Path.cwd()
    if (cwd / "powerfootball_master.db").exists():
        return cwd / "powerfootball_master.db"
    if (cwd.parent / "powerfootball_master.db").exists():
        return cwd.parent / "powerfootball_master.db"
    return Path(__file__).resolve().parent / "powerfootball_master.db"

DB_PATH = get_db_path()
OUTPUT_JSON_PATH = DB_PATH.parent / "antigravity_context.json"
OUTPUT_MD_PATH = DB_PATH.parent / "ANTIGRAVITY_CONTEXT.md"


class AntigravityContextGenerator:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        if not self.db_path.exists():
            raise FileNotFoundError(f"Database not found at: {self.db_path.resolve()}")
        self.conn = sqlite3.connect(self.db_path)
        self.cursor = self.conn.cursor()

    def inspect_tables(self) -> Dict[str, Any]:
        """Inspects all tables, columns, constraints, and record counts."""
        self.cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
        )
        table_names = [row[0] for row in self.cursor.fetchall()]

        schema_data = {}
        for table in table_names:
            # Columns metadata
            self.cursor.execute(f"PRAGMA table_info({table});")
            columns = []
            for col in self.cursor.fetchall():
                columns.append({
                    "cid": col[0],
                    "name": col[1],
                    "type": col[2],
                    "notnull": bool(col[3]),
                    "default_value": col[4],
                    "primary_key": bool(col[5])
                })

            # Foreign keys
            self.cursor.execute(f"PRAGMA foreign_key_list({table});")
            foreign_keys = []
            for fk in self.cursor.fetchall():
                foreign_keys.append({
                    "from": fk[3],
                    "target_table": fk[2],
                    "to": fk[4]
                })

            # Row count
            self.cursor.execute(f"SELECT COUNT(*) FROM {table};")
            row_count = self.cursor.fetchone()[0]

            schema_data[table] = {
                "row_count": row_count,
                "columns": columns,
                "foreign_keys": foreign_keys
            }

        return schema_data

    def get_game_mode_metrics(self) -> Dict[str, Any]:
        """Aggregates metrics for split game modes (men vs women) and competitions."""
        metrics = {}

        # Gender metrics across tables
        for table in ["leagues", "teams", "players"]:
            try:
                self.cursor.execute(f"SELECT gender, COUNT(*) FROM {table} GROUP BY gender;")
                metrics[f"{table}_gender_split"] = dict(self.cursor.fetchall())
            except sqlite3.OperationalError:
                metrics[f"{table}_gender_split"] = "Column 'gender' not present"

        # Competition types
        try:
            self.cursor.execute("SELECT competition_type, COUNT(*) FROM leagues GROUP BY competition_type;")
            metrics["competition_types"] = dict(self.cursor.fetchall())
        except sqlite3.OperationalError:
            metrics["competition_types"] = "Column 'competition_type' not present"

        return metrics

    def generate_json_manifest(self, schema: Dict[str, Any], metrics: Dict[str, Any]) -> None:
        """Saves a structured JSON file for programmatic ingestion."""
        payload = {
            "project_name": "PowerFootball-2D",
            "engine": "Godot 4.7 (GDScript 2.0 / GDExtension godot-sqlite)",
            "database_file": self.db_path.name,
            "architecture_pattern": "Repository / Data Access Object (DAO) via Singleton",
            "metrics": metrics,
            "schema": schema,
            "sqlite_to_gdscript_type_mapping": {
                "INTEGER": "int",
                "REAL": "float",
                "TEXT": "String",
                "BLOB": "PackedByteArray"
            }
        }

        with open(OUTPUT_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        print(f"JSON context generated: {OUTPUT_JSON_PATH.resolve()}")

    def generate_markdown_context(self, schema: Dict[str, Any], metrics: Dict[str, Any]) -> None:
        """Saves a readable markdown instruction document for Antigravity."""
        lines = [
            "# Project Context: PowerFootball-2D Database Integration",
            "",
            "## Engine & Runtime Target",
            "- **Engine:** Godot Engine 4.7 (GDScript 2.0)",
            "- **SQLite Driver:** `godot-sqlite` (GDExtension)",
            f"- **Database File:** `{self.db_path.name}`",
            "- **Storage Strategy:** Read-only template in `res://data/`, copied to `user://` on first launch for writable save games.",
            "",
            "## Active System Metrics",
            f"- **Competition Types:** {metrics.get('competition_types', {})}",
            f"- **Player Gender Breakdown:** {metrics.get('players_gender_split', {})}",
            f"- **Team Gender Breakdown:** {metrics.get('teams_gender_split', {})}",
            "",
            "## Database Schema & Table Volume",
            "| Table Name | Row Count | Primary Key | Key Foreign Keys |",
            "| :--- | :--- | :--- | :--- |"
        ]

        for tbl, data in schema.items():
            pk = ", ".join([c["name"] for c in data["columns"] if c["primary_key"]]) or "None"
            fks = ", ".join([f"{fk['from']} -> {fk['target_table']}.{fk['to']}" for fk in data["foreign_keys"]]) or "None"
            lines.append(f"| `{tbl}` | {data['row_count']:,} | `{pk}` | {fks} |")

        lines.extend([
            "",
            "## Architectural Requirements for Generated GDScript",
            "1. **Singleton Access (`DatabaseManager.gd`):** Must support global access via `DatabaseManager` autoload.",
            "2. **Game Mode Isolation:** Every query fetching leagues, teams, or players must filter by `gender = current_game_mode` (`'men'` or `'women'`).",
            "3. **Competition Routing:** Domestic leagues (`DOMESTIC_LEAGUE`) determine standings; cups and Champions League (`CONTINENTAL_CUP`) must query `tournament_participants`.",
            "4. **Performance:** Match engine attributes (`mass`, `top_speed`, `vision`, `composure`, `reflexes`, etc.) must be instantiated as typed `Resource` objects (`PlayerData.gd`) to eliminate dictionary lookup overhead during 60 FPS simulations.",
            "",
            "## Standard SQL Query Recipes",
            "### 1. Fetch Squad Roster for Match Simulation",
            "```sql",
            "SELECT p.player_id, p.player_name, p.position_role, p.nationality,",
            "       p.mass, p.top_speed, p.stamina_max, p.vision, p.composure,",
            "       p.aggression, p.close_control, p.reflexes, p.determination, p.work_rate,",
            "       c.jersey_number, c.position_name",
            "FROM players p",
            "JOIN contracts c ON p.player_id = c.player_id",
            "WHERE c.team_id = ? AND p.gender = ?;",
            "```",
            "",
            "### 2. Fetch Active Tournament Participants (Champions League / Cups)",
            "```sql",
            "SELECT t.team_id, t.name, tp.seed_status, tp.stage_reached",
            "FROM tournament_participants tp",
            "JOIN teams t ON tp.team_id = t.team_id",
            "WHERE tp.season_id = ? AND tp.competition_id = ?;",
            "```"
        ])

        with open(OUTPUT_MD_PATH, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print(f"Markdown context generated: {OUTPUT_MD_PATH.resolve()}")

    def close(self):
        self.conn.close()


if __name__ == "__main__":
    generator = AntigravityContextGenerator(DB_PATH)
    schema = generator.inspect_tables()
    metrics = generator.get_game_mode_metrics()
    generator.generate_json_manifest(schema, metrics)
    generator.generate_markdown_context(schema, metrics)
    generator.close()
    print("\n[SUCCESS] Antigravity context generation completed successfully.")