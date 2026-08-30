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
  - date: 2026-08-30
    agent: Antigravity (Gemini)
    task: "Implement off-ball channel runs & attacking space seeking, goalkeeper overhaul (positioning arc, sweeper rushing, dive commitment), and pitch boundary clamping with touchline/endline safety margins."
    files_modified:
      - shared/FormationLibrary.gd
      - entities/player/PlayerBrain.gd
      - entities/goalkeeper/GoalkeeperDiveBrain.gd
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors (71 scripts)"
    invariants_consulted:
      - docs/CORE_INVARIANTS.md
      - AGENTS.md
    next_steps: "Tune in-game match-feel and continue planned Phase 1 / Phase 2 systems."
    new_rules_discovered: []

  - date: 2026-08-31
    agent: Antigravity (Gemini 3.7 Flash)
    task: "Layer 4 Club World Expansion: Populated complete 8-team fictional league (144 players with 11 starters + 7 bench per squad), 10 tactical managers with trait bitmasks, and 8 officiating crew referee profiles. Synchronized DataLoader, ManagerLoader, and RefereeLoader with fallback hierarchy, complete deserialization, and multi-team selection routing."
    files_modified:
      - data/league.json
      - data/managers.json
      - data/referees.json
      - autoloads/DataLoader.gd
      - autoloads/ManagerLoader.gd
      - autoloads/RefereeLoader.gd
      - pitch/PitchScene.gd
      - ui/pregame/PreGameScreen.gd
      - shared/PlayerFactory.gd
      - tools/generate_db.py
      - tools/verify_db.py
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors, 0 warnings (76 scripts)"
    invariants_consulted:
      - docs/CORE_INVARIANTS.md
      - docs/json-schema.md
      - AGENTS.md
    next_steps: "Integrate league tournament schedules / fixtures or expand Phase 1 injury & stamina persistence across matches."
    new_rules_discovered: []

  - date: 2026-08-31
    agent: Antigravity (Gemini 3.7 Flash)
    task: "Repository Optimization & Agent Harness Architecture: Created tools/dump_api.py & docs/API_SURFACE.md across 5 simulation layers (76 scripts parsed), expanded .antigravity/hooks.json and tools/hook_gdcheck.py with XML diagnostic emitter, created tools/compact_errata.py & .antigravity/scratchpad.md, implemented tools/layer_context.py with slash commands in .antigravity/commands.json, updated .aiexclude to block token waste, and injected semantic XML routing tags into llms.txt and AGENTS.md."
    files_modified:
      - tools/dump_api.py
      - docs/API_SURFACE.md
      - tools/hook_gdcheck.py
      - .antigravity/hooks.json
      - .agents/hooks.json
      - tools/compact_errata.py
      - .antigravity/scratchpad.md
      - docs/archive/errata_history.md
      - tools/layer_context.py
      - .antigravity/commands.json
      - .agents/commands.json
      - .aiexclude
      - llms.txt
      - AGENTS.md
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors, 0 warnings (76 scripts)"
    invariants_consulted:
      - docs/CORE_INVARIANTS.md
      - AGENTS.md
      - llms.txt
      - docs/API_SURFACE.md
    next_steps: "Utilize layer context tool and updated developer harness for Phase 1 gameplay features (injury system, aerial states)."
    new_rules_discovered: []

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
