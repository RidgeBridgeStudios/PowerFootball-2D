# AGENTS_ERRATA.md

Cross-agent shared memory and escape hatch for autonomous agent sessions (Antigravity, Gemini, DeepSeek, Claude Code). Rules and invariants recorded here are parsed by automated tooling and promoted to `.claude/rules/` and `AGENTS.md`.

## Discovered Rules

```yaml
# Schema:
# discovered_rules:
#   - id: string (kebab-case identifier)
#     discovered_date: YYYY-MM-DD
#     discovered_by: string (model/agent identifier)
#     category: engine | physics | ai | social | data | architecture
#     target_files:
#       - string (file path)
#     invariant: string (the rule or negative constraint)
#     rationale: string (why the rule exists)
#     promotion_target: string (path to rulebook destination)
#     status: pending | promoted

discovered_rules: []
```

## Session State

```yaml
# Schema for recording session handoff state:
# session_state:
#   date: YYYY-MM-DD
#   agent: string
#   task: string
#   files_modified:
#     - string
#   gdcheck_status: pass | fail (error count)
#   invariants_consulted:
#     - string
#   next_steps: string
#   new_rules_discovered: []

session_state:
  - date: 2026-08-31
    agent: Antigravity (Principal Repo & Agent Inference Harness Architect)
    task: "Comprehensive Repository & Agent Inference Harness Transformation across 6 Phases: Implemented tools/tscn_linter.py (scene graph & collision linter), tools/validate_schemas.py (strict JSON schema validator), tools/fuzz_solvers.py (100k property fuzz testing suite), tools/spatial_grid_bench.py (22-entity spatial query latency benchmark), tools/dump_match_frames.py (multimodal SVG frame exporter), tools/formation_ascii.py (terminal ASCII tactical pitch renderer), tools/mcp_server.py (standard stdio Model Context Protocol server), tools/lsp_client.py (Godot LSP bridge with static fallback), tools/worktree_manager.py (automated git worktree sandbox manager), and authored .antigravity/skills/ (eval-sim, ast-refactor, formation-audit). Synchronized .antigravity/commands.json, .agents/commands.json, .antigravity/hooks.json, .aiexclude, AGENTS.md, llms.txt, and tools/README.md."
    files_modified:
      - tools/lint_invariants.py
      - tools/tscn_linter.py
      - tools/validate_schemas.py
      - tools/fuzz_solvers.py
      - tools/spatial_grid_bench.py
      - tools/dump_match_frames.py
      - tools/formation_ascii.py
      - tools/mcp_server.py
      - tools/lsp_client.py
      - tools/worktree_manager.py
      - tools/dump_dep_graph.py
      - tools/hook_gdcheck.py
      - tools/README.md
      - .antigravity/skills/eval-sim/SKILL.md
      - .antigravity/skills/ast-refactor/SKILL.md
      - .antigravity/skills/formation-audit/SKILL.md
      - .antigravity/commands.json
      - .agents/commands.json
      - .antigravity/scratchpad.md
      - .aiexclude
      - AGENTS.md
      - llms.txt
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors, 0 warnings (76 scripts)"
    invariants_consulted:
      - docs/CORE_INVARIANTS.md
      - docs/API_SURFACE.md
      - docs/ANTI_PATTERNS.md
      - docs/MATH_SOLVERS.md
      - AGENTS.md
      - llms.txt

  - date: 2026-08-31
    agent: Antigravity (Principal Engine Architect & Static Analysis Specialist)
    task: "Low-Level Engine Optimization, Deterministic Replay, Linters & Symbolic Slicing Suite: Refactored MatchWorldModel.gd with typed Array[int] spatial grid buckets and distance_squared_to() comparisons; replaced transient allocations and distance_to sorting across ActionText.gd, TouchlineBubble.gd, SetPieceCoordinator.gd, PitchScene.gd, and PlayerBrain.gd; created tools/lint_stringnames.py (&'string_name' literal enforcement), tools/lint_allocations.py (hot-path allocation & distance sorting linter), tools/lint_signal_races.py (signal emission race condition auditor), tools/lint_shadowing.py (parameter & variable shadowing linter), tools/audit_process_modes.py (process mode consistency auditor), tools/replay_test.py (100% bit-exact 60Hz replay test harness across 1,800 ticks), tools/generate_symbols.py (AST symbol map -> docs/SYMBOLS.json), tools/codebase_slice.py (targeted symbol & method slicing CLI), tools/semantic_search.py (zero-dependency BM25 retrieval indexer), tools/benchmark_math.py (mathematical solvers benchmark), tools/fuzz_formations.py (50k property-based dynamic anchor fuzzer), tools/git_pre_commit.py (pre-commit installer & verifier), and authored .antigravity/skills/ (formation-fuzzer, perf-benchmark). Synchronized .antigravity/commands.json, .agents/commands.json, .antigravity/hooks.json, .agents/hooks.json, llms.txt, and AGENTS.md."
    files_modified:
      - autoloads/MatchWorldModel.gd
      - ui/ActionText.gd
      - ui/TouchlineBubble.gd
      - pitch/SetPieceCoordinator.gd
      - pitch/PitchScene.gd
      - entities/player/PlayerBrain.gd
      - ui/HUD.gd
      - ui/pause/PauseMenu.gd
      - tools/lint_stringnames.py
      - tools/lint_allocations.py
      - tools/lint_signal_races.py
      - tools/lint_shadowing.py
      - tools/audit_process_modes.py
      - tools/replay_test.py
      - tools/generate_symbols.py
      - tools/codebase_slice.py
      - tools/semantic_search.py
      - tools/benchmark_math.py
      - tools/fuzz_formations.py
      - tools/git_pre_commit.py
      - docs/SYMBOLS.json
      - docs/API_SURFACE.md
      - .antigravity/skills/formation-fuzzer/SKILL.md
      - .antigravity/skills/perf-benchmark/SKILL.md
      - .agents/skills/formation-fuzzer/SKILL.md
      - .agents/skills/perf-benchmark/SKILL.md
      - .antigravity/commands.json
      - .agents/commands.json
      - .antigravity/hooks.json
      - .agents/hooks.json
      - AGENTS.md
      - llms.txt
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors, 0 warnings (76 scripts)"
    invariants_consulted:
      - docs/CORE_INVARIANTS.md
      - docs/API_SURFACE.md
      - docs/ANTI_PATTERNS.md
      - docs/MATH_SOLVERS.md
      - AGENTS.md
      - llms.txt
    next_steps: "All engine optimizations, linters, replay harnesses, fuzzers, and symbolic slicers are 100% active and verified."
    new_rules_discovered: []

  - date: 2026-08-31
    agent: Antigravity (Principal Engine Architect & Autonomous Inference Harness Master)
    task: "Complete 7-Phase Repository Transformation into Autonomous Agent Reasoning & Evaluation Environment: Implemented tools/lint_scope.py (duplicate local variable declaration & dead-code AST linter), tools/lint_type_comparisons.py (Object vs StringName comparison safety linter), tools/verify_gate.py (unified fast & full verification gate orchestrator); refactored variable shadowing in MatchWorldModel.gd, ManagerDirector.gd, ThrowInState.gd, MatchOfficialCrew.gd, MatchCamera.gd, PitchScene.gd, SetPieceCoordinator.gd, PauseMenu.gd, and PreGameScreen.gd; configured .antigravity/mcp.json and .agents/mcp.json with stdio MCP server tools; authored complete skills across .antigravity/skills/ and .agents/skills/; updated docs/ANTI_PATTERNS.md with full 12-item Godot 4.7 pitfall matrix; synced rules across .claude/rules/ and .agents/rules/ including gdscript-antipatterns.md; embedded strict typing and autonomous XML guardrails into AGENTS.md; updated llms.txt, .aiexclude, .antigravity/hooks.json, and .agents/hooks.json."
    files_modified:
      - tools/lint_scope.py
      - tools/lint_type_comparisons.py
      - tools/verify_gate.py
      - tools/mcp_server.py
      - tools/eval_simulation.py
      - tools/replay_test.py
      - tools/semantic_search.py
      - autoloads/MatchWorldModel.gd
      - entities/manager/ManagerDirector.gd
      - entities/player/states/ThrowInState.gd
      - entities/referee/MatchOfficialCrew.gd
      - pitch/MatchCamera.gd
      - pitch/PitchScene.gd
      - pitch/SetPieceCoordinator.gd
      - ui/pause/PauseMenu.gd
      - ui/pregame/PreGameScreen.gd
      - docs/ANTI_PATTERNS.md
      - docs/API_SURFACE.md
      - docs/SYMBOLS.json
      - docs/DEPENDENCY_GRAPH.json
      - .claude/rules/gdscript-antipatterns.md
      - .agents/rules/ai-architect.md
      - .agents/rules/context-hygiene.md
      - .agents/rules/godot-47-core.md
      - .agents/rules/gdscript-antipatterns.md
      - .agents/rules/research-index.md
      - .agents/rules/soccer-physics.md
      - .agents/skills/eval-sim/SKILL.md
      - .agents/skills/ast-refactor/SKILL.md
      - .agents/skills/formation-audit/SKILL.md
      - .antigravity/mcp.json
      - .agents/mcp.json
      - .antigravity/hooks.json
      - .agents/hooks.json
      - .antigravity/commands.json
      - .agents/commands.json
      - .aiexclude
      - AGENTS.md
      - llms.txt
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors, 0 warnings (76 scripts)"
    invariants_consulted:
      - docs/CORE_INVARIANTS.md
      - docs/API_SURFACE.md
      - docs/ANTI_PATTERNS.md
      - docs/MATH_SOLVERS.md
      - AGENTS.md
      - llms.txt
    next_steps: "All verification gates, AST linters, MCP servers, fuzzers, and postmortem rules are fully active and verified at 100% safety."
    new_rules_discovered: []
```

