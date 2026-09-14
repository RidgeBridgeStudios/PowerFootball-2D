> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match layer.**
> This page records findings about the archived 22-player real-time match engine. That engine now lives under `legacy/` (excluded from Godot and from every linter), so these findings must **not** be applied to current code.
> They are retained as historical reference — useful when deepening `QuickSimEngine` — not as implementation guidance.
> Start with [architecture-pivot.md](architecture-pivot.md); canonical contracts are in [CORE_INVARIANTS.md](../CORE_INVARIANTS.md).
> The general Godot parser, autoload, and `tools/lint_xref.py` cross-referencing lessons at the end of this page remain current.

# Scene Tree, Node Hierarchy & Cross-Referencing Errata

**Simulation Layer:** Layer 1-5 Choke Points & Cross-Module Architecture  
**Primary Modules:** Autoload singletons (`MatchWorldModel`, `GameManager`, `DataLoader`, `RefereeLoader`), Scene hierarchies, and `tools/lint_xref.py`

This page records critical runtime crashes and static check blind spots arising from non-existent property access on autoloads, missing method implementations, and engine character set restrictions.

---

## Table of Contents
### Error Logs
- [ERR-20260901-01](#err-20260901-01)
- [ERR-20260910-01](#err-20260910-01)

### Cross-Module Architecture Findings
- [Three latent runtime crashes found by static cross-referencing](#three-latent-runtime-crashes-found-by-static-cross-referencing)
- [Non-ASCII identifiers parse here but not in Godot](#non-ascii-identifiers-parse-here-but-not-in-godot)
- [Self inside lambda closure parse failures in GDScript 2.0](#self-inside-lambda-closure-parse-failures-in-gdscript-20)

---

## ERR-20260910-01

```yaml
- id: ERR-20260910-01
  date: 2026-09-10
  agent: Antigravity / Gemini Flash
  subsystem: ui/manager_mode
  symptom: >
    Failed to load script "res://ui/manager_mode/SquadPanel.gd" with error "Parse error".
    Failed to load script "res://ui/manager_mode/TransfersPanel.gd" with error "Parse error".
  root_cause: >
    In GDScript 2.0 (Godot 4.x), anonymous lambdas are Callable closures that capture local
    scope variables by reference, but 'self' is a special keyword and cannot be captured.
    Calling `func(): open_modal(self, ...)` causes an immediate compile-time parse failure.
  resolution: >
    Replaced direct `self` keyword with the local outer parent container or bound variable
    (`body` in SquadPanel, `host` in TransfersPanel). Added `RULE-LAMBDA-SELF` to `tools/lint_scope.py`,
    headless engine compiler verification to `tools/godot_verify.py`, and wired checks into
    `tools/verify_gate.py` and git pre-commit hooks.
  affected_files:
    - ui/manager_mode/SquadPanel.gd
    - ui/manager_mode/TransfersPanel.gd
    - tools/lint_scope.py
    - tools/godot_verify.py
```

---

## ERR-20260901-01

```yaml
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
```

## Three latent runtime crashes found by static cross-referencing

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

---

## Non-ASCII identifiers parse here but not in Godot

A Cyrillic local variable slipped into `LeaguePanel.gd` and passed gdcheck.
Godot requires ASCII identifiers. Added a repo-wide scan to catch it; worth
keeping in mind when generating code with mixed-script content nearby.

---

## Self inside lambda closure parse failures in GDScript 2.0

In GDScript 2.0 (Godot 4.x), anonymous lambdas (`func(): ...`) are treated as closures that capture outer local variables. However, `self` is a special keyword, NOT a local variable. Writing:
```gdscript
button.pressed.connect(func(): open_modal(self, data))
```
triggers an unrecoverable parse error:
`Failed to load script "res://path/to/Script.gd" with error "Parse error".`

### Remediation
Store `self` in a local variable before the lambda:
```gdscript
var host_panel: Control = self
button.pressed.connect(func(): open_modal(host_panel, data))
```
or pass parent parameters (`body`, `host`) already present in the method scope.
Enforced statically in `<10ms` by `tools/lint_scope.py` (`RULE-LAMBDA-SELF`) and during engine verification by `tools/godot_verify.py`.
