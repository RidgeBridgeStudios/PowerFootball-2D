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
- **Simulation Stack:** 5-layer upward event propagation model (Physics → AI → Social → Club World → Narrative). Every major feature touches at least two layers.
- **Choke Points:** All spatial reads via `MatchWorldModel.gd`; all inter-system events via `GameEvents.gd`; `PlayerBrain` writes ONLY `movement_intent` and `wants_sprint`.
- **Reference Spec:** Consult `docs/course_implementation_specification.md` (READ-ONLY) before implementing course-related systems.
</core_invariants>

<verification>
## 2. Verification & Static Analysis

After every `.gd` file write, execute static analysis immediately:
```bash
python3 tools/gdcheck.py || python tools/gdcheck.py || py -3 tools/gdcheck.py
```
**Strict Requirement:** Do not proceed or conclude turns until the checker output shows `0 errors`.

### Invariant & Architecture AST Verification
```bash
python3 tools/lint_invariants.py || python tools/lint_invariants.py || py -3 tools/lint_invariants.py
```

### StringName Literal Verification
```bash
python3 tools/lint_stringnames.py || python tools/lint_stringnames.py || py -3 tools/lint_stringnames.py
```

### Variable & Autoload Shadowing Linter
```bash
python3 tools/lint_shadowing.py || python tools/lint_shadowing.py || py -3 tools/lint_shadowing.py
```

### Allocation & Distance-Sorting Linter
```bash
python3 tools/lint_allocations.py || python tools/lint_allocations.py || py -3 tools/lint_allocations.py
```

### Signal Race Condition Linter
```bash
python3 tools/lint_signal_races.py || python tools/lint_signal_races.py || py -3 tools/lint_signal_races.py
```

### Process Mode Contract Auditor
```bash
python3 tools/audit_process_modes.py || python tools/audit_process_modes.py || py -3 tools/audit_process_modes.py
```

### Deterministic Replay Test Harness
```bash
python3 tools/replay_test.py || python tools/replay_test.py || py -3 tools/replay_test.py
```

### Dynamic Formation & Boundary Fuzzing
```bash
python3 tools/fuzz_formations.py || python tools/fuzz_formations.py || py -3 tools/fuzz_formations.py
```

### Mathematical Solvers Micro-Benchmark
```bash
python3 tools/benchmark_math.py || python tools/benchmark_math.py || py -3 tools/benchmark_math.py
```

### Scene Graph & Resource Verification
```bash
python3 tools/tscn_linter.py || python tools/tscn_linter.py || py -3 tools/tscn_linter.py
```

### Database Integrity Verification
```bash
python3 tools/verify_db.py || python tools/verify_db.py || py -3 tools/verify_db.py
```

### Autoload Handling Contract
`gdcheck.py` reads `[autoload]` from `project.godot` and treats every autoload name as a known type. Never add `class_name` to an autoload script.
</verification>

<tooling>
## 3. Developer Tooling & Slash Commands

| Command | Action | Description |
|---|---|---|
| `/verify-all` | `tools/git_pre_commit.py` | Complete verification suite (gdcheck, invariants, tscn, stringnames, shadowing, db) |
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
| `/layer-ctx` | `tools/layer_context.py [1-5]` | Extract targeted context for simulation layers 1–5 |
</tooling>

<gemini_context_protocol>
## 4. Gemini Context Protocol & Antigravity Autonomy

### Large Context Window & Context Caching
- **Cached Architecture Prefix:** `POWERFOOTBALL_MASTER_VISION.md`, `docs/CORE_INVARIANTS.md`, `docs/API_SURFACE.md`, `AGENTS.md`, and `llms.txt` reside in the context prefix.
- **Holistic Cross-Layer Awareness:** Gemini's 1M+ token context window enables reasoning across multiple simulation layers simultaneously without lossy compaction.
- **Self-Healing Iteration:** When `.antigravity/hooks.json` intercepts a verification failure, review the `gdcheck.py` error diagnostic, locate the file and line number, and resolve type/syntax/contract errors immediately.

### Atomic Feature Discipline
- **One Feature = One File Set + One Verification Pass:** Execute changes in modular, cohesive units.
- **Strict Verification Gate:** Always verify with `tools/gdcheck.py` and `tools/lint_invariants.py` prior to completing any turn.
- **Errata Synchronization:** Record novel failure modes, API misconceptions, and runtime discoveries into `AGENTS_ERRATA.md` using the structured machine-readable format. Promote to `.claude/rules/` and `docs/CORE_INVARIANTS.md` via `/sync-rules` or `/compact-errata`.
</gemini_context_protocol>
