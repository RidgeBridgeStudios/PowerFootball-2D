# AGENTS.md — Canonical Shared AI Agent Policy & Architecture Guide

**Canonical Single Source of Truth for all AI Agents (Claude Code, Google Antigravity, Gemini, Cursor, Copilot, DeepSeek, opencode, and Human Contributors).**

All agents working in the PowerFootball-2D repository must strictly adhere to the policies, architectural choke points, navigation protocols, and verification gates defined in this document.

---

<core_invariants>
## 1. Core Architecture & Invariants

All engine constraints, simulation layers, and critical file contracts are canonically defined across:
- **[docs/CORE_INVARIANTS.md](docs/CORE_INVARIANTS.md)** — Canonical engine lock, simulation stack, choke points, and layer laws.
- **[docs/GRAPHIFY_LIFECYCLE.md](docs/GRAPHIFY_LIFECYCLE.md)** — Canonical Graphify lifecycle, git hooks, update mechanics, and enforcement matrix.
- **[docs/API_SURFACE.md](docs/API_SURFACE.md)** — Auto-generated public API surface map across all scripts, exports, signals, and methods.
- **[docs/ANTI_PATTERNS.md](docs/ANTI_PATTERNS.md)** — Curated anti-pattern and hallucination corpus for autonomous agent reasoning.
- **[docs/MATH_SOLVERS.md](docs/MATH_SOLVERS.md)** — Ground-truth mathematical solvers catalog with exact formulas, proofs, and GDScript reference code.
- **[docs/SYMBOLS.json](docs/SYMBOLS.json)** — Complete line-indexed symbol map across all classes, methods, properties, and signals.
- **[docs/DEPENDENCY_GRAPH.json](docs/DEPENDENCY_GRAPH.json)** — Static bidirectional dependency DAG and blast radius graph.
- **[POWERFOOTBALL_MASTER_VISION.md](POWERFOOTBALL_MASTER_VISION.md)** — Master design vision, systems design, and North Star.
- **[docs/agent-errata/README.md](docs/agent-errata/README.md)** — Modular agent errata index and topic-specific failure mode pages.
- **[ROADMAP.md](ROADMAP.md)** — Tactical `[ ]`/`[x]` feature checklist across 5 development phases.
- **[docs/course_implementation_specification.md](docs/course_implementation_specification.md)** — Course-derived reference specification (READ-ONLY): FSMs, formulas, gotchas.

### Key Architectural Invariants
- **Engine Lock:** Godot 4.7-stable · GDScript 2.0 ONLY · Strict Typing on every variable, parameter, and return type.
- **Simulation Stack:** 3-layer model — Career World → Quick-Sim Match → Narrative & Presentation. Career state feeds fixtures down into the statistical match resolver; resolved results propagate back up into career state and stats; presentation reacts through `GameEvents`. Every major feature touches at least two layers.
- **Signal Bus Choke Point:** ALL inter-system events route through `autoloads/GameEvents.gd` (11 signals: `formation_changed`, `lineup_changed`, and the career signals `career_started`, `career_day_advanced`, `career_advance_halted`, `career_inbox_changed`, `career_match_ready`, `career_result_recorded`, `career_season_ended`, `career_manager_sacked`, `world_event_logged`). Never emit cross-system signals from individual components directly.
- **Career State Ownership:** `CareerManager` owns the ONLY live `CareerSaveData`. The league (squads, staff, attributes) stays owned by `DataLoader` and is saved per slot via `DataLoader.save_league()`.
- **Quick-Sim Publishing Choke Point:** `QuickSimEngine.apply_to_match_stats_tracker()` is the single place a simulated result is pushed into `GameManager` + `MatchStatsTracker` and accumulated onto `PlayerData`. No other code may publish a match outcome.
- **Career Match-Day Flow:** `ui/manager_mode/ManagerModeRoot.gd::_on_continue_pressed()` calls `CareerManager.simulate_next_fixture()`, which runs `QuickSimEngine` and folds the result into table/finances/morale/board confidence/cups. The career UI never leaves `ManagerModeRoot` to play a match.
- **Boot Order (`project.godot`):**
  `GameEvents` → `GameManager` → `MatchStatsTracker` → `DataLoader` → `RefereeLoader` → `ManagerLoader` → `StaffLoader` → `WorldEventLog` → `CareerManager`.
  *Constraint:* `GameEvents` boots first; `WorldEventLog` and `CareerManager` must stay AFTER the four loaders (`DataLoader`, `RefereeLoader`, `ManagerLoader`, `StaffLoader`), and `WorldEventLog` before `CareerManager`. `tools/gdcheck.py` enforces this.
