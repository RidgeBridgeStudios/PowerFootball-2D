> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match layer.**
> This page records findings about the archived 22-player real-time match engine. That engine now lives under `legacy/` (excluded from Godot and from every linter), so these findings must **not** be applied to current code.
> They are retained as historical reference — useful when deepening `QuickSimEngine` — not as implementation guidance.
> Start with [architecture-pivot.md](architecture-pivot.md); canonical contracts are in [CORE_INVARIANTS.md](../CORE_INVARIANTS.md).

# UI, HUD & Signal Bus Errata

**Simulation Layer:** Layer 5 — Presentation & Signals  
**Primary Modules:** `autoloads/GameEvents.gd`, `ui/HUD.gd`, `ui/TouchlineBubble.gd`, `pitch/PitchScene.gd`

This page documents UI rendering gotchas, singleton positioning contracts (TouchlineBubble), signal argument count mismatches in Godot 4.7, and safe data retrieval for UI overlays.

---

## Table of Contents
### Discovered Rules
- [ball-struck-signal-arg-count-mismatch](#ball-struck-signal-arg-count-mismatch)
- [touchline-bubble-is-one-shared-instance-home-perspective-only](#touchline-bubble-is-one-shared-instance-home-perspective-only)

### Error Logs
- [ERR-20260830-02](#err-20260830-02)

---

## ball-struck-signal-arg-count-mismatch

```yaml
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
```

## touchline-bubble-is-one-shared-instance-home-perspective-only

```yaml
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

## ERR-20260830-02

```yaml
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

