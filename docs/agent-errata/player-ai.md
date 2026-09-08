# Player AI & Spatial Navigation Errata

**Simulation Layer:** Layer 2 — Match AI & Spatial Navigation  
**Primary Modules:** `entities/player/PlayerBrain.gd`, `autoloads/MatchWorldModel.gd`, `shared/PassUtilityScorer.gd`, `shared/FormationAnchorMath.gd`

This page documents historical bugs, unexpected emergent behaviors, utility-scoring gotchas, and spatial navigation deadlocks encountered within the player tactical AI and decision loop.

---

## Table of Contents
### Discovered Rules
- [press-trigger-needs-time-backstop](#press-trigger-needs-time-backstop)
- [loose-ball-anchor-clamp-deadlock](#loose-ball-anchor-clamp-deadlock)
- [maintain-formation-floor-freezes-ball-carrier](#maintain-formation-floor-freezes-ball-carrier)
- [bresenham-threat-shadowed-real-lane-check-match-wide](#bresenham-threat-shadowed-real-lane-check-match-wide)
- [loose-ball-max-dist-cap-also-needed-a-bypass](#loose-ball-max-dist-cap-also-needed-a-bypass)
- [chase-radius-crushes-legal-loose-ball-chase-score](#chase-radius-crushes-legal-loose-ball-chase-score)
- [arrive-radius-strands-correct-chase-decision](#arrive-radius-strands-correct-chase-decision)
- [find-space-outscores-chase-on-loose-ball](#find-space-outscores-chase-on-loose-ball)
- [sacchi-force-cancels-urgent-ball-actions](#sacchi-force-cancels-urgent-ball-actions)
- [possessor-can-chase-own-ball](#possessor-can-chase-own-ball)
- [defender-marking-was-uncoordinated-and-boundary-clamp-already-existed](#defender-marking-was-uncoordinated-and-boundary-clamp-already-existed)
- [cpu-players-never-gated-into-tackle-state](#cpu-players-never-gated-into-tackle-state)

### Error Logs
- [ERR-20260830-01](#err-20260830-01)

---

## press-trigger-needs-time-backstop

```yaml
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
```

## loose-ball-anchor-clamp-deadlock

```yaml
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

## maintain-formation-floor-freezes-ball-carrier

```yaml
- id: maintain-formation-floor-freezes-ball-carrier
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
    invariant: >
      _score_maintain_formation() returned a flat 0.20 baseline regardless of
      ctx.is_possessor, unlike its sibling _score_find_space() (which already
      guards `if ctx.is_possessor: return 0.0` — "getting back into shape" is
      an off-ball concept for both). evaluate_tactical_action()'s stated
      safety net ("if the ball carrier has zero viable offensive options,
      force a desperation clearance rather than freezing in possession")
      only fires when max(s_pass, s_dribble, s_shoot) <= 0.05 — but
      MaintainFormation's 0.20 floor sits well above that threshold. Any
      possessor with no legal pass target (_find_best_pass_target() null,
      common once a pass is intercepted mid-pitch with no one yet repositioned)
      and only a weak-but-nonzero AttemptDribble score (routine under any real
      marking pressure or below-average aggression: base = eff_aggression*0.55,
      further cut by pressure*(1-composure)*0.50 and stamina_ratio, and by
      0.40x again if a set defender is facing them) lands in the 0.05-0.20
      gap: not low enough to trigger PanicClear, but lower than
      MaintainFormation. MaintainFormation wins evaluate_tactical_action()'s
      max-score comparison outright, current_action becomes
      &"MaintainFormation", and _steer_for_action() seeks the player's
      formation_anchor — near-zero movement_intent for a carrier already
      close to their anchor. The player stands still holding the ball
      indefinitely; nothing else ever re-triggers a re-evaluation because
      current_action never changes and no possession-change event fires
      (the carrier still has the ball). Any other action-scoring function
      that has a nonzero baseline "safe default" score must be audited for
      the same possessor-conditioned floor problem before being added.
    rationale: >
      User reported (after the loose-ball and kickoff-restart fixes above
      were confirmed live, via [PassScorer]/[KickoffAim] instrumentation
      request that turned out to need a follow-up repro) a new, distinct
      symptom in the same CPU-vs-CPU match: an opposing player intercepted a
      dribble, regained it cleanly, then ~10 seconds later a player stood
      still holding the ball doing nothing. Traced by hand-computing
      evaluate_tactical_action()'s five action scores for a plausible
      no-open-teammate, moderately-marked carrier: _score_pass=0.0 (no
      target), _score_dribble in the 0.05-0.20 range depending on aggression/
      pressure/composure, _score_shoot=0.0 (out of range), and
      _score_maintain_formation=0.20 flat — MaintainFormation wins by
      construction whenever dribble lands under its 0.20 floor, which the
      existing <= 0.05 PanicClear fallback was never positioned to catch.
      This sandbox has no Godot binary (see godot-47-core.md), so this was
      derived from the scoring formulas themselves rather than a captured
      log; documented here as a hypothesis-turned-fix rather than
      log-confirmed, unlike the ball-struck-signal-arg-count-mismatch entry
      above.
    resolution: >
      Added `if ctx.is_possessor: return 0.0` to the top of
      _score_maintain_formation(), mirroring the existing guard on
      _score_find_space(). A possessor's best_score now floors at whatever
      Pass/Chase/Dribble/Shoot legitimately score, so the <= 0.05
      PanicClear fallback catches every truly-no-good-options carrier as
      originally intended, and any real-but-weak Pass/Dribble/Shoot score
      is acted on instead of losing to a formation-holding no-op.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## bresenham-threat-shadowed-real-lane-check-match-wide

```yaml
- id: bresenham-threat-shadowed-real-lane-check-match-wide
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - autoloads/MatchWorldModel.gd
    invariant: >
      MatchWorldModel.is_passing_lane_open() opened with an unconditional
      `return get_bresenham_threat(start_pos, end_pos, passer_team_id) <= 100`
      as its FIRST statement, making every line below it — the documented,
      geometric point-to-segment corridor check against `corridor_width` (the
      function's own doc comment: "Performs an analytical point-to-segment
      distance / vector projection check") — permanently unreachable dead
      code. The `corridor_width` / PASS_LANE_CLEARANCE parameter every one of
      the 3 call sites in PlayerBrain.gd tunes was therefore silently
      ignored match-wide. get_bresenham_threat() (used from nowhere else —
      confirmed by a full-repo grep) instead summed `_update_tactical_grid()`
      influence values along a coarse 12x8-cell (~133x112px/cell) Bresenham
      walk and compared against a magic `100` threshold, but that grid's
      influence magnitudes are ~1000 at a player's own cell and ~700 at each
      orthogonally-adjacent cell (I_BASE=1000, K_D=300/manhattan-cell). Any
      opponent within ~2 of these large cells of the passing lane trivially
      pushes the sum into the thousands, so is_passing_lane_open() returned
      false for nearly every candidate in any realistic 11v11 spacing — not
      a kickoff-specific bug. This made _find_best_pass_target() (and
      _is_pass_plan_still_valid(), and the channel-run candidate check
      around PlayerBrain.gd:1503) return null far more often than intended
      throughout the whole match, which independently explains a large share
      of both the kickoff mis-pass symptom (kickoff-backward-pass-veto-
      starves-taker, angle-dot-vs-stale-facing fix above) and the
      MaintainFormation freeze (maintain-formation-floor-freezes-ball-carrier
      above) — a possessor with open_teammate_exists almost always false has
      _score_pass pinned at 0.0 nearly every tick regardless of any other
      fix. Any future performance-motivated rewrite of a spatial query must
      not leave the old, doc-correct implementation dead-coded below a
      shortcut `return` — delete superseded code, never shadow it.
    rationale: >
      Confirmed live via the user's Output-panel paste: after the
      angle-dot-vs-stale-facing fix above, [KickoffAim] still logged
      pass_target=null for PlayerA_LW at the true kickoff centre spot
      (0,0) — but critically, ZERO [PassScorer] per-candidate lines ever
      printed, even with debug_log_pass_scores forced true across the whole
      candidate loop. Since allow_backward_pass=true already bypasses the
      only other continue in that loop (the composure-gated veto), the only
      remaining rejection point that could silence literally all ~9-10
      teammate candidates before the print statement is the
      is_passing_lane_open() call — traced from there down to the dead
      early-return. This sandbox has no Godot binary (godot-47-core.md), so
      the influence-magnitude math above (not a captured runtime log) is
      what confirms `<= 100` was never a viable threshold for this grid's
      actual value range, rather than merely a plausible theory.
    resolution: >
      Deleted the erroneous `return get_bresenham_threat(...) <= 100` line,
      restoring the geometric corridor-check (spatial grid bounding box +
      UtilityMath.is_lane_blocked() point-to-segment distance, verified
      correct by inspection: clamped projection parameter t, ±0.05 segment
      tolerance, squared-distance clearance comparison) as the sole,
      reachable implementation. Also deleted get_bresenham_threat() itself
      (confirmed zero remaining callers) rather than leave it as dead code.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## loose-ball-max-dist-cap-also-needed-a-bypass

```yaml
- id: loose-ball-max-dist-cap-also-needed-a-bypass
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
    invariant: >
      The loose-ball-anchor-clamp-deadlock fix above only exempted a
      possessor-less ball from the ANCHOR-RELATIVE clamp
      (clamp_chase_target()) at the tail of _should_chase_ball() — it did not
      account for the separate, earlier ABSOLUTE range cap
      (`if my_dist_sq > max_dist * max_dist: return false`, max_dist =
      role_config.max_chase_distance, e.g. 260px for a defender, 320px
      midfielder, 380px attacker) that runs unconditionally before the
      `ball.possessor == null` bypass is ever reached. A loose ball that
      comes to rest farther than EVERY eligible player's own role max_dist —
      plausible on a full-size pitch once players are appropriately spread
      across their zones, not just immediately after a kickoff tap — still
      makes _should_chase_ball() return false for all 22 players via this
      earlier check alone, reproducing the exact same freeze the original
      fix targeted, just gated by absolute range instead of anchor-relative
      range. Any future loose-ball exemption must be checked against BOTH
      gates in this function (and any other role-eligibility gate added
      later), not just whichever one the original bug report happened to hit.
    rationale: >
      User confirmed via live play (screenshot + [PassScorer]/[KickoffAim]
      Output panel text) that the kickoff-restart pass-target fixes above
      (angle-dot-vs-stale-facing, bresenham-threat-shadowed-real-lane-check)
      fully resolved the kickoff mis-pass — PlayerA_CM correctly found
      PlayerA_RB as a real backward pass target (total=0.867) and kicked off
      in the right direction. But the "ball sits unclaimed with nobody
      acting on it" symptom recurred independently, later in the same match,
      with the ball resting in open space between clusters of players. Since
      the bresenham-threat fix already resolved the passing-lane starvation
      that could otherwise explain a stuck possessor, and this ball was
      genuinely loose (no possessor) rather than held, the only remaining
      candidate in _should_chase_ball() was the max_dist cap sitting before
      the existing loose-ball bypass — confirmed by re-reading the function
      end to end. This sandbox has no Godot binary (godot-47-core.md), so
      this is a code-trace conclusion drawn from the reported symptom shape
      matching the known gap in the function's control flow, not a captured
      log of this specific decision.
    resolution: >
      Introduced `var is_loose: bool = ball.possessor == null` immediately
      before the max_dist check, changed that check to
      `if not is_loose and my_dist_sq > max_dist * max_dist: return false`,
      and reused `is_loose` (rather than re-reading ball.possessor) at the
      existing anchor-clamp bypass further down. The role-budget
      closer-count loop between the two still applies unchanged, so only
      the single closest eligible player per role breaks off for a distant
      loose ball — this does not send the whole team roaming, matching the
      original fix's stated scope.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## chase-radius-crushes-legal-loose-ball-chase-score

```yaml
- id: chase-radius-crushes-legal-loose-ball-chase-score
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
    invariant: >
      _should_chase_ball() being legal for a loose ball (after both fixes
      above) does not by itself make evaluate_tactical_action() pick
      ChaseBall — that only decides which action wins evaluate_
      tactical_action()'s max-score comparison, and _score_chase()'s own
      formula was untouched by either fix. Its `prox` term clamps to 0.0 the
      instant ctx.dist_to_ball exceeds CHASE_RADIUS (220px) — a constant
      tuned for contesting a ball an OPPONENT still controls nearby, far
      smaller than the 260-380px role max_chase_distance values, and smaller
      still than the now-unlimited loose-ball range. With prox=0, the only
      remaining term is eff_aggression*0.30 (~0.1-0.2 typical), which
      _score_maintain_formation's anchor-urgency term (up to 0.55 for a
      player far from anchor with team_has_ball false, both true for this
      exact scenario) reliably outscores — so MaintainFormation kept winning
      even with ChaseBall legally available, re-freezing the identical
      "ball sits, nobody moves" symptom through a third, independent gap in
      the same decision chain. Any score formula that reads ctx.dist_to_ball
      or a similarly tight proximity radius must be checked against a loose
      ball's now-unbounded legal chase range, not just the legality gate
      that feeds ctx.chase_is_legal.
    rationale: >
      User confirmed via a second live repro (screenshot, ball motionless in
      open space, same shape as the first report) that the max_dist-cap fix
      above did not resolve the freeze, and explicitly asked for more
      debugging tooling rather than another blind guess. Traced downstream
      from ctx.chase_is_legal (now true per the prior fix) into
      _score_chase()'s own formula, since legality and score are two
      separate gates in this codebase's utility-AI pattern and only the
      first had been fixed. This sandbox has no Godot binary
      (godot-47-core.md); the magnitude comparison (prox-crushed ~0.1-0.2 vs
      MaintainFormation's up to 0.55) is a code-trace conclusion, not a
      captured decision log — the newly-added debug_log_action_scores flag
      (see resolution) exists specifically so the next report of this class
      can be confirmed from real numbers instead.
    resolution: >
      _score_chase() now floors `prox` at 1.0 whenever ball.possessor ==
      null (a loose ball), bypassing the CHASE_RADIUS falloff entirely
      rather than recalculating it against a different radius — legality
      already narrowed this to the single correct player, so proximity
      inside that decision has already done its job. Also added
      PlayerBrain.debug_log_action_scores (mirrors the existing
      debug_log_pass_scores pattern): when true, evaluate_tactical_action()
      prints every action's score (maintain/panic/pass/chase/space/dribble/
      shoot) plus the winner and key context flags
      (is_possessor/team_has_ball/chase_legal/open_teammate/dist_to_ball) on
      every decision tick for that player. Toggle it at runtime from the
      Godot editor's Remote scene tree Inspector on a specific stuck
      player's PlayerBrain node — no rebuild needed — for any future
      decision-layer bug report.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## arrive-radius-strands-correct-chase-decision

```yaml
- id: arrive-radius-strands-correct-chase-decision
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
    invariant: >
      _steer_for_action()'s very first check — `if distance <= ARRIVE_RADIUS:
      return Vector2.ZERO` (ARRIVE_RADIUS=24px) — zeroed movement_intent
      unconditionally for EVERY current_action once the seek_target got
      close, including ChaseBall, PanicClear and AttemptShoot, whose
      seek_target is the ball's own position (_cached_intercept / ball.
      global_position directly). This is correct for smoothly settling into
      a stationary FORMATION anchor or a PASS receiving position — overshoot/
      jitter there is undesirable and "arrived" genuinely means "close
      enough" — but wrong for those three ball-seeking actions, where
      "arrived" has to mean "touching the ball" (entering the much smaller
      foot-sensor radius) to actually trigger possession pickup or a kick.
      A player who correctly wins the ChaseBall/PanicClear/AttemptShoot
      comparison in evaluate_tactical_action() but is stopped 21-24px short
      gets permanently zero movement_intent every subsequent tick — distance
      never changes once velocity has decayed to zero, so this is a stable,
      non-recovering equilibrium, not a transient wobble. Any future
      seek-target consumer that targets the ball's exact position (not a
      formation/passing-lane point) must be exempted from this generic
      arrival cushion, or must accept a much tighter radius than 24px.
    rationale: >
      User confirmed via the automatic stall watchdog (see
      chase-radius-crushes-legal-loose-ball-chase-score above, added
      specifically to gather this kind of evidence without further blind
      fixes) that all three prior chase-related fixes were working exactly
      as intended: PlayerB_CB1's [ActionScorer] trace showed chase=0.802
      decisively beating maintain=0.209, chase_is_legal=true, and
      current_action correctly resolved to ChaseBall — yet the player still
      never moved, at only dist_to_ball=21.2px. Since the DECISION layer was
      now empirically confirmed correct, the remaining bug had to be in
      translating current_action into movement_intent — traced directly to
      _steer_for_action()'s arrival cushion, whose 24px radius comfortably
      exceeds the observed 21.2px stall distance. This sandbox has no Godot
      binary (godot-47-core.md), so the exact match is drawn from the
      captured [ActionScorer] numbers plus static confirmation of
      ARRIVE_RADIUS's value, not a second captured trace of the fix itself.
    resolution: >
      Added `var must_reach_ball: bool = current_action == &"ChaseBall" or
      current_action == &"PanicClear" or current_action == &"AttemptShoot"`
      and changed the early-return guard to
      `if distance <= ARRIVE_RADIUS and not must_reach_ball: return
      Vector2.ZERO`. Pass/AttemptDribble/MaintainFormation/FindSpace all
      keep the original cushion unchanged — only the three actions whose
      seek_target IS the ball itself bypass it, and the existing minimum
      0.35 deflection floor a few lines below already prevents the seek
      force from collapsing to zero at very short range once this guard no
      longer exits early.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## find-space-outscores-chase-on-loose-ball

```yaml
- id: find-space-outscores-chase-on-loose-ball
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
    invariant: >
      _team_has_ball() (feeding ctx.team_has_ball) is purely last-touch-based
      — `ball.last_touched_by.team == player.team` — with no awareness of
      whether the ball is currently loose. It stays true even once the ball
      has gone fully dead and unclaimed in open space, as long as this
      player's own team touched it last. _score_find_space() only gated on
      `not ctx.team_has_ball`, so a fast/visionary off-ball attacker's
      FindSpace score (up to ~0.8 for high vision/stamina) could comfortably
      outscore ChaseBall's for the SAME player who was legally the closest
      eligible chaser to that stalled ball (chase-radius-crushes-legal-
      loose-ball-chase-score above already made chase score correctly high,
      ~0.3 here, but FindSpace scored higher still) — sending them running
      further into space instead of winning the ball back. Any future score
      function gated only on ctx.team_has_ball must independently consider
      whether the ball is actually loose (ball.possessor == null) before
      assuming "my team has continuous possession, act accordingly" — that
      assumption silently breaks the instant a loose/dead ball enters the
      picture, regardless of who touched it last.
    rationale: >
      User confirmed via the new possession/stall watchdog trace: PlayerA_ST,
      35.7px from a stalled, unpossessed ball, had chase_legal=true and
      chase=0.297 (correctly boosted by the earlier chase-radius fix) but
      space=0.676 — FindSpace won outright and current_action resolved to
      &"FindSpace", producing the reported "jogs slowly, does nothing"
      symptom (intent_len=0.04, vel_len=0.0). This sandbox has no Godot
      binary (godot-47-core.md); the fix is drawn directly from this
      captured trace's own numbers, not from re-derived math.
    resolution: >
      Added a guard to _score_find_space(): `if ctx.chase_is_legal and ball
      != null and ball.possessor == null: return 0.0` — placed after the
      existing team_has_ball check, so a genuinely different teammate (for
      whom chase is NOT legal, e.g. a second attacker outside their role
      budget) can still score a legitimate supporting run while the
      designated chaser goes to win the ball. _team_has_ball() itself was
      deliberately left unchanged — it has ~7 call sites across formation-
      phase and other tactical logic that could not be verified without a
      running engine, so a narrow fix at the one confirmed call site was
      judged lower-risk than redefining team_has_ball's semantics globally.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## sacchi-force-cancels-urgent-ball-actions

```yaml
- id: sacchi-force-cancels-urgent-ball-actions
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
    invariant: >
      _steer_for_action()'s "Sacchi compactness" force (pulls a player back
      toward their team's X centre-of-mass once the team's attacker-to-
      defender X spread, L_team, exceeds 340px) was summed unguarded into
      raw_intent for EVERY current_action, including ChaseBall/PanicClear/
      AttemptShoot — unlike sep_force and line_lateral_force a few lines
      above it in the same function, which are already explicitly excluded
      for exactly those three actions ("so chasers aren't pushed off the
      intercept line"). sacchi_force's magnitude formula
      (`-K_sacchi(0.0025) * (L_team-340)^2`, then `/100.0`, clamped to
      [-1,1]) reaches its FULL clamped magnitude at only 200px of excess
      spread (L_team=540px total) — a routine amount of stretch during any
      transition or counter-attack on this project's pitch size, not a rare
      edge case. Because raw_intent is a simple vector sum before a single
      final `.limit_length(1.0)` clamp, a maxed-out sacchi_force pointing
      opposite an active ChaseBall seek_force can nearly fully cancel it
      even when the seek_force itself was computed correctly and strongly.
      Any future steering force added to this blend must be checked against
      the same "does this make sense added to an active
      ChaseBall/PanicClear/AttemptShoot seek" question before being left
      unguarded — an ambient shape-keeping nudge should never be able to
      override a decisive, already-legal ball-seeking action.
    rationale: >
      User's [Steer] trace (the instrumentation added specifically for this
      class of report) showed it directly, not inferred: seek=
      (-0.792728, -0.04979) (a correct, strong pull toward the ball,
      deflection=0.79) summed with sacchi=(1.0, 0.0) (maxed out, opposite
      X-direction) produced raw_intent=(0.057311, -0.046385) — length 0.07,
      functionally zero, despite ChaseBall being the correctly-chosen,
      correctly-scored action (chase=0.471, decisively above maintain=
      0.169). User separately reported the ball going out for a throw-in
      "looks and feels like a panic clear" and rash-feeling decisions
      generally — this specific trace is from a different moment (the stall
      watchdog, not that exact throw-in incident) so it is not proven to be
      THE cause of that specific incident, but it is a confirmed, general
      contributor to erratic/diluted movement across ball-seeking actions
      match-wide, found via the same tooling built to investigate exactly
      this class of report.
    resolution: >
      Added `applies_to_ball_actions` (current_action not in
      {ChaseBall, PanicClear, AttemptShoot}) as an additional guard on the
      existing role check before computing sacchi_force at all — mirrors
      the sep_force/line_lateral_force pattern already established a few
      lines above in the same function. sacchi_force keeps its exact
      existing magnitude/formula for MaintainFormation, FindSpace,
      AttemptDribble and Pass; only the three ball-seeking actions are now
      exempt, matching the existing off-ball-only convention rather than
      introducing a new one.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## possessor-can-chase-own-ball

```yaml
- id: possessor-can-chase-own-ball
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
    invariant: >
      _should_chase_ball() (and therefore _score_chase()) had no exclusion
      for `ball.possessor == player` — a player who already has the ball.
      Every sibling score function already guards this case
      (_score_find_space: `if ctx.is_possessor: return 0.0`;
      _score_maintain_formation: same; _score_dribble/_score_shoot: `if not
      ctx.is_possessor: return 0.0`; _score_pass: `if not ctx.is_possessor:
      return 0.0`) but _score_chase() never got the equivalent guard. Since
      a possessor is, by construction, standing right next to their own
      ball, _score_chase()'s proximity term (`prox = 1.0 - dist/
      CHASE_RADIUS`) scores them very highly essentially always — observed
      live at chase=0.709 and chase=0.740 across two consecutive decision
      ticks for the SAME possessing player — comfortably beating Pass
      (0.039, 0.000), Dribble (0.159, 0.016), and everything else nearly
      every tick. ChaseBall's seek_target for a possessor is
      _predict_intercept_position() on their OWN ball, which — since they
      are the one carrying it — closely tracks their own current position,
      producing reactive, small, non-purposeful movement rather than the
      forward/space-seeking runs AttemptDribble would produce, and
      systematically starving Pass of the chance to ever be chosen. Any
      future addition to evaluate_tactical_action()'s scored actions must be
      checked against ctx.is_possessor before being trusted to behave
      sensibly for a player who already has the ball — chase is the second
      confirmed omission of this pattern this session (after
      find-space-outscores-chase-on-loose-ball, which was the inverse case:
      an off-ball score not accounting for a ball state it should have).
    rationale: >
      User reported the AI is much improved after the prior session's fixes
      but still "huddles up like a rugby scrum, no sense of space or trying
      to create space" and is "extremely reluctant to pass." User's own
      [ActionScorer] log, pasted unprompted, showed the mechanism directly:
      PlayerB_CB1 with possessor=true picked ChaseBall at chase=0.709/0.740
      across two ticks while pass=0.039/0.000 — a possessor essentially
      never getting to try Pass, exactly matching "reluctant to pass," and
      chasing-not-advancing exactly matching "no sense of space." This
      sandbox has no Godot binary (godot-47-core.md); root-caused directly
      from the pasted trace's own possessor=true/chase=high/pass=low
      juxtaposition, cross-checked against every sibling score function's
      existing is_possessor handling to confirm chase was the outlier.
    resolution: >
      Added `if ball.possessor == player: return false` as the first
      substantive check in _should_chase_ball() (after the existing
      null-guard), before any of the role-budget/max_dist/anchor-clamp
      logic runs. A possessor now scores 0.0 on ChaseBall via the existing
      `if not ctx.chase_is_legal: return 0.0` gate in _score_chase(),
      letting Pass/AttemptDribble/AttemptShoot compete on their own actual
      merits instead of losing to an artificially-inflated proximity score
      every tick.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## defender-marking-was-uncoordinated-and-boundary-clamp-already-existed

```yaml
- id: defender-marking-was-uncoordinated-and-boundary-clamp-already-existed
    discovered_date: 2026-09-01
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/PlayerBrain.gd
      - shared/FormationAnchorMath.gd
    invariant: >
      A third externally-authored "[TARGETED EDIT]" prompt (scoped to
      FormationAnchorMath.gd + PlayerBrain.gd, greedy marking + anchor
      boundary clamping) had one task that was real and one that was already
      done. Real: _find_nearest_threatening_opponent() was, and had always
      been, purely local — every OUTFIELD_DEFENDER independently picked its
      own nearest opposing OUTFIELD_ATTACKER with zero coordination, so
      several defenders could converge on the same threat while another went
      unmarked (the DefensiveDuty enum even has a MARKING case whose own
      comment admits "Reserved fallback label — currently folded into
      RETREAT's target" — never wired up). Already done:
      FormationAnchorMath.get_dynamic_anchor_position() already clamps both
      axes to [-1,1] normalized pitch-half space unconditionally at the end
      of the function (pulled_norm.x/.y both go through clampf(...,-1.0,1.0)
      before the pitch_centre + pulled_norm*half conversion back to world
      space) — the clamp is not inside any of the three TeamPhase branches,
      so it already applies identically across IN_POSSESSION/
      OUT_OF_POSSESSION/TRANSITION. FormationAnchorMath.gd is only 109 lines
      total, all in this one function — there was nowhere else a per-phase
      unclamped path could hide. Confirmed empirically, not just by reading:
      fuzz_formations.py --iterations=50000 reports 0 boundary violations
      and 0 line inversions with FormationAnchorMath.gd completely untouched
      this session.
    rationale: >
      Third occurrence of this pattern across this prompt batch (Phase
      1's stamina system, Phase 2's xT/possession-timer prompt) — a task
      list generated from an architecture doc without reading the actual
      repo state will describe both real gaps and already-shipped work in
      the same confident voice, with no signal distinguishing them. Read the
      target file fully (109 lines here — cheap) before trusting either
      claim.
    resolution: >
      FormationAnchorMath.gd: untouched, zero diff — task was already
      satisfied. PlayerBrain.gd: added a team-wide greedy bipartite marking
      pass (_recompute_team_marking()), deliberately the greedy
      approximation named in the prompt's own invariant rules (NOT Hungarian
      — O(A^2 + A*D) <= 121+121 fixed comparisons over pre-sized static
      PackedInt32Array/PackedByteArray/PackedFloat32Array scratch, zero
      per-call allocation). Threat term reuses UtilityMath.get_xt_value()
      (added for the previous prompt in this batch) rather than inventing a
      parallel "threat" metric — the receiver-zone danger score xT already
      is is exactly what "threat" means here. Cost formula's dist_sq/
      goal_dist_sq terms are normalized against pitch_size-derived
      references before the prompt's literal 0.5/0.3/0.2 weights are
      applied — as given (raw px^2 against a 0.2-weighted 0..1 threat term)
      the threat term would have been numerically inert, tens-of-thousands
      vs low single digits, silently defeating the stated goal of favouring
      high-threat assignments. Coordination/staleness: the assignment is
      genuinely team-wide (which no single PlayerBrain instance's own state
      can hold), so it lives in a `static var` shared across every PlayerBrain
      instance (same category of pattern as HeavyPlayerController's
      static _auto_index counter, ai-architect.md) rather than in
      MatchWorldModel — the prompt's own file scope named only
      FormationAnchorMath.gd + PlayerBrain.gd, not MatchWorldModel.gd, so
      this stayed inside that boundary. Recompute is gated by a per-team
      last-recompute-tick check (_maybe_recompute_team_marking(),
      MARKING_REASSIGN_INTERVAL_TICKS=15 match ticks) so the whole team's
      O(A^2+A*D) pass runs roughly once per cadence window rather than once
      per defender (5-6x redundant otherwise, since every defender's own
      decision tick would otherwise independently trigger an identical
      recompute). Wired into the ONE existing consumer,
      _find_nearest_threatening_opponent(), which now prefers the
      coordinated assignment and falls back to the old local nearest-pick
      only when no assignment exists yet — this automatically fixes its
      three existing call sites (_resolve_defensive_duty(),
      _cover_shadow_target() via _find_open_space_target(), and
      _find_open_space_target()'s own direct use) without touching any of
      them individually. Confirmed every call site sits inside
      evaluate_tactical_action()'s existing (_frame_counter + player_index)
      % current_cadence decision-tick gate (none are reached from
      per-frame _steer_for_action()) before relying on that gate to satisfy
      "executed exclusively on the 15-frame AI decision stagger" — note
      current_cadence is actually a dynamic 8/20/45 depending on ball
      proximity, not a literal constant 15, despite that being the
      project-wide shorthand every doc (including this file) uses for "the
      decision-tick gate"; did not change that naming or behaviour, out of
      scope for this task. gdcheck + full lint suite (verify_gate.py --fast)
      and the prompt-specified check (fuzz_formations.py --iterations=50000)
      pass: 0 boundary violations, 0 line inversions.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## cpu-players-never-gated-into-tackle-state

```yaml
- id: cpu-players-never-gated-into-tackle-state
    discovered_date: 2026-09-01
    discovered_by: Claude
    category: ai
    target_files:
      - entities/player/HeavyPlayerController.gd
      - entities/player/PlayerState.gd
      - entities/player/PlayerBrain.gd
    invariant: >
      PlayerState.check_common_transitions()'s only gate into TACKLE was
      wants(player, &"action_tackle"), and PlayerState.wants() unconditionally
      returns false for any not player.is_user_controlled. A repo-wide grep
      confirmed action_tackle has no other reference anywhere, so TackleState
      was structurally unreachable for every CPU player — the only defensive
      mechanism CPU-vs-CPU play had was the foot-sensor steal covered by
      dribble-claim-ignores-existing-possessor-dual-driver-jitter, which is
      costless and silent, not a real challenge. HeavyPlayerController now
      exposes a third brain-intent channel, wants_tackle (mirroring the
      existing wants_sprint convention: human input read directly where
      consumed, CPU intent pre-written by PlayerBrain each physics tick),
      which check_common_transitions() ORs into the same TACKLE gate.
      PlayerBrain._should_attempt_tackle() (called every physics tick from
      _steer_for_action(), which already runs every frame regardless of the
      15-frame-equivalent decision stagger — see ai-architect.md) commits only
      when current_action == &"ChaseBall" (reusing every existing role-budget/
      anchor-clamp/loose-ball gate that already decides this is a legal,
      worthwhile chase), the ball is held by an opposing HeavyPlayerController
      (never a teammate, never a loose ball), the defender is within
      TACKLE_ATTEMPT_RANGE, and already clears TackleState.MIN_FACING_DOT —
      the same facing threshold TackleState itself re-checks at the moment of
      contact, so the AI's "is this worth attempting" question is exactly
      "would I actually pass TackleState's own check," not an independently-
      tuned duplicate. current_action is not reset when TackleState is
      entered (nothing in TackleState.gd touches it), so without
      TACKLE_ATTEMPT_COOLDOWN a defender whose ChaseBall/proximity/facing
      conditions still hold the instant a miss's RECOVERY window ends
      (routine — a miss typically leaves the tackler still close to and
      facing the dribbler) would re-lunge every ~0.73s indefinitely — any
      future reflex wired into _steer_for_action() the same way must consider
      whether current_action can go stale across the FSM state it triggers,
      the same trap this one required a cooldown to avoid.
    rationale: >
      User explicitly requested CPU players get real tackling routed through
      the existing TackleState rather than a new synchronous side-channel
      (unlike Pass/PanicClear/AttemptShoot, which _steer_for_action() already
      executes directly via ball.apply_kick(), bypassing ChargeKickState/
      ShotLockState entirely for CPU players — that precedent was considered
      and rejected here specifically because it would have discarded
      TackleState's windup/contact-window/foul-risk contest instead of
      reusing it). Confirmed TackleState._try_win_ball()/_check_mistimed_foul()
      never reference is_user_controlled (input-agnostic, safe to reuse
      as-is). Read PlayerBrain.evaluate_tactical_action() and
      _should_chase_ball() in full (independently, via a dedicated Plan
      sub-agent validation pass) to confirm current_action == &"ChaseBall" is
      a sound trigger: it is already the established mechanism for closing
      down an opponent's held ball (_score_chase()'s own comment: CHASE_RADIUS
      is "tuned for contesting a ball an OPPONENT still controls nearby"),
      correctly excludes a loose ball (ball.possessor == null fails the `as
      HeavyPlayerController` cast used for the opposing-team check), and
      inherits every documented press-trigger/loose-ball/chase-radius fix in
      this file for free since it never re-derives chase legality itself.
      Goalkeepers are structurally excluded (evaluate_tactical_action() never
      returns &"ChaseBall" for is_goalkeeper) — sweeper-keeper tackling is out
      of scope. Confirmed via a project-wide grep of .set_possessor( (4 call
      sites, all passing HeavyPlayerController) that the `as
      HeavyPlayerController` cast on ball.possessor is always safe. This
      sandbox has no Godot binary (godot-47-core.md) — the tackle-spam risk
      and its cooldown fix are derived from tracing current_action's actual
      lifetime across a TackleState commitment, not a captured trace, and need
      live playtest confirmation of tackle frequency/feel.
    resolution: >
      Added wants_tackle (HeavyPlayerController), the check_common_
      transitions() OR clause (PlayerState), and _should_attempt_tackle() plus
      TACKLE_ATTEMPT_RANGE/TACKLE_ATTEMPT_COOLDOWN/_tackle_cooldown
      (PlayerBrain), wired into _steer_for_action() alongside the existing
      wants_sprint assignment. Must ship together with dribble-claim-ignores-
      existing-possessor-dual-driver-jitter: that fix alone removes the only
      dispossession mechanism CPU defenders had, so this entry supplies the
      real replacement in the same change rather than leaving a gap.
    promotion_target: .claude/rules/ai-architect.md
    status: pending
```

## ERR-20260830-01

```yaml
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
```

