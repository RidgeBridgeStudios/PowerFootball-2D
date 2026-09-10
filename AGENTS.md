# AGENTS.md — Canonical Shared AI Agent Policy & Architecture Guide

**Canonical Single Source of Truth for all AI Agents (Claude Code, Google Antigravity, Gemini, Cursor, Copilot, DeepSeek, opencode, and Human Contributors).**

All agents working in the PowerFootball-2D repository must strictly adhere to the policies, architectural choke points, navigation protocols, and verification gates defined in this document.

---

<core_invariants>
## 1. Core Architecture & Invariants

All engine constraints, simulation layers, and critical file contracts are canonically defined across:
- **[docs/CORE_INVARIANTS.md](docs/CORE_INVARIANTS.md)** — Canonical engine lock, simulation stack, choke points, and physics/AI laws.
- **[docs/GRAPHIFY_LIFECYCLE.md](docs/GRAPHIFY_LIFECYCLE.md)** — Canonical Graphify lifecycle, git hooks, update mechanics, and enforcement matrix.
- **[docs/API_SURFACE.md](docs/API_SURFACE.md)** — Auto-generated public API surface map across all scripts, exports, signals, and methods.
- **[docs/ANTI_PATTERNS.md](docs/ANTI_PATTERNS.md)** — Curated anti-pattern and hallucination corpus for autonomous agent reasoning.
- **[docs/MATH_SOLVERS.md](docs/MATH_SOLVERS.md)** — Ground-truth mathematical solvers catalog with exact formulas, proofs, and GDScript reference code.
- **[docs/SYMBOLS.json](docs/SYMBOLS.json)** — Complete line-indexed symbol map across all classes, methods, properties, and signals.
- **[docs/DEPENDENCY_GRAPH.json](docs/DEPENDENCY_GRAPH.json)** — Static bidirectional dependency DAG and blast radius graph.
- **[POWERFOOTBALL_MASTER_VISION.md](POWERFOOTBALL_MASTER_VISION.md)** — Master design vision, 5-layer simulation stack, systems design, and North Star.
- **[docs/agent-errata/README.md](docs/agent-errata/README.md)** — Modular agent errata index and topic-specific failure mode pages.
- **[ROADMAP.md](ROADMAP.md)** — Tactical `[ ]`/`[x]` feature checklist across 5 development phases.
- **[docs/course_implementation_specification.md](docs/course_implementation_specification.md)** — Course-derived reference specification (READ-ONLY): FSMs, formulas, gotchas.

### Key Architectural Invariants
- **Engine Lock:** Godot 4.7-stable · GDScript 2.0 ONLY · Strict Typing on every variable, parameter, and return type.
- **Simulation Stack:** 5-layer upward event propagation model (Physics -> AI -> Social -> Club World -> Narrative). Every major feature touches at least two layers.
- **Spatial Cache Choke Point:** ALL spatial position reads route through `autoloads/MatchWorldModel.gd`. Calling `get_tree().get_nodes_in_group()` inside `_process`/`_physics_process` is FORBIDDEN.
- **Signal Bus Choke Point:** ALL inter-system events route through `autoloads/GameEvents.gd`. Never emit cross-system signals from individual components directly.
- **Match Lifecycle Choke Point:** `autoloads/GameManager.gd` is the single source of truth for match lifecycle, score, clock, and set-piece states.
- **Brain Contract Choke Point:** `PlayerBrain` writes ONLY to `player.movement_intent` (Vector2 direction) and `player.wants_sprint` (bool). Never directly modify `velocity`, `acceleration`, or `is_sprinting`.
- **Kinematic Execution Choke Point:** `HeavyPlayerController` executes kinematic integration, acceleration curves, and turning penalties. Direct velocity assignment is FORBIDDEN.
- **Collision Matrix Invariant:** `CharacterBody2D` masks Layer 1 (World) and Layer 2 (Players) ONLY. `CharacterBody2D` MUST NEVER mask Layer 3 (Ball). Ball interaction is handled via Area2D on Layer 4 sensing Layer 3.
- **Career State Ownership:** `CareerManager` owns the ONLY live `CareerSaveData`. The league (squads, staff, attributes) stays owned by `DataLoader` and is saved per slot via `DataLoader.save_league()`.
- **Career -> Match Bridge:** `PlayerFactory.apply()` is the single choke point where career morale/trust seeds `MoodSystem` and `TrustSystem`.
- **Boot Order (`project.godot`):**
  `MatchWorldModel` → `GameEvents` → `GameManager` → `MatchStatsTracker` → `MatchTelemetryLogger` → `DataLoader` → `RefereeLoader` → `ManagerLoader` → `StaffLoader` → `WorldEventLog` → `CareerManager` → `InputHelper`.
  *Constraint:* `WorldEventLog` and `CareerManager` must stay AFTER loaders (`DataLoader`, `ManagerLoader`, `StaffLoader`, `RefereeLoader`), and `WorldEventLog` before `CareerManager`.
