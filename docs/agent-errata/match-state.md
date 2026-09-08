# Match State, Pacing & Urgency Errata

**Simulation Layer:** Layer 2 — Match AI & Layer 5 — Match Lifecycle  
**Primary Modules:** `autoloads/GameManager.gd`, `autoloads/MatchWorldModel.gd`, `entities/manager/ManagerDirector.gd`

This page records rules and gotchas governing match lifecycle timing, possession duration timers, macro match urgency formulas, and match-stage boundaries.

---

## Table of Contents
### Discovered Rules
- [match-stage-boundaries-are-fractions-not-literal-seconds](#match-stage-boundaries-are-fractions-not-literal-seconds)
- [possession-hold-timer-has-two-non-interchangeable-variants](#possession-hold-timer-has-two-non-interchangeable-variants)
- [stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate](#stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate)
- [manager-risk-profile-is-derived-not-authored](#manager-risk-profile-is-derived-not-authored)

---

## match-stage-boundaries-are-fractions-not-literal-seconds

```yaml
- id: match-stage-boundaries-are-fractions-not-literal-seconds
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: architecture
    target_files:
      - autoloads/GameManager.gd
    invariant: >
      GameManager.match_duration defaults to 300.0 (a 5-minute arcade match),
      not a real 90-minute/5400s fixture. Any macro temporal system (match
      stages, urgency's time_ratio, future pacing logic) must express its
      boundaries as fractions of match_duration (GameManager.STAGE_1/2/3_
      FRACTION = 15/60/75 out of 90) and read `match_time / match_duration`,
      never a hardcoded absolute-seconds threshold like the architecture
      plan's own illustrative code (`if t < 900.0`). A literal-seconds
      threshold silently never fires, or always fires instantly, once
      match_duration is anything other than 5400.
    rationale: >
      The docs architecture plan's ManagerDirector/MatchWorldModel code
      samples hardcode 900.0/3600.0/4500.0/5400.0 throughout, calibrated to
      a real 90-minute match. Cross-checked against the actual
      GameManager.gd, which is explicitly a compressed-clock arcade design
      ("300.0 = a 5 minute match").
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## possession-hold-timer-has-two-non-interchangeable-variants

```yaml
- id: possession-hold-timer-has-two-non-interchangeable-variants
    discovered_date: 2026-09-01
    discovered_by: Claude
    category: ai
    target_files:
      - autoloads/MatchWorldModel.gd
      - entities/player/PlayerBrain.gd
    invariant: >
      MatchWorldModel has TWO possession-duration timers and they are not
      interchangeable. _possession_hold_timer (feeds PROLONGED_POSSESSION,
      the press-trigger backstop) is keyed off possessor_index /
      _resolve_possessor_index(), which falls back to last_touched_by when
      the ball is loose (soccer-physics.md's documented possessor/
      last_touched_by split) — it can read nonzero for a player who is not
      the actual controlled carrier right now. _active_possession_timer
      (private; feeds the [ActionScorer] possession watchdog trace) is keyed
      directly off ball_node.possessor, exactly matching PlayerBrain's own
      ctx.is_possessor definition ((ball != null and ball.possessor ==
      player) or is_throw_in_taker). A second externally-authored
      "[TARGETED EDIT]" prompt (this one scoped to UtilityMath.gd/
      PassUtilityScorer.gd/MatchWorldModel.gd for an xT grid + "La Pausa"
      holding-play cap) explicitly named "_possession_hold_timer" as the one
      to reuse for forcing a standstill carrier to act — the wrong one for
      that purpose; using it would let the new logic fire based on loose-ball
      last-touch time rather than genuine held possession, or fail to fire
      promptly on a real transfer. Any future consumer of "how long has the
      ball been held" must pick deliberately between the two based on
      whether it cares about the true active carrier (is_possessor semantics
      — use the possession-watchdog timer) or the broader
      press-trigger-relevant "who's effectively in control including a
      loose exchange" reading (possessor_index semantics).
    rationale: >
      Same class of near-miss as verify-external-agent-prompts-against-
      source-before-executing (Phase 1, same file's sibling PR) — an
      external prompt named a real, existing symbol, but the wrong one for
      the stated intent. Caught by tracing what possessor_index and
      ctx.is_possessor are each actually keyed on rather than trusting the
      prompt's own attribution once the name was confirmed to exist.
    resolution: >
      Added MatchWorldModel.get_active_possession_hold_seconds() (returns
      _active_possession_timer, 0.0 while _active_possession_node is null)
      as the public accessor — PlayerBrain never previously read any
      underscore-prefixed MatchWorldModel field directly, so this also
      preserves that convention instead of reaching into a private field
      across files. evaluate_tactical_action()'s existing possessor floor
      ("if max_offensive <= 0.05: PanicClear") now has an elif: when
      best_action resolved to MaintainFormation with ctx.open_teammate_exists
      false and get_active_possession_hold_seconds() >
      LA_PAUSA_HOLD_SECONDS (1.0s), force AttemptDribble (if s_dribble clears
      the same 0.05 bar as the floor above) or PanicClear otherwise. Also
      added UtilityMath.XT_GRID (flat 16x10 PackedFloat32Array, row*16+col,
      hand-authored analytic shape — this project has no real match data to
      fit an xT model from, documented as such rather than presented as a
      real football-analytics table) and get_xt_value(pitch_pos, pitch_size,
      attack_sign), zero-allocation. PassUtilityScorer.score_pass()/
      score_pass_breakdown() gained a trailing xt_value: float = -1.0 param
      (appended, not inserted, so existing positional call sites are
      unaffected) blending it into advancement_utility as
      (direction_dot_utility + xt_value) * 0.5 when supplied.
      _find_best_pass_target()'s candidate loop computes xt_value per
      candidate from candidate_pos - pitch_boundary.get_centre_spot() (the
      centre-spot offset makes it correct even if a boundary is not
      origin-centred, rather than assuming the common-case default is always
      true). gdcheck + full lint suite (verify_gate.py --fast) and both
      prompt-specified checks (fuzz_solvers.py, eval_simulation.py
      --duration=60) pass; note both of those are Python-side property/
      analytical harnesses, not the actual GDScript executing in Godot (no
      engine in this sandbox — godot-47-core.md), so they confirm the
      surrounding math properties and simulation invariants hold, not that
      this specific new GDScript is runtime-exercised.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate

```yaml
- id: stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate
    discovered_date: 2026-09-01
    discovered_by: Claude
    category: ai
    target_files:
      - autoloads/GameManager.gd
      - entities/manager/ManagerDirector.gd
    invariant: >
      GameManager.STAGE_3_FRACTION = 75.0/90.0 ~= 0.833, not 0.90. A fourth
      externally-authored prompt (emergency tactics: GameEvents.gd +
      ManagerDirector.gd + PitchScene.gd + TouchlineBubble.gd) described the
      trigger condition in prose as "match time > 90% (GameManager.
      STAGE_3_FRACTION)" — citing the right symbol, wrong paraphrase of its
      value, same failure shape as this batch's other three prompts (real
      name, wrong attribute). Used the actual constant, not the prompt's 90%
      claim. Separately, and unlike the other three prompts in this batch,
      one part of this one was genuinely NOT redundant with existing code
      even though it looked like it might be: _evaluate_tactical_urgency()'s
      tanh(-TIME_ACCEL_K * delta_score * time_sq + risk_profile) already
      produces high urgency when trailing late (time_sq -> 1, delta_score
      negative), so "push the defensive line" might have seemed already
      covered — but tanh saturation means it does NOT reach the full +-1.0
      that drives FormationAnchorMath's URGENCY_MAX_DEF_LINE_SHIFT=120px
      push: trailing by exactly 1 goal exactly at STAGE_3_FRACTION only
      computes tanh(1.35*0.694 + risk_profile) = tanh([0.587, 1.287]) ~=
      [0.53, 0.86] depending on the manager's risk_profile ([-0.35, 0.35]) —
      i.e. roughly a 64-103px push, not 120px, and not a discrete
      escalation. Do not assume "the continuous formula already goes there
      eventually" means "the discrete emergency case is already handled" —
      check the actual saturation numerically before deciding a task is
      redundant, the same way you'd check a claimed-missing feature actually
      exists before building it.
    rationale: >
      Verified by hand-computing the tanh argument at the trigger boundary
      rather than eyeballing "urgency goes up late + trailing, so this must
      already be covered" — the same discipline as the batch's other three
      entries, applied to catch a false-negative (looks redundant, isn't)
      instead of the usual false-positive (looks new, already exists).
    resolution: >
      Added GameEvents.emergency_tactics_triggered(team, tactic_type) —
      genuinely new signal name, verified no collision. ManagerDirector gets
      a one-shot _emergency_tactics_triggered bool (same pattern as the
      existing _shifted_to_attack/_shifted_to_defend flags, reset in
      bind()): the first _evaluate_tactical_urgency() tick where
      time_ratio >= GameManager.STAGE_3_FRACTION and delta_score <= -1.0,
      it forces final_urgency = 1.0 for that tick's existing
      GameEvents.team_urgency_updated emit (reusing the exact existing
      +120px mechanism rather than adding a parallel defensive-line
      override) and separately emits emergency_tactics_triggered once.
      PitchScene.gd connects it and follows the ALREADY-DOCUMENTED
      touchline-bubble-is-one-shared-instance-home-perspective-only
      convention exactly (gates on team == GameManager.TEAM_A, matches
      _on_team_momentum_updated()'s fixed-quote-line style rather than
      routing through PressOffice — ALL_OUT_ATTACK isn't one of
      PressOffice's existing quote contexts and PressOffice.gd is outside
      this task's file scope, so inventing a new trait-quote category for
      it would have been scope creep). This is the one prompt in the batch
      whose stated invariants (home-perspective-only, signal-argument-count
      matching) were themselves accurate and worth trusting outright rather
      than needing correction. gdcheck + full lint suite + the
      prompt-specified python3 tools/verify_gate.py --full (15 steps,
      including eval_simulation/fuzz_solvers/fuzz_formations/dump_api/
      generate_symbols/compact_errata) all pass. Note --full's
      compact_errata step has the side effect of reformatting this file and
      archiving old session_state entries into docs/archive/
      errata_history.md every time it runs — expected, not a regression.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## manager-risk-profile-is-derived-not-authored

```yaml
- id: manager-risk-profile-is-derived-not-authored
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: architecture
    target_files:
      - entities/manager/ManagerDirector.gd
      - shared/ManagerData.gd
    invariant: >
      ManagerData has no risk-disposition field. The macro Match Urgency
      formula (U = tanh(-K * delta_score * time_ratio^2 + risk_profile))
      needs one per manager, so ManagerDirector._compute_risk_profile()
      derives it at bind() time from ManagerData.tempo and
      pressing_intensity (both already-existing 0..1 sliders), adjusted by
      the Pragmatist(4)/HotHead(1)/Volatile(256) trait bits, then clamps to
      [-0.35, 0.35]. Do not add a new @export risk_profile field to
      ManagerData for this — it would require touching every authored .tres
      resource, generate_db.py, and verify_db.py for a value that is fully
      recoverable from fields that already exist.
    rationale: >
      Read shared/ManagerData.gd in full before wiring the macro urgency
      architecture (POWERFOOTBALL_MASTER_VISION.md / the 2D Football Engine
      Architecture Plan PDF) — the plan's own illustrative ManagerDirector
      sample simply declares `@export var manager_risk_profile: float`, which
      does not exist anywhere in this repo and would be a schema-widening
      change disproportionate to what the value needs to represent.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

