> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match layer.**
> This page records findings about the archived 22-player real-time match engine. That engine now lives under `legacy/` (excluded from Godot and from every linter), so these findings must **not** be applied to current code.
> They are retained as historical reference — useful when deepening `QuickSimEngine` — not as implementation guidance.
> Start with [architecture-pivot.md](architecture-pivot.md); canonical contracts are in [CORE_INVARIANTS.md](../CORE_INVARIANTS.md).

# Telemetry, Diagnostics & Match Stats Errata

**Simulation Layer:** Layer 2 / Layer 3 — Observability & Analytics  
**Primary Modules:** `autoloads/MatchTelemetryLogger.gd`, `autoloads/MatchStatsTracker.gd`, `autoloads/MatchWorldModel.gd`

This page records contracts regarding diagnostic instrumentation, avoiding duplicate telemetry hooks, and spacing evaluation logs.

---

## Table of Contents
### Discovered Rules
- [crowding-space-creation-diagnostics](#crowding-space-creation-diagnostics)

---

## crowding-space-creation-diagnostics

```yaml
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
```

