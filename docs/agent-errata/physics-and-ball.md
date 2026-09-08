# Physics, Ball Dynamics & Kinematics Errata

**Simulation Layer:** Layer 1 — Physics & Kinematics  
**Primary Modules:** `entities/ball/Pseudo3DBall.gd`, `entities/player/HeavyPlayerController.gd`, `entities/player/states/DribbleState.gd`, `entities/player/states/AerialState.gd`

This page documents physical interaction bugs, dribble magnet overshoot oscillations, dual-possessor kinematics jitter, bicycle kick gating angles, and player controller sprint jostle impulse / fatigue models.

---

## Table of Contents
### Discovered Rules
- [dribble-magnet-forward-overshoot-oscillation](#dribble-magnet-forward-overshoot-oscillation)
- [bicycle-kick-dominates-ambiguous-facing](#bicycle-kick-dominates-ambiguous-facing)
- [dribble-claim-ignores-existing-possessor-dual-driver-jitter](#dribble-claim-ignores-existing-possessor-dual-driver-jitter)
- [verify-external-agent-prompts-against-source-before-executing](#verify-external-agent-prompts-against-source-before-executing)

---

## dribble-magnet-forward-overshoot-oscillation

```yaml
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
```

## bicycle-kick-dominates-ambiguous-facing

```yaml
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
```

## dribble-claim-ignores-existing-possessor-dual-driver-jitter

```yaml
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
```

## verify-external-agent-prompts-against-source-before-executing

```yaml
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
```

