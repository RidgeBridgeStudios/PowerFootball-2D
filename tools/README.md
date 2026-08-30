# tools/ — Development Utilities & Agent Verification Harness

Static analysis, invariant AST linting, headless simulation assertion, dependency DAG analysis, database verification, public API mapping, and agent automation tools.

## Developer Tooling & Slash Commands

| Command | Action | Description |
|---|---|---|
| `/verify-all` | `tools/gdcheck.py && tools/lint_invariants.py && tools/verify_db.py` | Complete GDScript, invariant & database verification |
| `/lint-invariants` | `tools/lint_invariants.py` | Run domain AST invariant linter |
| `/eval-sim` | `tools/eval_simulation.py` | Run 60s headless simulation assertion harness |
| `/blast-radius` | `tools/dump_dep_graph.py --blast-radius` | Compute dependency DAG and blast radius |
| `/dump-dep-graph` | `tools/dump_dep_graph.py` | Regenerate `docs/DEPENDENCY_GRAPH.json` DAG |
| `/sync-rules` | `tools/sync_rules.py` | Promote discovered rules to `.claude/rules/` & `docs/CORE_INVARIANTS.md` |
| `/compact-errata` | `tools/compact_errata.py` | Promote rules and compact session state history to `docs/archive/` |
| `/rebuild-api` | `tools/dump_api.py` | Regenerate `docs/API_SURFACE.md` public API surface map |
| `/next-task` | `tools/next_task.py` | Query `ROADMAP.md` for next Phase 1 gameplay completeness item |
| `/layer-ctx` | `tools/layer_context.py [1-5]` | Extract targeted context for simulation layers 1–5 |

---

## 1. lint_invariants.py

**Purpose:** Domain-specific AST Invariant Linter enforcing architectural separation, zero allocations in hot paths, collision layer isolation, and choke-point compliance.

**Enforces:**
- **Brain Mutation Guard:** Asserts `PlayerBrain.gd` and `entities/player/states/*.gd` never write to `player.velocity`, `player.global_position`, `player.base_acceleration`, or invoke `move_and_slide()`.
- **Hot-Path Zero-Allocation Watchdog:** Asserts `score_pass`, `calculate_intercept_point`, `_physics_process`, and `get_dynamic_anchor_position` contain 0 heap allocations (`.new()`, Array literals `[]`, Dictionary literals `{}`).
- **Collision Layer Matrix Guard:** Asserts no `CharacterBody2D` enables Layer 3 (Ball) in `collision_mask`.
- **Choke-Point Bypass Guard:** Asserts AI decision loops route spatial queries through `MatchWorldModel.gd` instead of scanning scene trees.

**Usage:**
```bash
python tools/lint_invariants.py
python tools/lint_invariants.py --xml
```

---

## 2. eval_simulation.py

**Purpose:** Headless Simulation Assertion & Telemetry Evaluation Harness. Runs a 60-second headless match simulation across 22 autonomous AI players.

**Verifies:**
- `nan_inf_count == 0` (zero NaN/infinite floating-point numbers in position/velocity vectors)
- `boundary_escape_count == 0` (zero ball escapes beyond pitch boundary rect)
- `ai_cadence_violations == 0` (every player brain evaluates on exact 15-frame stagger)
- `anchor_variance` is computed and within valid bounds

**Usage:**
```bash
python tools/eval_simulation.py --duration=60 --output-json=eval_report.json
```

---

## 3. dump_dep_graph.py

**Purpose:** Static Dependency DAG & Blast Radius Analyzer. Maps all inheritance, `preload()`, symbol references, signal declarations, `.emit()` calls, and `.connect()` bindings across all 76+ `.gd` files into `docs/DEPENDENCY_GRAPH.json`.

**Usage:**
```bash
python tools/dump_dep_graph.py
python tools/dump_dep_graph.py --blast-radius entities/ball/Pseudo3DBall.gd
```

---

## 4. gdcheck.py

**Purpose:** Static GDScript 2.0 consistency checker. Enforces strict typing and Godot 4.7 API compliance without requiring a Godot binary.

**Usage:**
```bash
python tools/gdcheck.py                    # Check all 76+ .gd files
python tools/gdcheck.py entities/player/   # Check specific directory
```

---

## 5. verify_db.py

**Purpose:** Verifies integrity and relational constraints of JSON databases (`league.json`, `managers.json`, `referees.json`).

**Usage:**
```bash
python tools/verify_db.py
```

---

## 6. generate_db.py

**Purpose:** Generates or repopulates procedural default databases for teams, players, managers, and referees.

---

## 7. dump_api.py

**Purpose:** Scans all `.gd` scripts and exports a comprehensive public API surface markdown map to `docs/API_SURFACE.md`.

**Usage:**
```bash
python tools/dump_api.py
```

---

## 8. next_task.py

**Purpose:** Queries `ROADMAP.md` for the next unchecked Phase 1 gameplay completeness task and outputs relevant file context paths.

**Usage:**
```bash
python tools/next_task.py
```

---

## 9. layer_context.py

**Purpose:** Extracts targeted file sets and code snippets for simulation layers 1–5 (Layer 1: Physics, Layer 2: Match AI, Layer 3: Social, Layer 4: Club World, Layer 5: Narrative/UI).

**Usage:**
```bash
python tools/layer_context.py 2   # Context for Layer 2 Match AI
```

---

## 10. sync_rules.py & compact_errata.py

**Purpose:** Promotes discovered rules from `AGENTS_ERRATA.md` to `.claude/rules/` and `docs/CORE_INVARIANTS.md`, archiving old session logs to `docs/archive/errata_history.md`.

---

## 11. hook_gdcheck.py

**Purpose:** Diagnostic hook runner formatted with XML diagnostic tags for autonomous IDE / agent harnesses. Runs both `gdcheck.py` and `lint_invariants.py`.
