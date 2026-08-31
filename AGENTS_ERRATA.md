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

discovered_rules:
  - id: press-trigger-needs-time-backstop
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - autoloads/MatchWorldModel.gd
      - entities/player/PlayerBrain.gd
    invariant: >
      The three original press triggers (FACING_OWN_GOAL, TOUCHLINE_ISOLATION,
      HEAVY_TOUCH) are all narrow heuristics on the ball carrier's current
      posture/position — none of them fire on a carrier who calmly holds or
      dribbles mid-pitch facing forward. Since PlayerBrain._should_chase_ball()
      /clamp_chase_target() only lift the anchor-distance chase clamp while
      MatchWorldModel.press_trigger_active names an opposing carrier, a calm
      carrier outside every defender/midfielder's anchor-relative chase radius
      produces an indefinite, self-sustaining stand-off: the whole
      non-possessing side scores MaintainFormation forever with nothing to
      break it. Any future trigger heuristic added to this system must be
      accompanied by, or covered by, a time-based backstop trigger (see
      PROLONGED_POSSESSION, MatchWorldModel.gd) — do not assume posture-based
      heuristics alone are sufficient to guarantee a press eventually happens.
    rationale: >
      Confirmed via full reads of _should_chase_ball(), clamp_chase_target(),
      _update_press_trigger(), and all three _check_*_trigger() functions —
      a CPU-vs-CPU match reported by the user froze into a permanent
      white-presses-once-then-both-teams-stand-still state after a kickoff
      mis-pass put the ball on a calmly-holding opponent, exactly matching
      this gap.
    promotion_target: .claude/rules/ai-architect.md
    status: pending

  - id: kickoff-backward-pass-veto-starves-taker
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
      - pitch/SetPieceCoordinator.gd
    invariant: >
      _find_best_pass_target()'s low-composure safety valve
      (`if forward_dot < -0.2 and eff_composure < 0.55: continue`) rejects any
      candidate positioned behind the passer along the attack axis. At
      kickoff, SetPieceCoordinator._enforce_kickoff_halves() confines every
      outfield player except the taker — who stands exactly on the centre
      spot / halfway line — to their own half, i.e. structurally behind the
      taker. For any taker with composure_attribute below 0.55 this makes
      forward_dot < -0.2 for literally every teammate, so the loop rejects
      every candidate and find_pass_target_for_set_piece() returns null.
      _activate_set_piece() then leaves the CPU taker's stale
      facing_direction untouched, ChargeKickState fires an immediate CPU tap
      (CPU never holds action_kick, so _held_time is one physics frame — always
      a tap) along that stale forward-facing direction, and the ball rolls
      into the opponent's half where — by the same half-confinement rule — no
      teammate can be standing. Immediate kickoff turnover, exactly matching
      the "kickoff mis-pass" symptom in press-trigger-needs-time-backstop
      above. Any future caller of _find_best_pass_target() for a restart
      where IFAB rules confine the receiving side to one half (kickoff today,
      potentially others later) must pass allow_backward_pass=true, or the
      veto will silently starve it of every candidate whenever the taker's
      composure rolls low.
    rationale: >
      Traced end-to-end: SetPieceCoordinator._enforce_kickoff_halves()
      (clamps all non-taker players, both teams, to their own half) ->
      PlayerBrain._find_best_pass_target()'s composure-gated backward-pass
      continue -> SetPieceCoordinator._activate_set_piece()'s
      pass_target-null branch (facing_direction left untouched) ->
      ChargeKickState._release_kick()'s CPU-always-taps-instantly path
      (wants() always false for a non-user-controlled player, so
      still_held is always false and _held_time is a single physics frame).
      User-reported: every kickoff, the kicking team passes into the
      opponent's half and immediately loses possession.
    resolution: >
      Added allow_backward_pass: bool = false to
      PlayerBrain._find_best_pass_target(); find_pass_target_for_set_piece()
      now calls _find_best_pass_target(0.0, true) so restart takers can
      target a real teammate regardless of composure. The normal open-play
      caller (evaluate_tactical_action(), via _cached_pass_target) is
      unchanged and still applies the low-composure veto.
    promotion_target: .claude/rules/ai-architect.md
    status: pending

  - id: loose-ball-anchor-clamp-deadlock
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
      - autoloads/MatchWorldModel.gd
    invariant: >
      PlayerBrain._should_chase_ball()'s final gate clamps the chase target to
      within the player's role max_chase_distance of their FORMATION ANCHOR
      (not their current position), via clamp_chase_target(). That clamp is
      only bypassed while MatchWorldModel.press_trigger_active names an
      opposing carrier — but none of the four press triggers (FACING_OWN_GOAL,
      TOUCHLINE_ISOLATION, HEAVY_TOUCH, PROLONGED_POSSESSION) can ever arm for
      a ball nobody possesses, since all four key off a named carrier
      (`ball.possessor` or `ball.last_touched_by`). So a ball that goes loose
      and comes to rest outside every single player's anchor budget on both
      teams — trivially reachable right after kickoff, since anchors haven't
      reshaped from their kickoff-clamped positions yet, or after any
      mis-hit/deflected pass — makes _should_chase_ball() return false for
      all 22 players simultaneously. _score_chase() then scores 0.0 for
      everyone, MaintainFormation wins by default, and every player sits at
      (or oscillates near) their anchor forever: no one moves, but
      PlayerBrain still recomputes _cached_space_target and facing_direction
      on its usual per-player staggered cadence, so players visibly reorient
      in place without ever closing on the ball. This is a total,
      un-recovering match freeze, not a temporary stand-off — confirmed via a
      user screenshot showing a stationary loose ball with a red player
      standing ~90px away making no attempt to close it down, minutes into a
      match. Any future press-trigger-style exemption from the anchor clamp
      must also account for the "nobody owns the ball" case, not just
      "an opponent owns the ball" — a named carrier is not the only condition
      under which shape discipline should yield.
    rationale: >
      Traced end-to-end from the screenshot symptom: _score_chase() gates
      hard on ctx.chase_is_legal (_should_chase_ball()) -> the anchor-relative
      clamp_chase_target() call at the tail of _should_chase_ball() -> the
      press-trigger exemption inside clamp_chase_target() requires
      wm.press_trigger_carrier != null, which is never true for a loose ball
      -> MatchWorldModel's four _check_*_trigger() functions, all of which
      read ball.possessor/last_touched_by and do nothing when the ball is
      simply free. This is a distinct, deeper cause from
      press-trigger-needs-time-backstop above (that entry's PROLONGED_
      POSSESSION fix only covers a calmly-HELD ball outstaying its welcome;
      it cannot fire for a ball nobody is holding at all) and from
      kickoff-backward-pass-veto-starves-taker above (fixing the initial
      mis-pass does not help once *any* pass — a legitimate one included —
      puts the ball somewhere no anchor currently reaches).
    resolution: >
      Added a loose-ball bypass in PlayerBrain._should_chase_ball(): when
      ball.possessor == null, return true immediately after the existing
      role-budget (closer_count < budget) and absolute max_dist checks,
      skipping only the anchor-relative clamp. The single closest
      role-eligible player already selected by those upstream checks is now
      free to break formation and collect an unclaimed ball; role budgets and
      absolute chase range are untouched, so this does not send the whole
      team roaming.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
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

  - id: ERR-20260831-01
    date: 2026-08-31
    agent: Claude
    subsystem: ai
    symptom: >
      User-reported CPU-vs-CPU match froze permanently: white kicked off, the
      ball ended up with red, white pressed briefly, then both teams stood
      still indefinitely (match clock kept running, so IN_PLAY was never
      stuck — the freeze was a decision-layer stand-off, not a phase-gate bug).
    root_cause: >
      Two compounding issues. (1) ChargeKickState._get_resolved_aim() falls
      back to player.facing_direction for any non-user-controlled taker
      (_aim_accumulator is only ever filled when is_user_controlled). A CPU
      kickoff/set-piece taker was frozen in SetPieceFreezeState then teleported
      onto its restart spot by _apply_formation() — neither step touches
      facing_direction — so the kickoff tap fired along a stale direction with
      no regard for teammates, often landing near an opponent parked only
      wall_distance (176px) away. (2) Once the opponent settled into calm
      possession, PlayerBrain._should_chase_ball()/clamp_chase_target() only
      allow a player to chase beyond its formation-anchor-relative radius while
      MatchWorldModel.press_trigger_active names that carrier — and none of
      the three prior triggers (FACING_OWN_GOAL, TOUCHLINE_ISOLATION,
      HEAVY_TOUCH) fire for a carrier who just holds the ball calmly facing
      forward mid-pitch. With no trigger ever arming, every player on the
      non-possessing side defaults to MaintainFormation forever — see the
      press-trigger-needs-time-backstop discovered_rule above.
    resolution: >
      Added a 4th press trigger, PROLONGED_POSSESSION (MatchWorldModel.gd):
      a _possession_hold_timer resets whenever possessor_index changes and
      accumulates otherwise; _check_prolonged_possession_trigger() arms the
      trigger once the same possessor has held the ball for
      PROLONGED_POSSESSION_SECONDS (2.5s) with no other trigger having fired.
      No changes were needed to _should_chase_ball(), clamp_chase_target(),
      _score_chase(), or _resolve_defensive_duty() — all already treat
      press_trigger_active/press_trigger_carrier generically across trigger
      types. Separately, added PlayerBrain.find_pass_target_for_set_piece()
      (thin public wrapper over the existing _find_best_pass_target()) and
      call it from SetPieceCoordinator._activate_set_piece() to orient a CPU
      taker's facing_direction at a real teammate before forcing CHARGE_KICK,
      covering every CPU-taken restart (kickoff, free kick, corner), not just
      kickoff.
    affected_files:
      - autoloads/MatchWorldModel.gd
      - entities/player/PlayerBrain.gd
      - pitch/SetPieceCoordinator.gd
```
