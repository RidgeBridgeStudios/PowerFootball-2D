# entities/referee/ — Match Rules & Personality

Referee personality-weighted foul decisions and match rule enforcement.

## Architecture Overview

```
RefereeLoader (autoload)
  └─ Loads referee JSON → RefereeData pool
  
MatchReferee (match instance)
  ├─ Listens to GameEvents.foul_committed
  ├─ Decides award based on RefereeData personality
  ├─ Routes to SetPieceCoordinator for dead-ball setup
  └─ Tracks cards and discipline stats
```

---

## RefereeLoader.gd (autoload)

**Contract:** Pure database loader.

**Exports:**
- `referees: Dictionary[String, RefereeData]` — Loaded pool

**Responsibilities:**
- Parse `res://data/referees/*.json`
- Instantiate RefereeData objects
- Make pool available to match initialization

---

## MatchReferee.gd

**Contract:** Match-time arbiter. Personality-weighted foul decisions.

**Key Method:**

**Foul Adjudication:**
```gdscript
func _on_foul_committed(offender: HeavyPlayerController, victim: HeavyPlayerController, foul_type: String) -> void
```

Uses `RefereeData` personality and match state to decide:
- Is it an offense or play-on?
- Free kick or penalty?
- Card (yellow/red)?

**Signal Routing:**
- Listens to `GameEvents.foul_committed(offender, victim, type)`
- Emits `GameEvents.foul_awarded(team, location, set_piece_type)`
- Routes to `SetPieceCoordinator.handle_foul()` for dead-ball initiation

**Foul Types** (planned standardization):
- TACKLE — Mistimed challenge
- PUSH — Shoulder contact
- HAND_BALL — Deliberate handball
- DANGEROUS_PLAY — High boot, studs showing
- DISSENT — Verbal/gestural complaint (future)

**Card System** (Phase 1):
- Yellow card → Recorded in RefereeData.yellow_cards_issued
- Red card → Player removal (future substitution system)
- Accumulation rules (2nd yellow = red, etc.)

**Match Temperature:**
- Referee becomes more lenient as match settles
- More trigger-happy early or after contentious moments
- Personality traits (strict, lenient, etc.) override base rules

**DO NOT:**
- Make tactical decisions based on foul calls (ref is passive)
- Directly modify player state; emit events instead
- Cache player references; use MatchWorldModel

---

## RefereeData Schema

See **docs/json-schema.md** for complete schema.

**Key Fields:**
- `referee_id` — Unique identifier
- `first_name`, `last_name`
- `trait_bits` — Personality (strict, lenient, political, etc.)
- `yellow_cards_issued`, `red_cards_issued` — Match stats
- `fouls_awarded`, `fouls_waved` — Adjudication history

**Personality Trait Examples:**
- STRICT (1) — Low tolerance; frequent cards
- LENIENT (2) — High tolerance; lets game flow
- POLITICAL (4) — Favors home team or star players
- VETERAN (8) — Calm; consistent decisions
- YOUNG (16) — Reactive; swayed by crowd

---

## Known Gaps (Phase 1)

- **Offside:** Declared but not emitted (`GameEvents.offside_offense`)
- **Out of Bounds:** Ball escape not yet triggering corner/goal kick
- **Added Time:** No injury time compensation
- **Clearances:** GK actions (punch, throw) not yet distinct from field saves

---

## Notes

- Referee is per-match, instantiated fresh each game
- Personality traits affect decision weighting, not binary rules
- Card accumulation is career-persistent (tracked in PlayerData.career_cards)
- Match temperature rises on yellow cards and contested decisions, decays over time
