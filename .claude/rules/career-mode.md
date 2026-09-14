---
description: Career layer contracts, identity rules, and the match-layer bridge
paths: ["**/shared/career/**", "**/autoloads/CareerManager*", "**/autoloads/WorldEventLog*", "**/ui/manager_mode/**"]
---
## Career Mode (Layer 1) Invariants

STATE OWNERSHIP:
  CareerManager owns the ONLY live CareerSaveData. Nothing else mutates it.
  WorldEventLog is a live VIEW over CareerSaveData.world_events, not its owner.
  The league (squads/staff/attributes) stays owned by DataLoader and is saved
  per slot via DataLoader.save_league() — never duplicated into the career save.

IDENTITY:
  player_key = team_index * 1000 + squad_index, matching MatchStatsTracker's
  per-player keys and PlayerCareerState.player_key. There is still no
  PlayerData.player_id, so squad_index is the identity (see below).

PERSISTENCE:
  JSON, not .tres. A career must survive the SCRIPTS changing; ResourceSaver
  binary would invalidate every save when a field is added.

## Compounded corrections — verified against the source

### squad_index IS the identity, so removing a player renumbers everyone behind them
`TeamData.squad` is a plain Array. Removing an entry shifts every later index
down by one, which silently re-points:

- every `PlayerCareerState.player_key` / `squad_index` for that club,
- `TeamData.lineup_indices` (the starting XI),
- `TeamData.captain_index`,
- `TeamManagementData.lineup` / `bench` working copies.

`CareerManager._move_player()` is therefore the ONLY place a player changes
clubs, and it must call all three repair steps in order:

```gdscript
source.squad.remove_at(from_squad_index)
_repair_lineup_after_removal(source, from_squad_index)   # XI + captain
_rekey_states_after_removal(from_team, from_squad_index) # player_states dict
```

Never call `squad.remove_at()` anywhere else. A transfer that skips the repair
leaves the club fielding a different eleven than the one the manager picked,
with no error anywhere.

### The career -> match bridge is the quick-sim result folded back by CareerManager
There is no live match entity for career state to seed: the pre-pivot
`PlayerFactory.apply()` bridge (and the in-match `MoodSystem` / `TrustSystem`
it reset) was archived with the real-time layer. A career match now resolves
entirely inside `QuickSimEngine`, and `CareerManager._apply_fixture_result()` is
the one place a result reaches the world. It forwards to
`CareerProgressionEngine.process_matchday_progression()` (reputation, board
confidence, referee drift, accumulated PlayerData stats) and then to
`_record_player_match_state()`, which writes appearance and rating into each
`PlayerCareerState` and runs `MoraleEngine.apply_result_reaction()` /
`apply_reputation_drift()`. Never write a morale, rating, or reputation update
anywhere else.

### Match side is NOT the league team index
The quick-sim runs on two sides (`GameManager.TEAM_A`/`TEAM_B`); the career runs
on league indices. `GameManager`'s `home_team_index` / `away_team_index`
metadata (set by `CareerManager.play_next_fixture()`) is the mapping, and
`DataLoader.get_match_team()` / `DataLoader.get_player()` is the single
conversion — a career lookup keyed on the side directly reads the wrong club's
state whenever the user's club is not league index 0 or 1.

The same trap exists in reverse for QuickSimEngine results:
`QuickSimResult.player_ratings` is keyed by match SIDE (0/1), not league index,
so `_record_player_match_state()` looks up `side * 1000 + squad_index` while
walking the real `team.lineup_indices`.

### Inbox options are deliberately NOT serialised
`InboxItem.Option` carries behaviour-defining deltas (morale, board confidence,
press standing) and an `action_tag` that drives structural effects. Persisting
those to JSON would let a hand-edited save invent arbitrary consequences, so
`CareerSerializer` stores an item's TEXT and resolved state only.

Consequence: any UNRESOLVED decision must be rebuilt after a load, or the
player is left with an unanswerable message that will silently escalate.
`CareerManager._rehydrate_inbox()` does that from the item's category and
payload. A new decision-bearing inbox category needs a matching branch there.

### Trust lives in career space only now
`RelationshipData.trust` — persistent, career space, 0.0-1.0, neutral 0.5 — is
the only live trust value. The in-match `TrustSystem` (stored space 0.5-1.5,
bridged by `normalise_trust()` / `denormalise_trust()`) was archived with the
real-time match layer; nothing loads, seeds, or resets it any more. If an
in-match trust model is reintroduced, keep the two spaces apart: the historical
bug was `trust_multiplier()` feeding the STORED value into a
`clampf(t, 0.0, 1.0)` lerp, so neutral trust (1.0) mapped to the MAXIMUM 1.15x
and every value from 1.0 to 1.5 flattened onto that ceiling.

### The season calendar is derived, never a fixed weekly rhythm
`CareerManager._matchday_spacing()` fits the round count between the first and
last matchday dates. A hard 7-day spacing gave the shipped 8-club league a
season that ended in early November.

The rollover check is likewise an explicit DATE (`SEASON_END_MONTH/DAY`), not a
month comparison. A bare `today.month < 6` guard is incoherent across league
sizes — it fires instantly for a league finishing in November and blocks one
finishing in April.

### gdcheck cannot see through autoloads — use lint_xref
`gdcheck.py` registers autoload names as known TYPES but never checks that a
member exists on them, and it does not type-check expressions. So

```gdscript
RefereeLoader.get_or_assign_referee(home, away)   # method never existed
```

passed every static gate while being a guaranteed runtime crash, in three
shipped call sites. `tools/lint_xref.py` (wired into `verify_gate`) closes that
hole by indexing each class's and autoload's real surface and checking every
qualified access, plus verifying `res://` paths resolve. Run the gate, not just
gdcheck.

### This container still has no engine
Everything above was verified by static analysis, by porting the maths to
Python and checking it against the stdlib, or by reading the source. No Godot
binary exists here, so NOTHING in the career layer has been executed. Scene
rendering, signal dispatch, and frame-level behaviour remain unverified — say
so rather than implying the mode has been run.
