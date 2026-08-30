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
    agent: Antigravity (Gemini 3.7 Flash)
    task: "Repository-Wide Documentation & Architectural Integrity Audit: Eliminated stale 'Known Gaps', obsolete TODOs, phantom exports, and contract drifts across pitch/README.md, entities/ball/README.md, entities/player/README.md, shared/README.md, autoloads/README.md, ui/README.md, tools/README.md, docs/CORE_INVARIANTS.md, CLAUDE.md, POWERFOOTBALL_MASTER_VISION.md, .claude/rules/soccer-physics.md, autoloads/GameManager.gd, and entities/ball/states/PossessionState.gd. Synchronized 6-layer collision matrix, MatchStatsTracker boot order, and Phase 1 completion checklist."
    files_modified:
      - pitch/README.md
      - entities/ball/README.md
      - entities/player/README.md
      - shared/README.md
      - autoloads/README.md
      - ui/README.md
      - tools/README.md
      - docs/CORE_INVARIANTS.md
      - CLAUDE.md
      - POWERFOOTBALL_MASTER_VISION.md
      - .claude/rules/soccer-physics.md
      - autoloads/GameManager.gd
      - entities/ball/states/PossessionState.gd
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors, 0 warnings (76 scripts)"
    invariants_consulted:
      - docs/CORE_INVARIANTS.md
      - docs/API_SURFACE.md
      - AGENTS.md
      - ROADMAP.md
    next_steps: "Proceed with next Phase 1 tasks (Injury system, AerialState/heading resolution, Through-ball lead targeting)."
    new_rules_discovered: []

  - date: 2026-08-31
    agent: Antigravity (Gemini 3.7 Flash)
    task: "Autonomous Agent Reasoning & Verification Environment Overhaul: Created tools/lint_invariants.py (enforcing brain mutation laws, zero allocations in hot paths, collision matrix, and choke point compliance), tools/eval_simulation.py (headless simulation assertion harness and telemetry evaluator), tools/dump_dep_graph.py (static dependency DAG and blast radius analyzer -> docs/DEPENDENCY_GRAPH.json), updated pitch/PitchScene.gd with headless sim telemetry runner, created docs/ANTI_PATTERNS.md (anti-hallucination corpus) and docs/MATH_SOLVERS.md (mathematical solvers reference), optimized BPE tokenizer layout, synchronized .antigravity/commands.json, .agents/commands.json, .antigravity/hooks.json, .agents/hooks.json, and llms.txt."
    files_modified:
      - tools/lint_invariants.py
      - tools/eval_simulation.py
      - tools/dump_dep_graph.py
      - tools/hook_gdcheck.py
      - tools/README.md
      - pitch/PitchScene.gd
      - entities/player/HeavyPlayerController.gd
      - entities/player/states/SetPieceFreezeState.gd
      - docs/ANTI_PATTERNS.md
      - docs/MATH_SOLVERS.md
      - docs/DEPENDENCY_GRAPH.json
      - .antigravity/commands.json
      - .agents/commands.json
      - .antigravity/hooks.json
      - .agents/hooks.json
      - llms.txt
      - AGENTS.md
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors, 0 warnings (76 scripts)"
    invariants_consulted:
      - docs/CORE_INVARIANTS.md
      - docs/API_SURFACE.md
      - docs/ANTI_PATTERNS.md
      - docs/MATH_SOLVERS.md
      - AGENTS.md
      - llms.txt
    next_steps: "Harness is fully primed for autonomous feature development (Injury system, AerialState/heading resolution, Through-ball lead targeting)."
    new_rules_discovered: []

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
    next_steps: "Execute full verification gate across all suites and deploy autonomous reasoning harness."
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
