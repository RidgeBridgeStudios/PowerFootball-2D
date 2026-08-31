# AGENTS.md

Onboarding and agent protocol for Google Antigravity, Gemini models, and autonomous agents (DeepSeek, opencode, Copilot).

<core_invariants>
## 1. Core Architecture & Invariants

All engine constraints, simulation layers, and critical file contracts are canonically defined in:
- **[docs/CORE_INVARIANTS.md](docs/CORE_INVARIANTS.md)**
- **[docs/API_SURFACE.md](docs/API_SURFACE.md)**
- **[docs/ANTI_PATTERNS.md](docs/ANTI_PATTERNS.md)**
- **[docs/MATH_SOLVERS.md](docs/MATH_SOLVERS.md)**
- **[docs/SYMBOLS.json](docs/SYMBOLS.json)**
- **[docs/DEPENDENCY_GRAPH.json](docs/DEPENDENCY_GRAPH.json)**

Key Highlights:
- **Engine Lock:** Godot 4.7-stable · GDScript 2.0 ONLY · Strict Typing on every variable, parameter, and return type.
- **Simulation Stack:** 5-layer upward event propagation model (Physics -> AI -> Social -> Club World -> Narrative). Every major feature touches at least two layers.
- **Choke Points:** All spatial reads via `autoloads/MatchWorldModel.gd`; all inter-system events via `autoloads/GameEvents.gd`; `PlayerBrain` writes ONLY `movement_intent` and `wants_sprint`.
- **Reference Spec:** Consult `docs/course_implementation_specification.md` (READ-ONLY) before implementing course-related systems.
</core_invariants>

<strict_type_discipline>
- Never compare an object instance (`current_state`, `player`, `ball`) to a StringName or String literal. Check if the class exposes a distinct string identifier (e.g., `current_state_name`).
- When introducing an early `return`, inspect the remainder of the function and remove all orphaned code to prevent duplicate declaration parse errors.
- If a root class used as a type annotation (e.g., `PlayerBrain`, `HeavyPlayerController`) produces cascade errors, inspect the root file's syntax first.
- In candidate ranking or sorting loops, always use `distance_squared_to()` to avoid costly square root instructions.
</strict_type_discipline>

<autonomous_discipline>
- Pre-Edit: Execute `python3 tools/dump_dep_graph.py --blast-radius <file>` before editing core classes.
- Post-Write: Every file write automatically executes `python3 tools/verify_gate.py --fast`. Resolve any failure immediately.
- Pre-Turn-Complete: Turns are gated on `python3 tools/verify_gate.py --full`. Do not conclude turns with unresolved diagnostics.
</autonomous_discipline>

<verification>
## 2. Verification & Static Analysis

After every `.gd` file write, execute static analysis immediately:
```bash
python3 tools/verify_gate.py --fast || python tools/verify_gate.py --fast
```
**Strict Requirement:** Do not proceed or conclude turns until the checker output shows `0 errors`.

### Unified Verification Gates
```bash
# Fast post-write check (<150ms):
python3 tools/verify_gate.py --fast

# Full pre-turn completion battery:
python3 tools/verify_gate.py --full
```

### Standalone Linters
```bash
python3 tools/gdcheck.py
python3 tools/lint_invariants.py
python3 tools/lint_scope.py
python3 tools/lint_type_comparisons.py
python3 tools/lint_stringnames.py
python3 tools/lint_shadowing.py
python3 tools/lint_allocations.py
python3 tools/tscn_linter.py
python3 tools/verify_db.py
```

### Simulation & Property Testing
```bash
python3 tools/fuzz_solvers.py
python3 tools/fuzz_formations.py
python3 tools/eval_simulation.py --duration=60
python3 tools/replay_test.py
python3 tools/benchmark_math.py
```

### Autoload Handling Contract
`gdcheck.py` reads `[autoload]` from `project.godot` and treats every autoload name as a known type. Never add `class_name` to an autoload script.
</verification>

<tooling>
## 3. Developer Tooling & Slash Commands

