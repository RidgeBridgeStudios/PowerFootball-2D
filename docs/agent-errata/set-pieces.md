> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match layer.**
> This page records findings about the archived 22-player real-time match engine. That engine now lives under `legacy/` (excluded from Godot and from every linter), so these findings must **not** be applied to current code.
> They are retained as historical reference — useful when deepening `QuickSimEngine` — not as implementation guidance.
> Start with [architecture-pivot.md](architecture-pivot.md); canonical contracts are in [CORE_INVARIANTS.md](../CORE_INVARIANTS.md).

# Set Pieces & Restarts Errata

**Simulation Layer:** Layer 1 — Kinematics & Layer 2 — Tactical Restarts  
**Primary Modules:** `pitch/SetPieceCoordinator.gd`, `entities/player/states/ThrowInState.gd`, `entities/player/PlayerBrain.gd`, `pitch/PenaltyShootoutCoordinator.gd`

This page documents dead-ball restart deadlocks, kickoff backward pass starvation, corner kick run triggers, throw-in CPU execution stalls, and boundary legality rectangles.

---

## Table of Contents
### Discovered Rules
- [kickoff-backward-pass-veto-starves-taker](#kickoff-backward-pass-veto-starves-taker)

### Error Logs
- [ERR-20260831-01](#err-20260831-01)
- [ERR-20260831-02](#err-20260831-02)
- [ERR-20260831-03](#err-20260831-03)
- [throw-in-ball-outside-chase-legality-rect](#throw-in-ball-outside-chase-legality-rect)

---

## kickoff-backward-pass-veto-starves-taker

```yaml
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
```

## ERR-20260831-01

```yaml
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

## ERR-20260831-02

```yaml
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
```

## ERR-20260831-03

```yaml
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
```

## throw-in-ball-outside-chase-legality-rect

```yaml
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

