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
    task: "Configure repo tooling for Google Antigravity & Gemini: hooks.json, .aiexclude, AGENTS.md XML tags, AGENTS_ERRATA.md machine-readable schemas."
    files_modified:
      - .antigravity/hooks.json
      - .agents/hooks.json
      - tools/hook_gdcheck.py
      - .aiexclude
      - AGENTS.md
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors (71 scripts)"
    invariants_consulted:
      - AGENTS.md (Engine Lock, Simulation Stack, Critical File Contracts, Gemini Context Protocol)
      - .claude/rules/godot-47-core.md
    next_steps: "Continuous multi-agent sync and feature execution."
    new_rules_discovered: []

  - date: 2026-08-30
    agent: Antigravity (Gemini)
    task: "Advanced repository optimizations: Configure slash commands (.antigravity/commands.json, /verify, /sync-rules, /next-task), optimize llms.txt as RAG semantic router with 5 simulation layer tags, extract docs/CORE_INVARIANTS.md, and eliminate manual sync drift between AGENTS.md and CLAUDE.md."
    files_modified:
      - .antigravity/commands.json
      - .agents/commands.json
      - tools/sync_rules.py
      - tools/next_task.py
      - docs/CORE_INVARIANTS.md
      - AGENTS.md
      - CLAUDE.md
      - llms.txt
      - AGENTS_ERRATA.md
    gdcheck_status: "pass, 0 errors (71 scripts)"
    invariants_consulted:
      - docs/CORE_INVARIANTS.md
      - POWERFOOTBALL_MASTER_VISION.md
      - ROADMAP.md
    next_steps: "Proceed with Phase 1 task: Injury system."
    new_rules_discovered: []

  - date: 2026-08-30
    agent: Claude
    task: "Implement phase-dependent dynamic formation anchors (IN_POSSESSION / OUT_OF_POSSESSION / TRANSITION) on top of compactness lerp."
    files_modified:
      - shared/FormationAnchorMath.gd
      - entities/player/PlayerBrain.gd
    gdcheck_status: "pass, 0 errors (68 scripts)"
    invariants_consulted:
      - .claude/rules/ai-architect.md
      - .claude/rules/godot-47-core.md
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
