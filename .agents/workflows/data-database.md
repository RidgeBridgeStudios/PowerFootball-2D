---
name: data-database
description: Governs Layer 4 Club World game data (players, leagues, staff, referees), schema evolution, synthetic generation, and database verification gates.
---

# Workflow: data-database

Adaptive protocol for inspecting, modifying, generating, or validating Layer 4 game databases (`data/*.json`).

## Execution Protocol

1. **Context & Inspection Hygiene (Zero File Dumps):**
   - NEVER read `data/league.json`, `data/players.json`, `staff.json`, `managers.json`, or `referees.json` directly (large generated artifacts; >288 players).
   - Inspect active structures via `DataLoader` autoload (`autoloads/DataLoader.gd`) or targeted slices.
   - Do NOT dump `docs/json-schema.md` (410 lines). Query targeted sections via:
     `py -3 tools/semantic_search.py "<attribute_or_entity>"`

2. **Schema Invariants & Blast Radius (Pre-Edit):**
   - **Identity Invariant:** `player_key = team_index * 1000 + squad_index`. Ignore `player_id` in `docs/json-schema.md` (errata: no `PlayerData.player_id` exists; squad index is identity).
   - **State Ownership:** `DataLoader` owns league data; `CareerManager` owns live `CareerSaveData`.
   - Before proposing schema changes, compute consumer blast radius:
     `py -3 tools/dump_dep_graph.py --blast-radius autoloads/DataLoader.gd`

3. **Data Generation & Modification:**
   - NEVER hand-edit `data/*.json`.
   - Update generation logic in `tools/generate_db.py`, `tools/update_db_all.py`, or `tools/expand_database.py`.
   - Re-generate data files via:
     `py -3 tools/update_db_all.py || python tools/update_db_all.py || py -3 tools/update_db_all.py`
     or `py -3 tools/expand_database.py || python tools/expand_database.py || py -3 tools/expand_database.py`

4. **Schema & Database Validation:**
   - Validate schemas against strict bounds and report output:
     `py -3 tools/validate_schemas.py || python tools/validate_schemas.py || py -3 tools/validate_schemas.py`
   - Run standalone database integrity assertions:
     `py -3 tools/verify_db.py || python tools/verify_db.py || py -3 tools/verify_db.py`

5. **Verification Gate:**
   - Post-write / Fast Gate (includes step 9 `verify_db.py`):
     `py -3 tools/verify_gate.py --fast || python tools/verify_gate.py --fast || py -3 tools/verify_gate.py --fast`
   - Pre-turn / Full Battery (linters + fuzzers + simulation):
     `py -3 tools/verify_gate.py --full || python tools/verify_gate.py --full || py -3 tools/verify_gate.py --full`
