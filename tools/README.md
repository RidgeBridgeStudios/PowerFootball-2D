# tools/ — Development Utilities & Agent Verification Harness

Static analysis, invariant AST linting, scene graph verification, headless simulation assertion, property fuzzing, spatial grid benchmarks, dependency DAG analysis, database verification, public API mapping, MCP/LSP bridges, and worktree automation tools.

## Developer Tooling & Slash Commands

| Command | Action | Description |
|---|---|---|
| `/verify-all` | `tools/verify_gate.py --full` | Complete 17-step verification suite (linters, fuzzers, sim, symbols, graphify) |
| `/lint-invariants` | `tools/lint_invariants.py` | Run domain AST invariant linter |
| `/eval-sim` | `tools/eval_simulation.py` | Run 60s headless simulation assertion harness |
| `/fuzz-solvers` | `tools/fuzz_solvers.py` | Run 100,000 property fuzzing iterations across mathematical solvers |
| `/formation-audit` | `tools/formation_ascii.py --all` | Render terminal ASCII tactical formation spacing diagrams |
| `/blast-radius` | `tools/dump_dep_graph.py --blast-radius <file>` | Compute dependency DAG and blast radius |
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
- **Choke-Point Bypass Guard:** Asserts AI decision loops route spatial queries through `MatchWorldModel.gd` instead of scanning scene trees or chaining `get_parent().get_parent()`.

**Usage:**
```bash
py -3 tools/lint_invariants.py
py -3 tools/lint_invariants.py --xml
```

---

## 2. tscn_linter.py

**Purpose:** TSCN Scene Graph Invariant Linter. Parses all `.tscn` scene files in the repository to assert resource integrity, valid parent hierarchies, and collision mask contracts.

**Usage:**
```bash
py -3 tools/tscn_linter.py
py -3 tools/tscn_linter.py --xml
```

---

## 3. validate_schemas.py

**Purpose:** Strict JSON Schema & Invariant Validator for club databases (`data/league.json`, `data/managers.json`, `data/referees.json`). Validates squad counts (16-22), 11 starting XI indices, GK at slot 0, trait bitmasks, and physical/tactical attribute bounds.

**Usage:**
```bash
py -3 tools/validate_schemas.py
```

---

## 4. fuzz_solvers.py

**Purpose:** Property-Based Mathematical Solvers & Kinematic Fuzz Tester. Runs 100,000 randomized velocity, angle, and deceleration vectors against `calculate_intercept_point()`, `is_lane_blocked()`, `closest_point_on_segment()`, `distance_squared_to_segment()`, `quadratic_decay()`, and `sigmoid()`.

**Usage:**
```bash
py -3 tools/fuzz_solvers.py --iterations=100000 --seed=42
```

---

## 5. spatial_grid_bench.py

**Purpose:** 22-Entity Spatial Query & Grid Cell Latency Benchmark. Measures spatial query latencies across grid cell sizes (64px, 128px, 256px, 512px) against a brute-force linear array search.

**Usage:**
```bash
py -3 tools/spatial_grid_bench.py --queries=50000
```

---

## 6. eval_simulation.py

**Purpose:** Headless Simulation Assertion & Telemetry Evaluation Harness. Runs a 60-second headless match simulation across 22 autonomous AI players.

**Verifies:**
- `nan_inf_count == 0` (zero NaN/infinite floating-point numbers in position/velocity vectors)
- `boundary_escape_count == 0` (zero ball escapes beyond pitch boundary rect)
- `ai_cadence_violations == 0` (every player brain evaluates on exact 15-frame stagger)
- `anchor_variance` is computed and within valid bounds

**Usage:**
```bash
py -3 tools/eval_simulation.py --duration=60 --output-json=eval_report.json
```

---

## 7. dump_match_frames.py & formation_ascii.py

**Purpose:** Visual and terminal tactical diagramming tools.
- `dump_match_frames.py`: Exports top-down SVG frames showing player coordinates, velocities, and passing corridors for Gemini multimodal evaluation.
- `formation_ascii.py`: Renders terminal ASCII pitch diagrams illustrating 11-player tactical spacing across `IN_POSSESSION`, `OUT_OF_POSSESSION`, and `TRANSITION` phases.

**Usage:**
```bash
py -3 tools/dump_match_frames.py --frames=5 --output-dir=match_frames
py -3 tools/formation_ascii.py --formation=4-3-3 --all
```

---

## 8. dump_dep_graph.py

**Purpose:** Static Dependency DAG & Blast Radius Analyzer. Maps all inheritance, `preload()`, symbol references, signal declarations, `.emit()` calls, and `.connect()` bindings across all 76+ `.gd` files into `docs/DEPENDENCY_GRAPH.json`.

**Usage:**
```bash
py -3 tools/dump_dep_graph.py
py -3 tools/dump_dep_graph.py --blast-radius entities/player/PlayerBrain.gd
```

---

## 9. dump_api.py

**Purpose:** Scans all `.gd` scripts and exports a comprehensive public API surface markdown map to `docs/API_SURFACE.md`.

**Usage:**
```bash
py -3 tools/dump_api.py
```

---

## 10. layer_context.py

**Purpose:** Extracts targeted file sets and code snippets for simulation layers 1–5 (Layer 1: Physics, Layer 2: Match AI, Layer 3: Social, Layer 4: Club World, Layer 5: Narrative/UI).

**Usage:**
```bash
py -3 tools/layer_context.py 2   # Context for Layer 2 Match AI
```

---

## 11. mcp_server.py & lsp_client.py

**Purpose:** Protocol bridge services:
- `mcp_server.py`: Standard stdio Model Context Protocol (MCP) server exposing tools: `get_layer_invariants`, `inspect_scene_tree`, `query_spatial_cache`, `run_property_test`.
- `lsp_client.py`: Godot Language Server Protocol client connecting to `tcp://127.0.0.1:6005` with local offline static diagnostic fallback.

**Usage:**
```bash
py -3 tools/mcp_server.py
py -3 tools/lsp_client.py --check
```

---

## 12. worktree_manager.py

**Purpose:** Automated git worktree isolation manager for feature development and verification sandboxing.

**Usage:**
```bash
py -3 tools/worktree_manager.py list
py -3 tools/worktree_manager.py create feature/aerial-contest
py -3 tools/worktree_manager.py verify feature/aerial-contest
py -3 tools/worktree_manager.py merge feature/aerial-contest
py -3 tools/worktree_manager.py cleanup feature/aerial-contest
```

---

## 13. sync_rules.py & compact_errata.py

**Purpose:** Promotes discovered rules from `AGENTS_ERRATA.md` to `.claude/rules/` and `docs/CORE_INVARIANTS.md`, archiving old session logs to `docs/archive/errata_history.md`.

---

## 14. hook_gdcheck.py

**Purpose:** Unified lifecycle verification runner for IDE / agent hooks executing `gdcheck.py`, `lint_invariants.py`, `tscn_linter.py`, and `validate_schemas.py` with structured XML reporting.