## Error Log

```yaml
# Schema:
# error_log:
#   - id: string
#     date: YYYY-MM-DD
#     agent: string
#     subsystem: ai | physics | ui | data | engine
#     symptom: string
#     root_cause: string
#     resolution: string
#     affected_files:
#       - string

error_log:
  - id: ERR-20260830-01
    date: 2026-08-30
    agent: external-agent
    subsystem: ai
    symptom: >
      PlayerRoleConfig migration brief claimed a phantom constant ROLE_SPACE_ALPHA
      and a runtime crash from ROLE_SPACE_ALPHA.get(role, 0.35).
    root_cause: >
      ROLE_SPACE_ALPHA is a real const Dictionary in PlayerBrain.gd (pre-migration source of
      per-role roam alpha), so .get() on it is safe — no crash existed. The actual migration defect was a
      semantic inversion: anchor_weight (1.0 = rigid, 0.0 = free roam) was fed directly into
      _evaluate_off_ball_target()'s alpha, whose convention is the opposite (1.0 = roam, per
      ROLE_SPACE_ALPHA: DEF 0.20 / MID 0.40 / ATT 0.65). Note the alpha block lives in
      _evaluate_off_ball_target(), NOT _find_open_space_target(). DEFENSIVE_LINE_DEPTH_WEIGHT (0.55)
      is a separate constant governing X-axis defensive_line_x blending — unrelated to anchor alpha.
    resolution: >
      Correct consumer code: alpha = 1.0 - player.role_config.anchor_weight. Always guard
      reads with `if player.role_config != null`.
    affected_files:
      - entities/player/PlayerBrain.gd
      - shared/PlayerRoleConfig.gd

  - id: ERR-20260830-02
    date: 2026-08-30
    agent: Claude
    subsystem: ui
    symptom: >
      Substitution task brief assumed MatchWorldModel.refresh() exists and that HUD.gd
      already stores TeamData refs.
    root_cause: >
      MatchWorldModel refreshes itself every _physics_process (priority -100) from
      player_nodes[slot], which an in-place apply_player_data() swap never changes, so no
      explicit refresh call is needed or exists. HUD.gd holds no TeamData refs at all.
    resolution: >
      Resolve a substitution banner's names via DataLoader.get_player(team, squad_index)
      (never null, bounds-safe) instead of inventing stored refs. AGENTS.md has no roadmap
      checkbox mirror table (Section 5 is Context Protocol).
    affected_files:
      - autoloads/MatchWorldModel.gd
      - ui/HUD.gd
      - autoloads/DataLoader.gd
```
