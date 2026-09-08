# Errata Session History & Handoff Logs

This page records session handoff state logs, historical task descriptions, and files modified across autonomous agent sessions.

---

## Table of Contents
- [Recent Session State Archive](#recent-session-state-archive)
- [Session State: 2026-09-02 (Manager Career Mode, Phase 4)](#session-state-2026-09-02-manager-career-mode-phase-4)

---

## Recent Session State Archive

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

  - date: 2026-08-31
      agent: Claude
      task: >
        Implemented the macro match architecture (Team Match Urgency, an
        anti-snowball Team Momentum accumulator, and 4 temporal Match Stages)
        per POWERFOOTBALL_MASTER_VISION.md / "2D Football Engine Architecture
        Plan.pdf", adapted to this repo's real signal signatures and scoring
        functions rather than the plan's illustrative generic samples (see the
        3 new discovered_rules entries above). GameEvents gained 3 signals
        (team_urgency_updated, team_momentum_updated, match_stage_changed).
        GameManager owns MatchStage (fraction-of-match_duration boundaries) and
        broadcasts transitions. ManagerDirector runs a ~1s urgency tick per
        team (tanh scoreline/time S-curve + a derived risk_profile, Phase-0
        dampened). MatchStatsTracker owns momentum: continuous decay + 5
        discrete event impulses (shot on target/tackle won/goal conceded/
        turnover/5-pass sequence in the opponent's half), quadratically
        self-dampened. MatchWorldModel caches all three as the hot-path read
        surface. PlayerBrain's _find_best_pass_target() modulates
        PassUtilityScorer's w_press/w_adv by urgency (loop-invariant, computed
        once per decision tick); its two FormationAnchorMath.
        get_dynamic_anchor_position() call sites thread urgency through a new
        trailing optional param (default 0.0) that shifts the shared
        defensive-line depth and scales lateral compactness. MoodSystem folds
        an ambient own/opponent momentum term into get_composure_delta().
        PitchScene reacts to a sharp home-team momentum swing (|delta| > 0.35)
        with a fixed-text touchline shout, matching the existing
        home-perspective-only convention. tools/fuzz_formations.py's Python
        mirror of get_dynamic_anchor_position() was updated in lockstep and
        re-run (50k iterations, urgency in [-1,1]) — 0 boundary/ordering/NaN
        violations.
      files_modified:
        - autoloads/GameEvents.gd
        - autoloads/GameManager.gd
        - autoloads/MatchWorldModel.gd
        - autoloads/MatchStatsTracker.gd
        - entities/manager/ManagerDirector.gd
        - entities/player/MoodSystem.gd
        - entities/player/PlayerBrain.gd
        - shared/FormationAnchorMath.gd
        - pitch/PitchScene.gd
        - tools/fuzz_formations.py
        - AGENTS_ERRATA.md
      gdcheck_status: "pass, 0 errors, 0 warnings (76 scripts)"
      invariants_consulted:
        - docs/CORE_INVARIANTS.md
        - .claude/rules/godot-47-core.md
        - .claude/rules/soccer-physics.md
        - .claude/rules/ai-architect.md
        - .claude/rules/gdscript-antipatterns.md
      next_steps: >
        verify_gate.py --full passes (15/15). No PressOffice quote category
        exists yet for a momentum-swing touchline reaction (see
        touchline-bubble-is-one-shared-instance-home-perspective-only above) —
        a future task could add trait-flavored variants there instead of the
        current two fixed strings. Sprint-threshold urgency modulation
        (PlayerBrain.wants_sprint) was intentionally left out — not in the
        task's 5 numbered formula specs, and no existing call site needed it.
      new_rules_discovered:
        - manager-risk-profile-is-derived-not-authored
        - match-stage-boundaries-are-fractions-not-literal-seconds
        - touchline-bubble-is-one-shared-instance-home-perspective-only

  - date: 2026-08-31
      agent: Claude
      task: >
        Investigating a SECOND, distinct throw-in freeze reported live after
        the ERR-20260831-03 fix (ThrowInState CPU branch no longer gated on
        current_action == &"Pass") was already in place. This run's evidence
        does not match ERR-20260831-03's shape: [SpacingReport] numbers were
        still changing between the two windows shown (not bit-for-bit frozen
        like the first report), so most players were still moving — only the
        ball was stuck, at a throw-in-formula-exact position (y=474.0 = pitch
        half.y(450) + THROW_IN_INSET(24), matching _start_throw_in()), with
        the closest player 213px away (a correctly-placed taker should read
        ~0px). Traced _release_throw()'s two early-return branches (no ball
        found / ball already possessed by someone else) and confirmed by
        re-reading ThrowInState.process()'s caller that both branches still
        transition the FSM to MOVE/IDLE unconditionally right after calling
        _release_throw(), which still fires _on_taker_state_changed() and
        still calls GameManager.restart_play() — so that specific theory
        (silent no-op leaving the phase stuck) does not hold up on a second
        read; did not change that code. Separately noticed, while reading
        _activate_set_piece()/_on_taker_state_changed(), that _current_taker
        is a single mutable SetPieceCoordinator field with no per-restart
        snapshotting: the state_changed signal connected in
        _activate_set_piece() closes over _current_taker by reference, so if
        a second handle_out_of_bounds() ever fires (and reassigns
        _current_taker to a new taker) before the FIRST taker's own
        THROW_IN-\>MOVE/IDLE transition fires, _on_taker_state_changed()
        would try to disconnect the signal from the WRONG (new) taker when
        the original one's transition eventually arrives — a real fragility,
        but no confirmed evidence yet that reentrancy is actually happening
        this session, so this was recorded rather than "fixed" preemptively.
        Chose instrumentation over a third speculative patch per the
        Error Compounding Rule in course_implementation_specification.md
        Section 15 ("if a bug cannot be resolved in 2 iterations, stop").
      files_modified:
        - pitch/SetPieceCoordinator.gd
        - entities/player/states/ThrowInState.gd
      gdcheck_status: "pass, 0 errors, 0 warnings (76 scripts)"
      invariants_consulted:
        - AGENTS_ERRATA.md (ERR-20260831-02, ERR-20260831-03, crowding-space-creation-diagnostics)
        - .claude/rules/godot-47-core.md
        - .claude/rules/ai-architect.md
      next_steps: >
        Added an always-on (no debug flag needed) [SetPiece] breadcrumb trail
        covering the full restart lifecycle: handle_out_of_bounds() entry
        (also logs _awaiting_confirmation/_current_taker at call time, so a
        re-entrant second trigger while the first restart is still pending is
        immediately visible), _assign_taker() (taker name + placed position +
        distance from the intended spot, or an explicit "FOUND NO
        CANDIDATES" line), _await_taker_confirmation() (delay chosen),
        _activate_set_piece() (taker position vs set_piece_position
        immediately before the ball is placed — this is the key line: if the
        taker is already far from the spot HERE, the drift happened during
        the SET_PIECE_FREEZE await-confirmation window, which should be
        physically impossible since that state applies zero movement intent
        every frame; if the taker is still ~0px away here but drifts before
        the next stall report, the drift happened inside ThrowInState
        itself, e.g. via PlayerBrain writing a large movement_intent for the
        is_throw_in_taker FindSpace branch that ThrowInState.physics_process()
        then applies along the touchline), ThrowInState.enter() (taker pos vs
        ball pos at state entry), and ThrowInState._release_throw() (all
        three outcomes: no ball found, ball already possessed by someone
        else, or a real throw — each with taker/ball positions and the
        resulting distance). Next session: get a fresh log from the user with
        this instrumentation in place. Whichever [SetPiece] line is the LAST
        one printed before the freeze pinpoints the exact failing step
        without further guessing — do not add a fourth speculative code fix
        before that log exists.
      new_rules_discovered:
        - throw-in-taker-current-taker-is-unscoped-mutable-state
```

---

## Session State: 2026-09-02 (Manager Career Mode, Phase 4)

TASK: Build Manager Career mode — career data layer, day loop, save/load, and
the FM-style UI shell, wired into the existing match engine.

FILES MODIFIED: 18 new resources in `shared/career/`, 2 new autoloads
(`CareerManager`, `WorldEventLog`), 16 files in `ui/manager_mode/`, plus
`PlayerFactory`, `PitchScene`, `TrustSystem`, `RefereeLoader`, `DataLoader`,
`GameEvents`, `MainMenu`, `project.godot`, `tools/gdcheck.py`,
`tools/verify_gate.py`, and a new `tools/lint_xref.py`.

GDCHECK: pass (139 scripts, 0 errors). verify_gate --full: 16/16 pass.

INVARIANTS CONSULTED: `godot-47-core.md`, `ai-architect.md`,
`soccer-physics.md`, `gdscript-antipatterns.md`, `context-hygiene.md`,
`docs/CORE_INVARIANTS.md`.

NEW RULES: promoted to `.claude/rules/career-mode.md`.

### Architectural & Gotcha Findings from this Session
The specific technical findings from this session have been modularized into their primary domain pages:
- **[Three latent runtime crashes found by static cross-referencing](scene-and-node-paths.md#three-latent-runtime-crashes-found-by-static-cross-referencing)** (Score/card array access, missing RefereeLoader method, TrustSystem clamp bug, rule for `tools/lint_xref.py`)
- **[Calibration is not optional, and the first guess was wrong twice](data-and-persistence.md#calibration-is-not-optional-and-the-first-guess-was-wrong-twice)** (Player decline curve and Morale-to-MoodSystem seeding calibration)
- **[The season calendar cannot be a fixed weekly rhythm](data-and-persistence.md#the-season-calendar-cannot-be-a-fixed-weekly-rhythm)** (Season matchday spacing derived from round count)
- **[Non-ASCII identifiers parse here but not in Godot](scene-and-node-paths.md#non-ascii-identifiers-parse-here-but-not-in-godot)** (Cyrillic identifier engine gotcha)

### Next Steps Handoff
NEXT: nothing in the career layer has been EXECUTED — this container has no Godot binary. The next session with an engine should boot Manager Mode, start a career, and click through all 13 sections before trusting any of it. Highest risk is scene/layout rendering and signal dispatch, neither of which any static tool here can check.
