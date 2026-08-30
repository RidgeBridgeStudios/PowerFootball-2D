# tools/ — Development Utilities & Agent Harness

Static analysis, database verification, public API mapping, and agent automation tools.

## Developer Tooling & Slash Commands

| Command | Action | Description |
|---|---|---|
| `/verify-all` | `tools/gdcheck.py && tools/verify_db.py` | Complete GDScript & database verification |
| `/sync-rules` | `tools/sync_rules.py` | Promote discovered rules to `.claude/rules/` & `docs/CORE_INVARIANTS.md` |
| `/compact-errata` | `tools/compact_errata.py` | Promote rules and compact session state history to `docs/archive/` |
| `/rebuild-api` | `tools/dump_api.py` | Regenerate `docs/API_SURFACE.md` public API surface map |
| `/next-task` | `tools/next_task.py` | Query `ROADMAP.md` for next Phase 1 gameplay completeness item |
| `/layer-ctx` | `tools/layer_context.py [1-5]` | Extract targeted context for simulation layers 1–5 |

---

## 1. gdcheck.py

**Purpose:** Static GDScript 2.0 consistency checker. Enforces strict typing and Godot 4.7 API compliance without requiring a Godot binary.

**Catches:**
- Undeclared members (accessing fields/methods that don't exist)
- Unknown types (referencing undefined classes)
- Unbalanced brackets and mixed indentation
- Godot 3 deprecated APIs (`yield`, `KinematicBody2D`, `File.new()`, etc.)
- Autoload types declared in `project.godot`

**Usage:**
```bash
python tools/gdcheck.py                    # Check all 76+ .gd files
python tools/gdcheck.py entities/player/   # Check specific directory
```

---

## 2. verify_db.py

**Purpose:** Verifies integrity and relational constraints of JSON databases (`league.json`, `managers.json`, `referees.json`).

**Checks:**
- 8 teams with 144 players (11 starters + 7 bench per team)
- 10 managers with valid formation mappings and trait bitmasks
- 8 referees with personality spectrums and career statistics

**Usage:**
```bash
python tools/verify_db.py
```

---

## 3. generate_db.py

**Purpose:** Generates or repopulates procedural default databases for teams, players, managers, and referees.

---

## 4. dump_api.py

**Purpose:** Scans all `.gd` scripts and exports a comprehensive public API surface markdown map to `docs/API_SURFACE.md`.

**Usage:**
```bash
python tools/dump_api.py
```

---

## 5. next_task.py

**Purpose:** Queries `ROADMAP.md` for the next unchecked Phase 1 gameplay completeness task and outputs relevant file context paths.

**Usage:**
```bash
python tools/next_task.py
```

---

## 6. layer_context.py

**Purpose:** Extracts targeted file sets and code snippets for simulation layers 1–5 (Layer 1: Physics, Layer 2: Match AI, Layer 3: Social, Layer 4: Club World, Layer 5: Narrative/UI).

**Usage:**
```bash
python tools/layer_context.py 2   # Context for Layer 2 Match AI
```

---

## 7. sync_rules.py & compact_errata.py

**Purpose:** Promotes discovered rules from `AGENTS_ERRATA.md` to `.claude/rules/` and `docs/CORE_INVARIANTS.md`, archiving old session logs to `docs/archive/errata_history.md`.

---

## 8. hook_gdcheck.py

**Purpose:** Diagnostic hook runner formatted with XML diagnostic tags for autonomous IDE / agent harnesses.