- **Retired Real-Time Layer:** The former 22-player physics match engine (ball/player/goalkeeper/referee entities, `pitch/`, the real-time match HUD, and the match-time autoloads) is archived under `legacy/` behind `legacy/.gdignore` — not deleted, but excluded from Godot import and from every verification tool. Live code must not reference it: matches have no player control, ball physics, or per-frame AI.
</core_invariants>

<graphify_navigation>
## 2. Graphify-First Navigation Protocol

This repository maintains an active Graphify knowledge graph (`graphify-out/graph.json`) providing structural dependency analysis, god nodes, community clusters, and cross-file relationships. Full lifecycle & hooks specification: **[docs/GRAPHIFY_LIFECYCLE.md](docs/GRAPHIFY_LIFECYCLE.md)**.

### Navigation Hierarchy
1. **Query Knowledge Graph First:** Before browsing files or running broad text searches, query Graphify:
   - CLI: `graphify query "<question>"`, `graphify path "<A>" "<B>"`, `graphify explain "<concept>"`.
     *(Or run via py -3: `py -3 -m graphify query ...`)*
   - MCP: Use `query_graph`, `shortest_path`, `get_node`, `get_neighbors`, `god_nodes`.
2. **Mandatory Pre-Edit Blast Radius (Tier 2 & Tier 3):**
   - Run dependency blast radius: `py -3 tools/dump_dep_graph.py --blast-radius <target>`.
   - Query Graphify neighbors/path (`get_neighbors` or `graphify explain "<target>"`) to map dependent modules across simulation layers before editing code.
3. **Consult Wiki/Report:** If `graphify-out/wiki/index.md` exists, consult it for conceptual domain maps. Read `graphify-out/GRAPH_REPORT.md` for high-level architecture overviews.
4. **Targeted Inspection:** Open source files with targeted line ranges (`tools/codebase_slice.py` or `view_file` on specific line slices) ONLY AFTER Graphify has localized the relevant symbols or choke points.
5. **Graph Maintenance:** After modifying GDScript or contract files, run `graphify update .` (executed automatically during `tools/verify_gate.py --full` Step 17) to keep the topology synchronized with zero LLM token cost.
6. **Reflection Loop:** Save high-value navigation paths using `graphify save-result --outcome useful`.

> [!NOTE]
> **Scope Clarification:** Graphify is NOT queried for every conversational prompt. Conversational chit-chat, simple formatting tasks, or localized edits from already-loaded context do not invoke Graphify. It is required for architectural discovery, cross-module relationship analysis, and pre-edit blast radius checks.

### Prohibited Navigation Anti-Patterns
- **NO Blind Ripgrep/Grep:** Do not run recursive grep across entire directories (`grep -r ...`) without a scoped target path.
- **NO Directory Orientation Dumps:** Do not `cat` or read all files in a folder (`autoloads/*.gd`, `shared/*.gd`) to "orient" yourself.
</graphify_navigation>

<change_impact_tiers>
## 3. Change-Impact Tiers

Every code modification in this repository falls into one of three distinct impact tiers. Agents must follow the pre-edit analysis and post-write verification required for that tier:

| Tier | Scope & Affected Files | Pre-Edit Requirement | Verification Gate |
|---|---|---|---|
| **Tier 1: Local** | Self-contained leaf files: UI styling/labels (`ui/manager_mode/CareerTheme.gd`, `shared/career/CareerThemePalette.gd`), standalone math/formatting helpers without contract changes, isolated comments, documentation. | Local file inspection; confirm no exported variables or public signatures are altered. | Fast Gate:<br>`py -3 tools/verify_gate.py --fast`<br>(0 errors required) |
| **Tier 2: Cross-Module** | Multi-file interactions within or between adjacent simulation layers: signal signatures in `autoloads/GameEvents.gd`, shared resources (`shared/PlayerData.gd`, `shared/TeamData.gd`, `shared/career/*`), role configurations (`shared/PlayerRoleConfig.gd`), or exported properties accessed across scenes. | Run dependency blast radius (`py -3 tools/dump_dep_graph.py --blast-radius <target>`) and query Graphify neighbors (`get_neighbors`). Check all call sites and signal receivers before editing. | Fast Gate + Targeted Linters:<br>`py -3 tools/verify_gate.py --fast`<br>+ relevant domain tests. |
| **Tier 3: Core Simulation** | Architectural choke points (`autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `autoloads/GameManager.gd`, `autoloads/GameEvents.gd`, `autoloads/MatchStatsTracker.gd`, `shared/QuickSimEngine.gd`, `shared/career/*`, `shared/TeamManagementData.gd`), boot order, signal-bus contracts, career-state ownership, quick-sim publishing, or career match-day flow. | Mandatory blast radius DAG (`tools/dump_dep_graph.py --blast-radius <target>`), Graphify dependency path trace, and explicit review of `docs/CORE_INVARIANTS.md` and `docs/ANTI_PATTERNS.md`. | Full Pre-Turn Battery:<br>`py -3 tools/verify_gate.py --full`<br>(all 10 static linters + quick-sim/solver harnesses + index regeneration). |
</change_impact_tiers>

<ponytail_gating>
## 3.5. Reuse & Complexity Gating (Ponytail)

Before writing new code or standing up new infrastructure (a new MCP server, a new autoload, a new data store), climb the reuse ladder in [.claude/rules/ponytail.md](.claude/rules/ponytail.md) (mirrored at `.agents/rules/ponytail.md`) — applies to every agent listed at the top of this document, including DeepSeek harnesses. In short: YAGNI-gate against `ROADMAP.md`, reuse `CareerManager`/`GameEvents`/`QuickSimEngine`/`AGENTS_ERRATA.md` before inventing parallel systems, and never add a tool/package/MCP-server reference to a config file without first confirming it is actually installed in this repo.
</ponytail_gating>

<football_domain_intelligence>
## 3.6. Football Domain Intelligence (`football-expert` MCP server)

A local, offline `football-expert` MCP server (`tools/football_mcp.py`, SQLite knowledge base at `.agents/football_domain.db`, rebuilt via `scripts/build_football_kb.py`) exposes `verify_kinematics`, `audit_tactical_compactness`, `query_ifab_rule`, `audit_action_transition`, and `diagnose_tactical_deviation`. Full usage guidance — including when to call it and when not to — is in [.claude/rules/football-domain.md](.claude/rules/football-domain.md) (mirrored at `.agents/rules/football-domain.md`). Its numeric ranges are tuning-plausibility heuristics compiled from public sports-science sources and the IFAB Laws, not hard physical constants — verify against the actual code before changing tuning values based on its output.
</football_domain_intelligence>

<documentation_policy>
## 4. Conditional Documentation-Update Policy

To prevent documentation decay without generating unnecessary token churn, agents must update documentation strictly based on change triggers:

- **Public API / Signatures Changed:** If any public method, export variable, signal, or class interface in GDScript is added, modified, or deleted:
  - Regenerate public API map: `py -3 tools/dump_api.py` -> `docs/API_SURFACE.md`.
  - Regenerate symbol index: `py -3 tools/generate_symbols.py` -> `docs/SYMBOLS.json`.
- **Dependencies or Autoloads Changed:** If imports, autoload singletons in `project.godot`, or cross-file class references change:
  - Regenerate dependency DAG: `py -3 tools/dump_dep_graph.py` -> `docs/DEPENDENCY_GRAPH.json`.
- **Architectural Laws / Choke Points Changed:** If engine contracts, the simulation-layer model, choke points, or layer invariants are modified:
  - Update `docs/CORE_INVARIANTS.md` and synchronize corresponding rules in `.claude/rules/` and `.agents/rules/`.
- **Bugs, Edge Cases, or New Invariants Discovered:**
  - Consult topic-specific errata pages in `docs/agent-errata/` (e.g. `match-state.md`, `data-and-persistence.md`, `ui-and-signals.md`) rather than loading full errata history.
  - Record new findings in `AGENTS_ERRATA.md` following the structured YAML schema (`discovered_rules` or `session_state`).
  - Run `/sync-rules` (`py -3 tools/sync_rules.py`) or `/compact-errata` (`py -3 tools/compact_errata.py`) to promote pending rules.
- **Roadmap Milestones Achieved:**
  - Mark completed tasks with `[x]` in `ROADMAP.md`.
- **Internal / Non-Interface Changes:**
  - If a change is an internal refactoring or bug fix that leaves public signatures, dependencies, and invariants unchanged, **DO NOT regenerate or modify documentation** (avoids token waste and noisy diffs).
</documentation_policy>

<strict_type_discipline>
## 5. Strict Type Discipline

- **Explicit Typing Required:** Every variable declaration, function parameter, and function return type must be explicitly typed.
- **No Object-to-String Comparisons:** Never compare an object instance (`current_phase`, `player`, `career`) to a StringName or String literal. Check if the class exposes a distinct string identifier (e.g., `current_state_name`).
- **No `self` in Lambda Closures:** In GDScript 2.0, `self` is a special keyword and cannot be captured inside an anonymous lambda closure (`func(): ...`). Assign `self` to an outer local variable (`var host: Control = self`) before the lambda, or use `Callable.bind()`.
- **Callable Invocation Syntax:** Never invoke a `Callable` variable directly (`my_callable(...)`). Always use `my_callable.call(...)` or `.call_deferred(...)`.
- **No Pythonisms:** Never use Python syntax (`None`, `True`, `False`, `def`, `len()`, `isinstance()`, `import`). Use GDScript 2.0 equivalents (`null`, `true`, `false`, `func`, `.size()`, `is`, `preload`).
- **Clean Early Returns:** When introducing an early `return`, inspect the remainder of the function and remove all orphaned code to prevent duplicate declaration parse errors.
- **Root Class Syntax:** If a root class used as a type annotation (e.g., `QuickSimEngine`, `CareerManager`) produces cascade errors, inspect the root file's syntax first.
- **Fast Distance Calculations:** In candidate ranking or sorting loops, always use `distance_squared_to()` to avoid costly square root instructions.
</strict_type_discipline>

<autonomous_discipline>
## 6. Autonomous Agent Verification Discipline

- **Pre-Edit:** For Tier 2 and Tier 3 tasks, execute `py -3 tools/dump_dep_graph.py --blast-radius <file>` before modifying shared classes.
- **Post-Write:** Every `.gd`, `.tscn`, or `.json` write automatically triggers static analysis:
  ```bash
  python3 tools/verify_gate.py --fast || python tools/verify_gate.py --fast || py -3 tools/verify_gate.py --fast
  ```
  **Strict Requirement:** Resolve any diagnostic failure immediately before proceeding to the next edit.
- **Pre-Turn-Complete:** Turns are gated on the full verification battery:
  ```bash
  python3 tools/verify_gate.py --full || python tools/verify_gate.py --full || py -3 tools/verify_gate.py --full
  ```
  Do not conclude turns with unresolved diagnostics.
</autonomous_discipline>

<verification>
## 7. Verification & Static Analysis

Static checking with `tools/gdcheck.py` alone is **NOT sufficient** — `gdcheck.py` treats autoloads as opaque types and cannot detect calls to non-existent methods on autoload singletons. `tools/lint_xref.py` (included in `tools/verify_gate.py`) validates qualified member access and `res://` path existence.

### Unified Verification Gates
```bash
# Fast post-write gate (<150ms) — 10 static linters:
py -3 tools/verify_gate.py --fast

# Full pre-turn completion battery — 10 linters + sim harnesses + fuzzers + index regeneration + graphify:
py -3 tools/verify_gate.py --full
```

### Standalone Linters
```bash
py -3 tools/gdcheck.py                # Type safety and syntax
py -3 tools/lint_invariants.py        # Layer separation and choke point contracts
py -3 tools/lint_scope.py             # Duplicate variable declarations and dead code
py -3 tools/lint_type_comparisons.py  # Object vs String/StringName comparisons
py -3 tools/lint_stringnames.py       # &'string_name' literal enforcement
py -3 tools/lint_shadowing.py         # Member variable and autoload shadowing
py -3 tools/lint_allocations.py       # Zero hot-path allocations and distance_squared_to
py -3 tools/lint_xref.py              # Qualified member access and res:// paths
py -3 tools/tscn_linter.py            # Scene tree integrity and collision masks
py -3 tools/verify_db.py              # JSON database schema validation
```

### Simulation & Property Testing
```bash
godot --headless tests/TestRunner.tscn # Headless regression test runner (P1-P4 architectural suite)
py -3 tools/test_quick_sim.py         # CURRENT GATE: validates shared/QuickSimEngine.gd statistical resolution
py -3 tools/replay_test.py            # Bit-exact deterministic replay test
py -3 tools/fuzz_solvers.py           # Mathematical solver fuzzing (shared/UtilityMath.gd)
py -3 tools/benchmark_math.py         # Math solvers latency benchmark

# Legacy real-time match engine — retirement candidates, NOT current gates:
py -3 tools/eval_simulation.py        # 60s headless assertion harness for the archived match engine
py -3 tools/fuzz_formations.py        # Formation-anchor stress tests for the archived match engine
```

> [!NOTE]
> `tools/eval_simulation.py`, `tools/fuzz_formations.py`, `tools/fuzz_utility_scorer.py`, `tools/formation_ascii.py`, `tools/dump_match_frames.py`, and `tools/spatial_grid_bench.py` describe the archived real-time engine and are candidates for retirement. `tools/test_quick_sim.py` is the current quick-sim validation gate.

### Non-Destructive Validation Checklist
Before concluding any editing turn or proposing changes, all agents must complete this 5-step checklist:
1. **Format & Static Lint (Fast Gate):** Run `python tools/verify_gate.py --fast` (or `py -3 tools/verify_gate.py --fast`). All 10 linters must show 0 errors.
2. **Targeted Smoke Test:** Run the relevant domain check (`tools/test_quick_sim.py` for the quick-sim engine, `tools/fuzz_solvers.py` for shared math, or `tools/replay_test.py`).
3. **Diff Review & Invariant Audit:** Check `git diff` against strict typing, zero allocations, no object-to-string comparisons, and architectural contracts.
4. **Graphify Refresh:** Synchronize graph topology via `graphify update .` or pre-turn gate `py -3 tools/verify_gate.py --full` (Step 17).
5. **Concise Final Evidence:** Report linters passed, execution duration, and zero invariant violations.

### Autoload Handling Contract
`gdcheck.py` reads `[autoload]` from `project.godot` and treats every autoload name as a known type. Never add `class_name` to an autoload script.
</verification>

<tooling>
## 8. Developer Tooling & Slash Commands

| Command | Action | Description |
|---|---|---|
| `/verify-all` | `tools/verify_gate.py --full` | Complete verification suite (linters, fuzzers, simulations, indexing, graphify) |
| `/slice` | `tools/codebase_slice.py` | Extract targeted class methods, enums, or headers with line numbers |
| `/search` | `tools/semantic_search.py` | Query BM25 local keyword index across specs, rules, and GDScript docstrings |
| `/benchmark` | `tools/benchmark_math.py` | Run mathematical solvers micro-benchmark suite |
| `/fuzz-formations` | `tools/fuzz_formations.py` | Run 50,000 property-based stress tests on formation anchors (archived real-time engine — retirement candidate) |
| `/replay-test` | `tools/replay_test.py` | Run deterministic simulation replay verification (0 bit-drift) |
| `/gen-symbols` | `tools/generate_symbols.py` | Regenerate `docs/SYMBOLS.json` line-indexed symbol map |
| `/lint-invariants` | `tools/lint_invariants.py` | Run domain AST invariant linter |
| `/eval-sim` | `tools/eval_simulation.py` | Run 60s headless simulation assertion harness (archived real-time engine — retirement candidate) |
| `/fuzz-solvers` | `tools/fuzz_solvers.py` | Run 100,000 property fuzzing iterations across mathematical solvers |
| `/formation-audit` | `tools/formation_ascii.py --all` | Render terminal ASCII tactical formation spacing diagrams (archived real-time engine — retirement candidate) |
| `/blast-radius` | `tools/dump_dep_graph.py --blast-radius` | Compute dependency DAG and blast radius for a target file |
| `/dump-dep-graph` | `tools/dump_dep_graph.py` | Regenerate `docs/DEPENDENCY_GRAPH.json` DAG |
| `/sync-rules` | `tools/sync_rules.py` | Promote discovered rules from `AGENTS_ERRATA.md` to `.claude/rules/` and `docs/CORE_INVARIANTS.md` |
| `/compact-errata` | `tools/compact_errata.py` | Promote rules and compact session state history to `docs/archive/` |
| `/rebuild-api` | `tools/dump_api.py` | Regenerate `docs/API_SURFACE.md` public API surface map |
| `/next-task` | `tools/next_task.py` | Query `ROADMAP.md` for next Phase 1 gameplay completeness item |
| `/layer-ctx` | `tools/layer_context.py` | Extract targeted context for the 3 simulation layers (tool still carries the legacy 1–5 alias taxonomy) |
</tooling>

<simulation_layers>
## 9. Three-Layer Simulation Stack

<layer_1_career_world>
### Layer 1 — Career World
- **Scope:** `autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `autoloads/ManagerLoader.gd`, `autoloads/RefereeLoader.gd`, `autoloads/StaffLoader.gd`, `shared/career/*`, `shared/TeamData.gd`, `shared/PlayerData.gd`, `shared/LeagueData.gd`, `shared/ManagerData.gd`, `shared/RefereeData.gd`, `shared/StaffData.gd`, `shared/TeamManagementData.gd`, `shared/NationDatabase.gd`, `shared/CareerProgressionEngine.gd`.
- **Invariants:** `CareerManager` owns the ONLY live `CareerSaveData`; the league stays owned by `DataLoader` and is saved per slot via `DataLoader.save_league()`. Database integrity is validated via `verify_db.py`. Squad index is player identity; transfers repair lineups and states.
</layer_1_career_world>

<layer_2_quicksim_match>
### Layer 2 — Quick-Sim Match
- **Scope:** `shared/QuickSimEngine.gd`, `shared/PlayerRatingCalculator.gd`, `shared/UtilityMath.gd`, `autoloads/MatchStatsTracker.gd`.
- **Invariants:** Matches are resolved entirely by statistical simulation — no player control, real-time frames, ball physics, or per-frame AI. `QuickSimEngine.apply_to_match_stats_tracker()` is the single publish point into `GameManager` + `MatchStatsTracker` and onto `PlayerData`. `MatchStatsTracker` is a passive stats container (`reset()`, `stop_possession_sampling()` no-op, `get_player_events()`, `compute_all_ratings()`, `get_stats()`, `get_advanced_stats()`).
</layer_2_quicksim_match>

<layer_3_narrative>
### Layer 3 — Narrative & Presentation
- **Scope:** `autoloads/WorldEventLog.gd`, `entities/manager/PressOffice.gd`, `ui/manager_mode/*`, `ui/MainMenu.gd`, `ui/OptionsMenu.gd`, `ui/MatchStatsUI.gd`, `ui/QuickSimModal.gd`.
- **Invariants:** Event log generation and UI presentation react strictly to `GameEvents`. The career UI never leaves `ui/manager_mode/ManagerModeRoot.gd` to play a match.
</layer_3_narrative>
</simulation_layers>

<shared_agent_memory>
## 10. Shared Agent Memory & Errata Synchronization

- **Topic-Scoped Errata:** Errata and historical failure modes are modularized under `docs/agent-errata/`. **Start with `architecture-pivot.md`** — it documents the manager-only pivot, the `legacy/` archive layout, the 3-layer stack and the traps the pivot left behind. Then read only the relevant topic page. Note that `player-ai.md`, `physics-and-ball.md`, `set-pieces.md`, `match-state.md`, `telemetry-and-stats.md` and `ui-and-signals.md` are marked **historical**: they record findings about the archived real-time match layer and must not be applied to current code.
- **Cross-Agent Shared Memory:** Record novel failure modes, API misconceptions, runtime discoveries, and pending rule proposals in `AGENTS_ERRATA.md` using the structured YAML schema (`discovered_rules` or `session_state`).
- **Rule Promotion:** Promote validated errata to `.claude/rules/`, `.agents/rules/`, and `docs/CORE_INVARIANTS.md` via `/sync-rules` (`py -3 tools/sync_rules.py`) or `/compact-errata` (`py -3 tools/compact_errata.py`).
- **Atomic Work Units:** Work in cohesive units: one feature/fix = targeted file set + verification pass.
</shared_agent_memory>