- **Process Priority:**
  `MatchWorldModel` (-100) → `PlayerBrain` (0) → `HeavyPlayerController` (100).
- **Declarative Squad Config:** 22 players total (11 per team), spawned declaratively as children of `$Players` in `pitch/PitchScene.tscn`. Self-service index assignment in player `_ready()` using static counter reset via `MatchWorldModel.unregister_all()`.
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
| **Tier 1: Local** | Self-contained leaf files: UI styling/labels (`ui/ActionText.gd`, `ui/TouchlineBubble.gd`), standalone math/formatting helpers without contract changes, isolated comments, documentation. | Local file inspection; confirm no exported variables or public signatures are altered. | Fast Gate:<br>`py -3 tools/verify_gate.py --fast`<br>(0 errors required) |
| **Tier 2: Cross-Module** | Multi-file interactions within or between adjacent simulation layers: signal signatures in `autoloads/GameEvents.gd`, shared resources (`shared/PlayerData.gd`, `shared/TeamData.gd`, `shared/career/*`), role configurations (`shared/PlayerRoleConfig.gd`), or exported properties accessed across scenes. | Run dependency blast radius (`py -3 tools/dump_dep_graph.py --blast-radius <target>`) and query Graphify neighbors (`get_neighbors`). Check all call sites and signal receivers before editing. | Fast Gate + Targeted Linters:<br>`py -3 tools/verify_gate.py --fast`<br>+ relevant domain tests. |
| **Tier 3: Core Simulation** | Architectural choke points (`autoloads/MatchWorldModel.gd`, `entities/player/HeavyPlayerController.gd`, `entities/player/PlayerBrain.gd`, `entities/ball/Pseudo3DBall.gd`, `shared/CollisionLayers.gd`, `pitch/PitchScene.gd`, `autoloads/GameManager.gd`, `autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `shared/PlayerFactory.gd`), process priority, boot order, 22-player declarative layout, or 6-layer collision matrix. | Mandatory blast radius DAG (`tools/dump_dep_graph.py --blast-radius <target>`), Graphify dependency path trace, and explicit review of `docs/CORE_INVARIANTS.md` and `docs/ANTI_PATTERNS.md`. | Full Pre-Turn Battery:<br>`py -3 tools/verify_gate.py --full`<br>(all 10 static linters + fuzzers + 60s analytical sim + replay test). |
</change_impact_tiers>

<documentation_policy>
## 4. Conditional Documentation-Update Policy

To prevent documentation decay without generating unnecessary token churn, agents must update documentation strictly based on change triggers:

- **Public API / Signatures Changed:** If any public method, export variable, signal, or class interface in GDScript is added, modified, or deleted:
  - Regenerate public API map: `py -3 tools/dump_api.py` -> `docs/API_SURFACE.md`.
  - Regenerate symbol index: `py -3 tools/generate_symbols.py` -> `docs/SYMBOLS.json`.
- **Dependencies or Autoloads Changed:** If imports, autoload singletons in `project.godot`, or cross-file class references change:
  - Regenerate dependency DAG: `py -3 tools/dump_dep_graph.py` -> `docs/DEPENDENCY_GRAPH.json`.
- **Architectural Laws / Choke Points Changed:** If engine contracts, physics formulas, collision masks, or layer invariants are modified:
  - Update `docs/CORE_INVARIANTS.md` and synchronize corresponding rules in `.claude/rules/` and `.agents/rules/`.
- **Bugs, Edge Cases, or New Invariants Discovered:**
  - Consult topic-specific errata pages in `docs/agent-errata/` (e.g. `player-ai.md`, `physics-and-ball.md`, `set-pieces.md`) rather than loading full errata history.
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
- **No Object-to-String Comparisons:** Never compare an object instance (`current_state`, `player`, `ball`) to a StringName or String literal. Check if the class exposes a distinct string identifier (e.g., `current_state_name`).
- **Clean Early Returns:** When introducing an early `return`, inspect the remainder of the function and remove all orphaned code to prevent duplicate declaration parse errors.
- **Root Class Syntax:** If a root class used as a type annotation (e.g., `PlayerBrain`, `HeavyPlayerController`) produces cascade errors, inspect the root file's syntax first.
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

# Full pre-turn completion battery — 17 checks (linters + fuzzers + simulation + symbols + graphify):
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
py -3 tools/fuzz_solvers.py           # 100k kinematic and boundary fuzzing tests
py -3 tools/fuzz_formations.py        # 50k formation anchor property stress tests
py -3 tools/eval_simulation.py        # 60s headless simulation assertion harness
py -3 tools/replay_test.py            # Bit-exact deterministic replay test
py -3 tools/benchmark_math.py         # Math solvers latency benchmark
```

### Non-Destructive Validation Checklist
Before concluding any editing turn or proposing changes, all agents must complete this 5-step checklist:
1. **Format & Static Lint (Fast Gate):** Run `python tools/verify_gate.py --fast` (or `py -3 tools/verify_gate.py --fast`). All 10 linters must show 0 errors.
2. **Targeted Smoke Test:** Run the relevant domain check (`fuzz_solvers.py`, `fuzz_formations.py`, `eval_simulation.py --duration=10`, or `replay_test.py`).
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
| `/fuzz-formations` | `tools/fuzz_formations.py` | Run 50,000 property-based stress tests on formation anchors |
| `/replay-test` | `tools/replay_test.py` | Run deterministic simulation replay verification (0 bit-drift) |
| `/gen-symbols` | `tools/generate_symbols.py` | Regenerate `docs/SYMBOLS.json` line-indexed symbol map |
| `/lint-invariants` | `tools/lint_invariants.py` | Run domain AST invariant linter |
| `/eval-sim` | `tools/eval_simulation.py` | Run 60s headless simulation assertion harness |
| `/fuzz-solvers` | `tools/fuzz_solvers.py` | Run 100,000 property fuzzing iterations across mathematical solvers |
| `/formation-audit` | `tools/formation_ascii.py --all` | Render terminal ASCII tactical formation spacing diagrams |
| `/blast-radius` | `tools/dump_dep_graph.py --blast-radius` | Compute dependency DAG and blast radius for a target file |
| `/dump-dep-graph` | `tools/dump_dep_graph.py` | Regenerate `docs/DEPENDENCY_GRAPH.json` DAG |
| `/sync-rules` | `tools/sync_rules.py` | Promote discovered rules from `AGENTS_ERRATA.md` to `.claude/rules/` and `docs/CORE_INVARIANTS.md` |
| `/compact-errata` | `tools/compact_errata.py` | Promote rules and compact session state history to `docs/archive/` |
| `/rebuild-api` | `tools/dump_api.py` | Regenerate `docs/API_SURFACE.md` public API surface map |
| `/next-task` | `tools/next_task.py` | Query `ROADMAP.md` for next Phase 1 gameplay completeness item |
| `/layer-ctx` | `tools/layer_context.py [1-5]` | Extract targeted context for simulation layers 1-5 |
</tooling>

<simulation_layers>
## 9. Five-Layer Simulation Stack

<layer_1_physics>
### Layer 1 — Physics & Kinematics
- **Scope:** `entities/ball/`, `entities/player/HeavyPlayerController.gd`, `entities/player/states/`, `pitch/PitchBoundary.gd`, `pitch/PitchScene.gd`, `shared/CollisionLayers.gd`.
- **Invariants:** 6-layer collision matrix. `CharacterBody2D` never masks Layer 3 (Ball). Velocity integrated via `HeavyPlayerController` only. Proportional ball friction.
</layer_1_physics>

<layer_2_match_ai>
### Layer 2 — Match AI & Spatial Navigation
- **Scope:** `autoloads/MatchWorldModel.gd`, `entities/player/PlayerBrain.gd`, `entities/goalkeeper/`, `entities/manager/`, `entities/referee/`, `shared/PassUtilityScorer.gd`, `shared/FormationAnchorMath.gd`.
- **Invariants:** All spatial reads via `MatchWorldModel`. Decision updates on 15-frame stagger. Zero allocations in hot paths.
</layer_2_match_ai>

<layer_3_match_social>
### Layer 3 — Match Social & Dynamic Form
- **Scope:** `entities/player/MoodSystem.gd`, `entities/player/TrustSystem.gd`, `shared/PlayerRatingCalculator.gd`, `autoloads/MatchStatsTracker.gd`.
- **Invariants:** Confidence drift on goals/cards/slumps. Trust weighting on passing decisions. Neutral reset on match initialization.
</layer_3_match_social>

<layer_4_club_world>
### Layer 4 — Club World & Career Persistence
- **Scope:** `autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `autoloads/ManagerLoader.gd`, `autoloads/RefereeLoader.gd`, `autoloads/StaffLoader.gd`, `shared/TeamData.gd`, `shared/PlayerData.gd`, `shared/career/*`.
- **Invariants:** `CareerManager` owns only live `CareerSaveData`. Validated database integrity via `verify_db.py` and `validate_schemas.py`. Squad index is player identity; transfers repair lineups and states.
</layer_4_club_world>

<layer_5_narrative>
### Layer 5 — Narrative & Presentation
- **Scope:** `autoloads/WorldEventLog.gd`, `entities/manager/PressOffice.gd`, `ui/TouchlineBubble.gd`, `ui/ActionText.gd`, `ui/MatchStatsUI.gd`, `ui/HUD.gd`, `ui/manager_mode/*`.
- **Invariants:** Event log generation and UI presentation reacting strictly to `GameEvents`.
</layer_5_narrative>
</simulation_layers>

<shared_agent_memory>
## 10. Shared Agent Memory & Errata Synchronization

- **Topic-Scoped Errata:** Errata and historical failure modes are modularized under `docs/agent-errata/` (`player-ai.md`, `match-state.md`, `physics-and-ball.md`, `set-pieces.md`, `scene-and-node-paths.md`, `data-and-persistence.md`, `telemetry-and-stats.md`, `ui-and-signals.md`). Agents must read only the relevant topic page.
- **Cross-Agent Shared Memory:** Record novel failure modes, API misconceptions, runtime discoveries, and pending rule proposals in `AGENTS_ERRATA.md` using the structured YAML schema (`discovered_rules` or `session_state`).
- **Rule Promotion:** Promote validated errata to `.claude/rules/`, `.agents/rules/`, and `docs/CORE_INVARIANTS.md` via `/sync-rules` (`py -3 tools/sync_rules.py`) or `/compact-errata` (`py -3 tools/compact_errata.py`).
- **Atomic Work Units:** Work in cohesive units: one feature/fix = targeted file set + verification pass.
</shared_agent_memory>