| Command | Action | Description |
|---|---|---|
| `/verify-all` | `tools/verify_gate.py --full` | Complete verification suite (linters, fuzzers, simulations, indexing) |
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
| `/blast-radius` | `tools/dump_dep_graph.py --blast-radius` | Compute dependency DAG and blast radius |
| `/dump-dep-graph` | `tools/dump_dep_graph.py` | Regenerate `docs/DEPENDENCY_GRAPH.json` DAG |
| `/sync-rules` | `tools/sync_rules.py` | Promote discovered rules to `.claude/rules/` & `docs/CORE_INVARIANTS.md` |
| `/compact-errata` | `tools/compact_errata.py` | Promote rules and compact session state history to `docs/archive/` |
| `/rebuild-api` | `tools/dump_api.py` | Regenerate `docs/API_SURFACE.md` public API surface map |
| `/next-task` | `tools/next_task.py` | Query `ROADMAP.md` for next Phase 1 gameplay completeness item |
| `/layer-ctx` | `tools/layer_context.py [1-5]` | Extract targeted context for simulation layers 1-5 |
</tooling>

<layer_1_physics>
- **Scope:** `entities/ball/`, `entities/player/HeavyPlayerController.gd`, `entities/player/states/`, `pitch/PitchBoundary.gd`, `pitch/PitchScene.gd`, `shared/CollisionLayers.gd`.
- **Invariants:** 6-layer collision matrix. `CharacterBody2D` never masks Layer 3 (Ball). Velocity integrated via `HeavyPlayerController` only.
</layer_1_physics>

<layer_2_match_ai>
- **Scope:** `autoloads/MatchWorldModel.gd`, `entities/player/PlayerBrain.gd`, `entities/goalkeeper/`, `entities/manager/`, `entities/referee/`, `shared/PassUtilityScorer.gd`, `shared/FormationAnchorMath.gd`.
- **Invariants:** All spatial reads via `MatchWorldModel`. Decision updates on 15-frame stagger. Zero allocations in hot paths.
</layer_2_match_ai>

<layer_3_match_social>
- **Scope:** `entities/player/MoodSystem.gd`, `entities/player/TrustSystem.gd`.
- **Invariants:** Confidence drift on goals/cards/slumps. Trust weighting on passing decisions.
</layer_3_match_social>

<layer_4_club_world>
- **Scope:** `autoloads/DataLoader.gd`, `autoloads/ManagerLoader.gd`, `autoloads/RefereeLoader.gd`, `shared/TeamData.gd`, `shared/PlayerData.gd`.
- **Invariants:** Validated database integrity via `verify_db.py` and `validate_schemas.py`.
</layer_4_club_world>

<layer_5_narrative>
- **Scope:** `entities/manager/PressOffice.gd`, `ui/TouchlineBubble.gd`, `ui/ActionText.gd`, `ui/MatchStatsUI.gd`, `ui/HUD.gd`.
- **Invariants:** Event log generation and UI presentation reacting to `GameEvents`.
</layer_5_narrative>

<gemini_context_protocol>
## 4. Gemini Context Protocol & Antigravity Autonomy

### Large Context Window & Context Caching
- **Cached Architecture Prefix:** `POWERFOOTBALL_MASTER_VISION.md`, `docs/CORE_INVARIANTS.md`, `docs/API_SURFACE.md`, `AGENTS.md`, and `llms.txt` reside in the context prefix.
- **Holistic Cross-Layer Awareness:** Gemini's 1M+ token context window enables reasoning across multiple simulation layers simultaneously without lossy compaction.
- **Self-Healing Iteration:** When `.antigravity/hooks.json` intercepts a verification failure, review the `verify_gate.py` diagnostic, locate the file and line number, and resolve type/syntax/contract errors immediately.

### Atomic Feature Discipline
- **One Feature = One File Set + One Verification Pass:** Execute changes in modular, cohesive units.
- **Strict Verification Gate:** Always verify with `python3 tools/verify_gate.py --fast` after file edits and `python3 tools/verify_gate.py --full` prior to completing any turn.
- **Errata Synchronization:** Record novel failure modes, API misconceptions, and runtime discoveries into `AGENTS_ERRATA.md` using the structured machine-readable format. Promote to `.claude/rules/` and `docs/CORE_INVARIANTS.md` via `/sync-rules` or `/compact-errata`.
</gemini_context_protocol>
