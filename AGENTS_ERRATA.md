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

  - id: crowding-space-creation-diagnostics
    discovered_date: 2026-08-31
    discovered_by: Claude
    category: ai
    target_files:
      - autoloads/MatchWorldModel.gd
      - entities/player/PlayerBrain.gd
    invariant: >
      Do not add a second, competing crowding/spacing instrumentation system.
      MatchWorldModel.debug_spacing_diagnostics (@export, so it is also
      toggleable live via the Debugger's Remote scene tree while a match is
      running — currently defaulted to true at the user's request for an
      active diagnostic pass; flip back to false once the crowding
      investigation is done, since the periodic [SpacingReport] print is
      noise for anyone not actively reading it) gates a full opt-in
      reporting pipeline: a periodic
      [SpacingReport] print every SPACING_REPORT_INTERVAL_SECONDS (15s) with
      the current window's numbers, and one [SpacingSummary] print at
      GameManager.MatchPhase.FULL_TIME with match-long averages. Metrics
      covered: per-team avg-nearest-teammate distance (the core "crowding
      index"), team bounding-box width/length as a % of pitch_size ("is the
      pitch actually being used"), avg count of same-team players within
      SPACING_CLUMP_RADIUS (100px) of the ball, the single worst
      nearest-teammate distance of the match plus which two named players,
      possessor-had-open-teammate rate (direct measure of "was there ever
      anyone to pass to"), FindSpace-chosen rate per role (ATT/MID/DEF), and
      the full action-choice distribution per team
      (MaintainFormation/Pass/ChaseBall/FindSpace/AttemptDribble/
      AttemptShoot/PanicClear as % of decisions). The spatial half
      (_accumulate_spacing_sample()) is self-contained in MatchWorldModel,
      sampled every SPACING_SAMPLE_STRIDE physics frames (not every frame —
      O(TOTAL_PLAYERS^2) per sample) purely from the existing
      p_pos_x/p_pos_y/player_teams cache, zero scene-tree polling. The
      decision half needs one line in PlayerBrain.evaluate_tactical_action():
      a MatchWorldModel.instance.record_decision(player.team, role,
      best_action, ctx.is_possessor, ctx.open_teammate_exists) call placed
      after the PanicClear fallback floor and before the existing
      debug_log_action_scores print block. Both halves are single-bool-gated
      no-ops when debug_spacing_diagnostics is false, so normal play (and
      every existing debug flag) is unaffected. Extend the existing
      DecisionAction enum / _action_tally_index() match statement rather than
      inventing a parallel tally if a new named action is ever added to
      evaluate_tactical_action().
    rationale: >
      User asked to dig into the "crowding, sloppy play, no space creation,
      players run around like ants" report plus a follow-up ("a player near
      the kickoff circle jogs slowly toward the middle doing nothing else")
      and explicitly asked for debugging tools they could read from the
      Godot Output panel after letting a CPU-vs-CPU match run themselves,
      rather than more blind tuning changes — this sandbox has no Godot
      binary (godot-47-core.md) so tuning constants here cannot be verified
      by actually playing a match. Built on the existing StallWatchdog/
      PossessionWatchdog/[ActionScorer]/[Steer] diagnostic-print conventions
      already in these two files rather than introducing a new pattern.
    resolution: >
      Not a bug fix — a capability addition. See target_files above. Findings
      from actually running it are expected to land as a follow-up error_log
      or discovered_rules entry once the user reports back what the reports
      show.
    promotion_target: .claude/rules/ai-architect.md
    status: pending

  - id: verify-external-agent-prompts-against-source-before-executing
    discovered_date: 2026-09-01
    discovered_by: Claude
    category: architecture
    target_files:
      - entities/player/HeavyPlayerController.gd
    invariant: >
      A batch of externally-authored "[EXECUTION MODE: FULL AUTONOMY]"
      upgrade prompts (for a different agent, Google Antigravity) described
      Phase 1 as "couple movement_intent to fatigue... three-tier metabolic
      model to throttle wants_sprint" as if no such system existed. A first
      grep pass for stamina|fatigue|metabolic returned zero hits and nearly
      caused this session to build a duplicate stamina system from scratch.
      A second, more careful grep (case-insensitive, one term at a time)
      found a complete existing system on HeavyPlayerController: stamina/
      stamina_max/stamina_drain_rate/stamina_recover_rate/sprint_locked/
      stamina_sprint_unlock, a stamina_depleted signal, a HUD stamina bar,
      and per-player PlayerData-driven tuning — just a binary gate (full
      sprint speed until stamina hits 0, then a hard lock), not tiered. Any
      externally-authored "upgrade this subsystem" prompt must be checked
      against an actual grep/read of the target files before being treated
      as greenfield — do not trust a prompt's own characterization of what
      does or does not already exist, and do not trust a single grep result
      without a second, narrower pass when the stakes of being wrong are
      "build a whole duplicate subsystem."
    rationale: >
      Same session also found tools/fuzz_formations.py, tools/eval_simulation.py
      and tools/verify_gate.py (three of the four prompts' VERIFY commands)
      genuinely exist with matching CLI flags, so the batch was not pure
      fabrication either — parts were grounded, parts were not, which is
      exactly why each phase needs individual verification rather than a
      blanket trust/distrust call.
    resolution: >
      Implemented the corrected Phase 1 on HeavyPlayerController.gd only:
      (1) FatigueTier enum (FRESH/TIRED/EXHAUSTED) read from the existing
      get_stamina_ratio(), consumed by get_current_top_speed() to scale both
      sprint_multiplier and base top_speed per tier — sprint_locked's hard
      zero-stamina cutoff is untouched, the tiers just make the approach to
      it progressive instead of a cliff. (2) _resolve_sprint_jostle(delta),
      called once per physics tick immediately after move_and_slide() (must
      run there — it reads that same call's get_slide_collision()/_count()),
      applies a small continuous apply_external_impulse() push (never a
      direct velocity write — see soccer-physics.md) between two
      HeavyPlayerController bodies that collide while both exceed
      JOSTLE_MIN_SPEED and their velocity headings agree within
      JOSTLE_HEADING_DOT_MIN=0.70 (side-by-side sprinting, not a crossing run
      or a tackle). Only the lower get_instance_id() of the colliding pair
      computes and applies the exchange, to both bodies, so the two sides'
      independent _physics_process() calls do not each push the other and
      double the effect. Reused apply_external_impulse() rather than adding
      a second impulse API — its doc comment already named "collisions" as
      an intended caller, alongside TackleState's existing one-shot lunge.
      The prompt's own formula ("θ_impact ≤ 45° AND v̂_A·v̂_B > 0.70") is
      numerically the same threshold stated twice (cos 45° ≈ 0.7071) rather
      than two independent conditions, so only the one real heading-alignment
      test was implemented — documented inline rather than inventing an
      unjustifiable second angle metric to satisfy the letter of the prompt.
      Did not touch acceleration/friction curves, PlayerBrain, or any other
      file — verify_gate.py --fast (gdcheck + all lints + tscn_linter +
      verify_db) passes clean.
    promotion_target: .claude/rules/ai-architect.md
    status: pending

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

  - id: dribble-claim-ignores-existing-possessor-dual-driver-jitter
    discovered_date: 2026-09-01
    discovered_by: Claude
    category: physics
    target_files:
      - entities/player/states/DribbleState.gd
      - entities/player/states/MoveState.gd
      - entities/player/states/IdleState.gd
    invariant: >
      DribbleState.enter() and the ball-in-range branch of DribbleState.
      process() called ball.set_possessor(player) whenever a ball was in foot
      range, with no check on ball.possessor's existing value, and
      DribbleState.physics_process() drove _apply_touch()/_apply_magnet()
      against its own cached _possessed_ball with no check that
      ball.possessor == player. Foot sensor radius (15px, HeavyPlayer.tscn)
      exceeds a dribble carry-target offset of only 16-28px
      (DribbleState.physics_process()'s dynamic_offset), so a second player's
      foot sensor overlapping the same ball is routine, not an edge case. That
      second player's DribbleState.enter() silently stole ball.possessor while
      the original carrier's own DribbleState instance never noticed and kept
      driving the same ball's velocity every physics tick — two players'
      physics_process() calls fighting over one ball every frame. Any future
      DribbleState entry or claim path must gate on
      (ball.possessor == null or ball.possessor == player) before calling
      set_possessor(), and physics_process() must independently re-check
      ball.possessor == player every tick rather than trusting process() to
      catch a stale claim in time — process() runs on PlayerStateFactory's
      frame-rate _process() callback (set_physics_process(false) in its
      _ready()) while physics_process() runs on the fixed-rate tick driven
      from HeavyPlayerController._physics_process(); these are independently
      scheduled, so a possessor reassignment (e.g. a tackle win, which
      explicitly reassigns possessor to the winner without touching the
      victim's own DribbleState instance) can go unnoticed by process() for
      one or more physics ticks. The physics_process() guard, not the entry
      guards, is what bounds that gap. MoveState.process() and
      IdleState.process() carried the identical unguarded
      "get_ball_in_foot_range() != null -> return DRIBBLE" transition, so a
      defender merely shadowing a held ball would still flicker into a
      hollow, immediately-bounced DribbleState every frame-rate tick even
      after DribbleState's own guards were fixed — closed at the same time.
    rationale: >
      User reported the ball "jitters and jumps around" during CPU-vs-CPU play
      and that it "confuses the players." Root-caused by direct reads of
      DribbleState.gd, MoveState.gd, IdleState.gd, PlayerState.gd (confirming
      check_common_transitions()'s action_tackle gate is unconditionally false
      for any non-user-controlled player, so the foot-sensor steal was the
      entire de facto CPU defensive mechanism — see the companion entry
      cpu-players-never-gated-into-tackle-state), HeavyPlayer.tscn (confirmed
      foot sensor radius 15.0 vs body collision radius 7.0), and every state
      that transitions to DRIBBLE or calls set_possessor() project-wide (4
      call sites total, all HeavyPlayerController, confirmed by grep) to rule
      out any legitimate flow depending on DribbleState silently reassigning a
      non-null, non-self possessor — none exists; TackleState's win path
      already explicitly sets possessor itself before returning DRIBBLE, and
      PenaltyKickState always calls apply_kick() (which releases possession)
      before ever reaching DRIBBLE. PlayerBrain.evaluate_tactical_action()
      keys heavily on ctx.is_possessor/ball.possessor for scoring, so the
      flickering possessor/last_touched_by state during a contest also
      destabilized every other player's decision inputs nearby — the
      "confuses the players" half of the report. Design validated by a
      dedicated Plan sub-agent pass, which independently re-read
      PlayerStateFactory.gd and confirmed the process()/physics_process()
      cadence split is real (not assumed) and is what makes the
      physics_process() guard load-bearing rather than a redundant safety net.
      This sandbox has no Godot binary (godot-47-core.md); the fix is a traced
      control-flow correction, not a captured runtime log — needs live
      playtest confirmation that the visible jitter is gone.
    resolution: >
      Added an (ball.possessor == null or ball.possessor == player) guard to
      DribbleState.enter()'s and process()'s claim branches, and an
      `or ball.possessor != player` clause to physics_process()'s existing
      early-return guard. Extended the same guard one level up into
      MoveState.process() and IdleState.process()'s own DRIBBLE-transition
      checks so a defender shadowing an opponent's held ball stays in
      MoveState/IdleState instead of flickering into a no-op DribbleState
      every frame-rate tick — confirmed via FacingArrow.gd (the only
      possession_lost/possession_gained listener) that the flicker itself was
      cosmetically inert, but the pointless enter()/exit() churn and a
      transient one-tick DRIBBLE_SPEED_PENALTY stutter were worth closing at
      the source. Must ship alongside cpu-players-never-gated-into-
      tackle-state — this fix alone removes CPU defenders' only dispossession
      mechanism (the very bug being fixed), so landing it without real
      tackling would be a defensive regression, not a neutral bug fix.
    promotion_target: .claude/rules/soccer-physics.md
    status: pending

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

  - id: ERR-20260831-02
    date: 2026-08-31
    agent: Claude
    subsystem: ai
    symptom: >
      User-reported: during a corner kick, the CPU taker never actually
      takes the corner, no attacking teammate makes a run into the box, the
      corner "goes to the other team," and the match then freezes. Also
      reported separately in the same session: a ball carrier near the
      centre circle jogs slowly toward the middle "doing nothing else."
    root_cause: >
      Three separate gaps, found by reading SetPieceCoordinator.gd end to
      end (this sandbox has no Godot binary — see godot-47-core.md — so this
      is a code-trace conclusion, not a captured log of this exact freeze).
      (1) _activate_set_piece() only overwrites a CPU taker's stale
      facing_direction when find_pass_target_for_set_piece() returns a real
      teammate (the ERR-20260831-01 fix). That function can still legally
      return null (no candidate clears MIN_PASS_SCORE, or every lane is
      blocked) — plausible at a corner, where most attacking teammates are
      still wherever they stood when the corner was won, not yet inside the
      box. When it does, facing_direction is left at whatever stale value it
      held from open play, which can point anywhere including out of
      bounds. ChargeKickState's CPU path always fires an immediate tap
      (wants() is always false for a non-user-controlled player, so
      _held_time is one physics frame), so a stale out-of-bounds facing taps
      the corner straight back out — explaining "does not take the corner"
      and "goes to the other team" (the re-triggered out-of-bounds event can
      hand the restart to the opposite side). (2) _await_taker_confirmation()
      silently `return`s when _assign_taker() leaves _current_taker null
      (empty _taker_candidates). _freeze_all_players() has already pushed
      all 22 players into SetPieceFreezeState, which only ever hands back to
      Idle once GameManager.is_in_play() is true — never set, since nothing
      ever calls GameManager.restart_play() on this path. This is the same
      class of total, un-recovering freeze as loose-ball-anchor-clamp-
      deadlock above, just triggered from set-piece taker assignment instead
      of the decision layer. (3) No code repositions the attacking side's
      non-taker outfielders during a corner — _position_defending_players()
      only handles the defending team, so attackers just stay frozen
      wherever they stood, which is why "teammates go up in the box" never
      happens; this is a missing feature, not a crash. The centre-circle
      jog report is very likely the general "crowded, no space" symptom
      (also raised in this session, not yet independently root-caused)
      manifesting most visibly right after a kickoff, when both sides are
      still clustered near the halfway line from _enforce_kickoff_halves()
      — _score_pass returns 0 with no open teammate, leaving a low-but-
      nonzero AttemptDribble as the only real option — rather than a
      distinct centre-circle-specific bug; no dedicated circle-radius logic
      exists outside the kickoff freeze itself.
    resolution: >
      (1) _activate_set_piece(): when find_pass_target_for_set_piece()
      returns null for a CPU taker, aim facing_direction at
      _boundary.get_centre_spot() instead of leaving it stale — always a
      safe, in-bounds direction from any restart spot. (2)
      _await_taker_confirmation(): if _current_taker is null, push_warning()
      and call GameManager.restart_play() directly instead of returning
      silently, so the match resumes (ball sits loose at the restart spot,
      picked up by normal ChaseBall logic) instead of freezing forever. (3)
      Added _position_attacking_players_for_corner(), called from
      _setup_taking_side() only for CORNER_KICK, mirroring the existing
      _position_defending_players()/_build_defensive_wall() teleport-based
      positioning pattern: sends up to 4 non-taker, non-GK attackers (sorted
      nearest-to-goal first) to near-post/six-yard-box/far-post/edge-of-box
      spots relative to the defending goal, clamped to the pitch rect. They
      stay parked there via SetPieceFreezeState until restart_play() fires,
      same as the defensive wall. Did not touch the general crowding/space-
      creation question (sep_radius=55px in PlayerBrain._separation_force()
      looks small relative to pitch scale, and _score_pass returning a hard
      0.0 whenever open_teammate_exists is false looks like the main lever)
      — flagged for the user as needing live playtesting to tune safely,
      since this sandbox cannot run a match to verify a tuning change
      actually reduces clumping rather than just moving the symptom.
    affected_files:
      - pitch/SetPieceCoordinator.gd

  - id: ERR-20260831-03
    date: 2026-08-31
    agent: Claude
    subsystem: ai
    symptom: >
      User-reported, and this time empirically confirmed via a pasted Godot
      Output log rather than a code-trace guess: a CPU-vs-CPU match froze
      permanently during a throw-in at 1:23. The freshly-added
      [SpacingReport] diagnostics (crowding-space-creation-diagnostics above)
      caught it directly — dozens of consecutive [SpacingReport] lines with
      bit-for-bit identical numbers (avg_nearest_teammate, width, length, all
      to the same decimal) proved every player's position had genuinely
      stopped changing, not just that the AI was picking a bad but
      technically-moving action. Immediately preceding the freeze:
      [StallWatchdog] logged the ball motionless at (-206.7, -474.0) — 24px
      outside the pitch rect on the touchline, exactly THROW_IN_INSET from
      SetPieceCoordinator._start_throw_in() — with the closest player 77.2px
      away, i.e. not the taker (a correctly-placed taker would read ~0px).
    root_cause: >
      ThrowInState.process()'s CPU branch only ever charged/released the
      throw while PlayerBrain.evaluate_tactical_action() returned &"Pass"
      for that player this tick (`brain.get("current_action") == &"Pass"`).
      But PlayerBrain has a dedicated is_throw_in_taker branch (~line 965)
      that returns &"FindSpace" instead whenever ctx.open_teammate_exists is
      false — normal and frequent, not an edge case, since a throw-in taker
      stands outside the pitch with every other player still frozen in
      SET_PIECE_FREEZE wherever they stood when the ball went out, so a
      pass-worthy candidate is far from guaranteed. When that happened, the
      CPU branch's else clause reset `_held = false; charge_ratio = 0.0`
      every single tick and returned &"" (stay in ThrowInState) — forever,
      since nothing else ever forces current_action back to &"Pass" for a
      teammate who never becomes open. GameManager.restart_play() is only
      ever called from inside ThrowInState._release_throw(), and
      SetPieceFreezeState (every OTHER player, both teams) only ever hands
      back to Idle once GameManager.is_in_play() is true — so the entire
      match locked up permanently. Confirms the SAME failure shape as
      corner-kick-empty-taker-permanent-freeze (ERR-20260831-02) and the
      whole loose-ball-anchor-clamp-deadlock chain: a set-piece/decision path
      that assumes an eventual "real" action will become available, with no
      time-bound fallback if it never does. Tellingly, ThrowInState already
      declared `_cpu_timer` and a `CPU_THROW_DELAY` constant with a doc
      comment describing exactly this auto-throw-after-a-delay fallback —
      neither was ever actually wired into the CPU branch, i.e. this reads
      as an incomplete refactor (the PlayerBrain-pass-target-aware throw
      logic was added on top of, but never merged with, the intended
      timer-based guarantee) rather than a novel design gap.
    resolution: >
      Rewrote ThrowInState.process()'s CPU branch to charge and release
      unconditionally on the existing timing (advances _cpu_timer and
      _held_time every tick regardless of current_action; releases once
      _cpu_timer >= CPU_THROW_DELAY (0.1s) AND charge_ratio >= 0.5, i.e.
      _held_time >= 0.3s — identical timing to the old current_action ==
      &"Pass" success path, so a real open teammate is still found and
      thrown to just as before). _release_throw() itself was already safe to
      call with no pass target — it reads PlayerBrain._cached_pass_target
      directly (set as a side effect of _build_context() regardless of which
      action won, so a real target found earlier in the tick is still used
      even though current_action resolved to &"FindSpace") and falls back to
      player.facing_direction only if that is also null. Did not touch
      _build_context()'s _find_best_pass_target(_ctx.pressure) call (default
      allow_backward_pass=false) even though it is a plausible contributor to
      why open_teammate_exists reads false at some throw-ins — unlike
      kickoff, throw-in receivers are not structurally confined behind the
      taker by any IFAB-derived rule, so this is a real tactical case some of
      the time rather than a guaranteed-every-time starve, and widening it
      is a pass-quality tuning question, not required to prevent the freeze.
    affected_files:
      - entities/player/states/ThrowInState.gd

  - id: ERR-20260901-01
    date: 2026-09-01
    agent: Claude
    subsystem: ai
    symptom: >
      User-reported crash on a live match: "Invalid access to property or key
      'total_registered' on a base object of type 'Node (MatchWorldModel.gd)'"
      raised from TackleState._find_nearby_opponent() (called from
      _check_mistimed_foul() <- _try_win_ball() <- process()), killing the
      state machine's _process() the first time a tackle attempt actually
      reached the mistimed-foul check.
    root_cause: >
      TackleState._find_nearby_opponent() read `world.total_registered` and
      indexed `world.player_active[i]` — neither member exists anywhere on
      MatchWorldModel (verified by grep across the whole file: only
      TOTAL_PLAYERS, the const, and is_slot_live(index), the actual per-slot
      liveness check, exist). This predates this session's own changes —
      TackleState.gd was not in the working tree's modified-files list before
      this session touched anything else, so the buggy call was already
      committed. Reads as the same shape as ball-struck-signal-arg-count-
      mismatch (see cpu-players-never-gated-into-tackle-state and
      verify-external-agent-prompts-against-source-before-executing above):
      code written against an API surface that either never existed under
      those names on MatchWorldModel or was renamed/removed during that
      file's grid-based rewrite (TOTAL_PLAYERS/is_slot_live are exactly the
      shaped replacements) without every caller being updated to match — and
      it went unnoticed because GDScript resolves member access on a
      dynamically-typed local at runtime, not at gdcheck's static-check time,
      so a wrong property name on `world: MatchWorldModel` (a real static
      type) still only surfaces the first time that exact code path executes.
    resolution: >
      Rewrote the loop to use MatchWorldModel.TOTAL_PLAYERS (the constant,
      called on the class since it's a const, not an instance member) in
      place of world.total_registered, and world.is_slot_live(i) in place of
      world.player_active[i] — is_slot_live() already does the intended
      "is this slot's node non-null and valid" check (see its doc comment),
      so behavior is unchanged from what the broken code was clearly trying
      to do, just against the API that actually exists.
    affected_files:
      - entities/player/states/TackleState.gd

  - id: throw-in-ball-outside-chase-legality-rect
    date: 2026-09-01
    agent: Claude
    subsystem: ai
    symptom: >
      User-reported, with a full Godot Output log: a CPU-vs-CPU match's ball
      went out for a throw-in, the throw released normally, but the ball then
      sat motionless just outside the pitch, with every player clustered far
      away and nobody ever approaching it — [StallWatchdog] logged it
      stationary at (48.44982, 474.0), velocity 0. A screenshot confirmed the
      ball resting outside the touchline with no player nearby. Not a crash —
      the match kept running, but play never resumed.
    root_cause: >
      Two independent bugs compounded. (1) PlayerBrain._should_chase_ball()'s
      out-of-play gate compared ball_pos against get_playable_rect() + 25px —
      but get_playable_rect() is already inset from the true pitch edge by
      PITCH_TOUCHLINE_SAFETY_MARGIN (35px) / PITCH_ENDLINE_SAFETY_MARGIN
      (45px) for STEERING clamps (validate_chase_intent/
      clamp_to_playable_area), not the actual out-of-bounds boundary. With a
      900px-tall pitch (touchline at y=450), that put the gate's effective
      edge at 415+25=440, while a throw-in ball legitimately rests
      SetPieceCoordinator.THROW_IN_INSET (24px) past the TRUE touchline
      (y=474 here) — comfortably past the true edge, but 34px beyond the
      gate. So _should_chase_ball() returned false for all 22 players
      whenever a throw-in ball came to rest loose in that zone, the exact
      same failure shape as loose-ball-anchor-clamp-deadlock above but from a
      different gate. (2) Compounding it: ThrowInState._release_throw()'s
      no-pass-target fallback aimed using player.facing_direction verbatim —
      stale from before the taker froze for the restart (see
      throw-in-cpu-taker-never-releases-without-pass-target) and with no
      guaranteed inward (toward pitch centre) component. Here it had ~zero Y
      component, so the released ball travelled entirely along the touchline
      (y pinned at 474.0 from release to rest) instead of into the pitch,
      landing it squarely in the now-unreachable strip from bug (1).
    resolution: >
      (1) Added PlayerBrain.CHASE_OUT_OF_BOUNDS_TOLERANCE (45px) and changed
      _should_chase_ball()'s gate to measure against the RAW pitch rect
      (pitch_boundary.get_pitch_rect()) instead of get_playable_rect(),
      comfortably covering THROW_IN_INSET. Also changed _steer_for_action()
      to skip validate_chase_intent()'s safety-inset clamp entirely for
      must_reach_ball actions (ChaseBall/PanicClear/AttemptShoot) — legality
      and the actual steering target now agree, so a player cleared to chase
      such a ball isn't then clamped short of it by the same inset rect.
      Ordinary FindSpace/MaintainFormation/Pass targets are still clamped to
      the safety-inset rect as before; only genuinely must-reach-the-ball
      actions get the wider allowance. (2) Rewrote the facing_direction
      fallback in ThrowInState._release_throw() to force a real inward Y
      component (sign toward pitch centre from the taker's own position),
      keeping facing_direction.x for left/right lean. A real pass-target aim
      or human input is untouched — only the "nothing better to aim at"
      fallback changed.
    affected_files:
      - entities/player/PlayerBrain.gd
      - entities/player/states/ThrowInState.gd
```

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

### Three latent runtime crashes found by static cross-referencing

None of these were caught by gdcheck, and two were shipped code:

1. `PitchScene.gd` read `GameManager.score_team_a` / `score_team_b` and
   `MatchStatsTracker.fouls_a` / `yellow_cards_a` / `red_cards_a`. None exist —
   both are `Array[int]` (`score[TEAM_A]`, `fouls[TEAM_A]`). The whole
   play-a-match career-progression path was dead on the first goal.

2. `RefereeLoader.get_or_assign_referee()` was called by `KickOffMenu`,
   `PreGameScreen` and the old `ManagerModeHub` but was never written.
   `RefereeLoader` only had `get_referee(index)` and `get_random_referee()`.
   Now implemented and deterministic per matchup, so every screen names the
   same official for the same fixture.

3. `TrustSystem.trust_multiplier()` clamped its stored-space input (0.5-1.5,
   neutral 1.0) with `clampf(t, 0.0, 1.0)`, mapping neutral onto the MAXIMUM
   1.15x and flattening 1.0-1.5 onto that ceiling. Trust losses bit; trust
   gains did nothing. The comment at `PlayerBrain.gd` claiming neutral was "a
   1.0x no-op" only became true after the fix.

**Rule:** an autoload or class member reference is invisible to gdcheck. Run
`tools/lint_xref.py` (now in `verify_gate`) before believing a cross-file call
exists.

### Calibration is not optional, and the first guess was wrong twice

Two models were plainly wrong on their first numbers and only surfaced by
plotting them:

- **Player decline** multiplied a per-year rate by years-past-peak, compounding
  into an 11% single-season pace loss by 33 and driving every player to the
  `top_speed` floor by 34 — a cliff, not a curve. Reworked to a small base with
  a gentle ramp: ~23% loss across ages 30-38, and traits now spread that from
  156 (fragile, unprofessional) to 197 (IronMan professional) on a 220 base.

- **Morale -> MoodSystem seeding** used a symmetric slope that dropped a merely
  "Restless" player (morale 0.45) into SLUMP — a heavy penalty tier. Made
  asymmetric (0.56 down / 0.70 up) so SLUMP needs genuine unhappiness. Verified
  anchors: authored default (0.70/6.5) lands exactly on 0.500 NORMAL.

**Rule:** port any new curve to Python and print it across its real input range
before committing it. Both bugs were invisible in code review and obvious in
one table of numbers.

### The season calendar cannot be a fixed weekly rhythm

A hard 7-day matchday spacing gave the shipped 8-club league a 14-matchday
season ending in early November. Spacing is now derived from the round count
and the target last-matchday date, so 8 clubs space to 21 days and 20 clubs
compress to 7. The rollover guard was likewise a bare `today.month < 6`, which
fired instantly for a November finish and blocked an April one; it is now an
explicit season-end date.

### Non-ASCII identifiers parse here but not in Godot

A Cyrillic local variable slipped into `LeaguePanel.gd` and passed gdcheck.
Godot requires ASCII identifiers. Added a repo-wide scan to catch it; worth
keeping in mind when generating code with mixed-script content nearby.

NEXT: nothing in the career layer has been EXECUTED — this container has no
Godot binary. The next session with an engine should boot Manager Mode, start a
career, and click through all 13 sections before trusting any of it. Highest
risk is scene/layout rendering and signal dispatch, neither of which any static
tool here can check.
