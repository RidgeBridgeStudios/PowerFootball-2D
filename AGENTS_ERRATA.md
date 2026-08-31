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

  - id: ball-struck-signal-arg-count-mismatch
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: engine
    target_files:
      - entities/player/MoodSystem.gd
      - ui/HUD.gd
      - entities/referee/MatchReferee.gd
      - pitch/PitchScene.gd
      - pitch/PenaltyShootoutCoordinator.gd
      - entities/manager/ManagerDirector.gd
    invariant: >
      Confirmed live (user-provided Godot Output log, not just static
      analysis) that Godot 4.7 raises "Error calling from signal '<name>' to
      callable: ... Method expected N argument(s), but called with M" on
      every single emission for a connected callback that declares fewer
      parameters than the signal currently emits. This directly falsifies
      the prior ai-architect.md claim that Godot silently drops unwanted
      trailing args — that claim was written from assumption, never run,
      per godot-47-core.md's "no engine in this container" note.
      MoodSystem._on_ball_struck() still declared 3 params after
      ball_struck gained a trailing is_shot: bool, so it errored on every
      kick in the match (dozens of times in a single short match) and its
      composure-on-powerful-shot logic silently never ran. The same
      under-declared-handler pattern was found (via a full sweep of every
      GameEvents.<signal>.connect() call against its signal's current
      declared arg count) on goal_scored in six more listeners — HUD.gd,
      MatchReferee.gd, PitchScene.gd (both _on_goal_scored and
      _on_practice_goal_scored), PenaltyShootoutCoordinator.gd, and
      ManagerDirector.gd — none yet triggered in the reported freeze only
      because no goal had been scored in the test matches. Whenever a
      trailing parameter is added to an existing GameEvents signal, grep
      every `GameEvents.<signal>.connect(...)` call and update every
      connected handler's signature in the same change — a param the
      handler doesn't need can just take a default value (e.g.
      `_scorer: Node = null`).
    rationale: >
      User reported a total CPU-vs-CPU match freeze after kickoff
      (loose-ball-anchor-clamp-deadlock above) that persisted after that fix
      was applied and pulled. Asked the user to paste the Godot Output log
      rather than guess a third blind fix; the pasted log's ~30 repeated
      ChargeKickState.gd:144 / MoodSystem.gd signal errors were the first
      concrete, empirical evidence gathered in this investigation (this
      sandbox has no Godot binary to run the match itself — see
      godot-47-core.md). Fixed on sight since it is unambiguously a real
      bug regardless of whether it is THE freeze cause; a
      [FreezeTrace] diagnostic print (temporary, PlayerBrain.gd,
      DEBUG_FREEZE_TRACE) was left active in the same push in case the
      freeze itself turns out to be unrelated to this signal bug.
    resolution: >
      Added the missing trailing parameter to all 7 under-declared handlers
      (MoodSystem._on_ball_struck, plus 6 goal_scored listeners), verified
      with a full-repo sweep script cross-checking every
      GameEvents.<signal>.connect() call's handler arg count against the
      signal's declared arg count (0 remaining mismatches across 62
      connections checked). Corrected the false claim in
      .claude/rules/ai-architect.md.
    promotion_target: .claude/rules/ai-architect.md
    status: promoted

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

  - id: dribble-magnet-forward-overshoot-oscillation
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: physics
    target_files:
      - entities/player/states/DribbleState.gd
    invariant: >
      DribbleState._apply_magnet()'s position correction
      (`pull_velocity = offset * MAGNET_STRENGTH(55.0)`, blended via
      `lerp(..., MAGNET_BLEND(0.85))`) applied the same full-strength
      correction regardless of WHICH direction the ball had drifted from
      carry_target. A touch (_apply_touch(), firing every 0.10-0.20s) sets
      ball.velocity directly to touch_direction * touch_speed, which reaches
      up to ~340px/s at a sprint (HeavyPlayerController.top_speed=240 *
      sprint_multiplier=1.45 * SPRINT_TOUCH_BONUS=1.15 * effective_touch_
      ratio up to 0.85) — against a carry_target only 16-28px ahead
      (dynamic_offset), routine overshoot within 1-2 frames after any touch.
      When the ball is AHEAD of carry_target (forward_offset < 0, the touch
      doing its job), the uncapped full-strength correction produced a
      near-total velocity reversal within a single MAGNET_BLEND=0.85 step
      (worked example: +340px/s touch velocity -> ~-313px/s pull_velocity
      from a modest 5.7px overshoot -> ~-215px/s post-blend, a ~555px/s
      swing in one frame), which then overshoots the other way and repeats
      every touch cycle (5-10Hz) — a textbook high-gain feedback oscillation,
      not merely "strong magnetism." This reads as the ball visibly
      bouncing/jittering in a small area in front of the dribbler rather
      than smoothly following, and — since ball.velocity feeds directly into
      UtilityMath.calculate_intercept_point() via PlayerBrain.
      _predict_intercept_position() for every OPPONENT computing a
      ChaseBall/PanicClear seek_target against this ball — plausibly
      corrupts other players' interception targets too, compounding into
      the broader "AI looks confused near a dribbler" symptom class,
      distinct from (but likely interacting with) the ai-architect.md chase/
      possession fixes above. MAGNET_STRENGTH and MAGNET_BLEND themselves
      were deliberately, explicitly tuned ("intentionally strong... locks
      onto the target within ~1 frame") and were NOT changed — the fix
      targets the untested emergent interaction between the touch and
      magnet systems, not the documented headline constants.
    rationale: >
      User reported unprompted, mid-debugging-session, that the ball looks
      "unnatural... bouncing up and down and moving about in a very small
      area in front of the dribbler" and suspected it was also confusing the
      AI. Verified possession_changed (fired twice per touch via apply_kick
      -> release_possession() -> set_possessor(null) immediately followed by
      DribbleState re-calling set_possessor(player)) has zero .connect()
      call sites anywhere in the repo, ruling that signal-churn out as the
      visual cause. Derived the touch-vs-magnet oscillation mechanism from
      reading DribbleState.gd's actual constants and HeavyPlayerController's
      real top_speed/sprint_multiplier values (not assumed numbers) rather
      than guessing — per research-index.md and CLAUDE.md's explicit "do not
      guess at physics values, feel parameters" instruction, also checked
      docs/research/PES-6-Gameplay-Physics-Research.txt first (documents a
      different, non-magnet "discrete touch + free RigidBody roll" dribble
      model — not directly prescriptive here since this codebase's own doc
      comments deliberately chose "Sensible Soccer style" magnetism instead,
      but confirms overshoot-then-correction is a known real dribble-physics
      failure mode worth taking seriously). This sandbox has no Godot binary
      (godot-47-core.md) — the fix is a worked-example calculation from real
      constants, not a captured trace, and genuinely needs the user's visual
      confirmation next play session since ball-carry feel cannot be judged
      from source alone.
    resolution: >
      Added FORWARD_OVERSHOOT_SOFTEN=0.20 and split _apply_magnet()'s
      position offset into forward (along carry_dir) and lateral
      (perpendicular) components, mirroring the existing velocity-damping
      decomposition a few lines above. Only a forward offset (ball ahead of
      carry_target — the ball fell BEHIND and needs pulling up) keeps full
      MAGNET_STRENGTH; a backward forward-offset (ball overshot ahead of
      carry_target) is corrected at 20% strength instead. Lateral/reverse
      drift — the actual "turn sharply and the ball runs away from you"
      design intent per DribbleState's own top-of-file doc comment — is
      completely unaffected, still corrected at full strength. Needs live
      playtest confirmation that the visible jitter is actually resolved,
      not just the computed worked example.
    promotion_target: .claude/rules/soccer-physics.md
    status: pending

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

  - id: bicycle-kick-dominates-ambiguous-facing
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: physics
    target_files:
      - entities/player/states/AerialState.gd
    invariant: >
      AerialState._attempt_contact()'s three-way header/volley/bicycle-kick
      branch gated VOLLEY on `facing_goal_dot > 0.0` and BICYCLE KICK on
      `facing_goal_dot <= 0.0` — meaning "not facing goal" (a full 180° arc
      of possible facing directions, including every merely-ambiguous or
      perpendicular orientation, not just a clean back-to-goal read) was
      sufficient for bicycle kick, provided height was in its [5,25] band —
      wider than volley's [10,20] band. HEADER only fired for heights
      entirely outside [5,25], or the narrow facing-goal-but-outside-[10,20]
      sliver — a much smaller effective territory than bicycle kick's for
      any typical throw-in reception height. The course spec
      (docs/course_implementation_specification.md Section 10D) describes
      bicycle kick as triggering when "facing away from target goal" and
      calls it "a spectacular acrobatic kick" — language implying a
      deliberately rare special case, not the routine default outcome for
      any aerial contact where the receiver hasn't already squared up to
      goal (which a throw-in receiver, having just turned in from the
      touchline to meet the ball, routinely has not). Any future aerial-
      contact branch added to this function must require a CLEARLY-oriented
      facing_goal_dot for its special-case variants (matching
      FACING_CLARITY_THRESHOLD), not merely a non-zero lean, or it risks
      the same "the general case rarely wins" failure mode.
    rationale: >
      User reported "the AI almost always attempts a bicycle kick instead
      of a header during throw ins." Read AerialState.gd directly (it does
      exist, despite ROADMAP.md Phase 1 item 8 "AerialState / heading
      resolution" being unchecked — the roadmap checkbox is stale) and
      found the three-way branch's asymmetric trigger-zone sizing described
      above. This sandbox has no Godot binary (godot-47-core.md); the fix
      is a structural/logic correction derived from reading the branch
      conditions themselves against the course spec's stated design intent,
      not a captured trace of a specific throw-in.
    resolution: >
      Added FACING_CLARITY_THRESHOLD=0.2 (matching the existing "clear
      enough to act on" convention already used elsewhere for a facing/
      direction read — PlayerBrain._find_best_pass_target()'s
      forward_dot < -0.2 backward-pass veto — rather than an invented
      value). VOLLEY now requires facing_goal_dot > 0.2 and BICYCLE KICK
      requires facing_goal_dot < -0.2; the resulting neutral band
      (-0.2..0.2) — genuinely ambiguous facing, the common case for a
      throw-in receiver who has just turned in to meet the ball — falls
      through to HEADER regardless of height, restoring it as the true
      default rather than the leftover case. Height bands and power/launch
      values for all three were left completely unchanged.
    promotion_target: .claude/rules/soccer-physics.md
    status: pending

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

  - id: touchline-bubble-is-one-shared-instance-home-perspective-only
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: architecture
    target_files:
      - ui/TouchlineBubble.gd
      - pitch/PitchScene.gd
    invariant: >
      There is exactly one $TouchlineBubble node (a CanvasLayer), not one per
      manager — PitchScene repositions it bottom-left/right per call via the
      `is_home: bool` argument to show_shout(). By established convention
      (see _fire_touchline_goal_shout()'s own comment), the AWAY manager
      never gets a reaction bubble — the touchline shout is deliberately a
      home-perspective-only feature, matching what a player watching their
      own team's dugout would see. Any new touchline-reaction trigger (e.g.
      a momentum-swing shout) must follow this same home-only convention and
      stay routed through PitchScene, which alone holds the ManagerData/
      display-name context TouchlineBubble itself intentionally has none of
      ("Depends on: nothing — driven entirely by show_shout() calls").
    rationale: >
      The architecture plan's illustrative TouchlineBubble sample assumes
      two independent per-team instances, each with its own
      `manager_team_id: int` export and its own GameEvents subscription —
      that shape does not match this repo's actual scene graph or its
      established home-perspective convention, and copying it verbatim
      would have either duplicated the node or broken the away-team-silent
      behavior other systems already rely on.
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
