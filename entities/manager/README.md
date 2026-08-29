# entities/manager/ — Manager AI & Formations

Manager personality, tactical setup, and formation application to the pitch.

## Architecture Overview

```
ManagerLoader (autoload)
  └─ Loads manager JSON → ManagerData pool
  
ManagerDirector (per-team match brain)
  ├─ Applies ManagerData to team
  ├─ Formation anchor assignment
  ├─ Pressing intensity modulation
  ├─ Brain override application (decision interval, unit traits)
  └─ Formation shifts mid-match
  
PressOffice (narrative layer)
  └─ Quote generation from match events + manager personality
```

---

## ManagerLoader.gd (autoload)

**Contract:** Pure database loader. No signals, no match-time behavior.

**Exports:**
- `managers: Dictionary[String, ManagerData]` — Loaded pool

**DO NOT:**
- Emit formation signals (that is ManagerDirector's role)
- Make match-time decisions
- Reference scene nodes

---

## ManagerDirector.gd

**Contract:** Match-time manager brain. Applies formations, overrides player AI, emits tactical signals.

**Key Methods:**

**Formation Application:**
```gdscript
func _apply_formation(formation_name: String) -> void
```
- Fetches formation anchors from ManagerData
- Writes anchor positions to each player's PlayerBrain
- Emits `GameEvents.manager_formation_changed(team, name)`

**Brain Overrides:**
```gdscript
func _apply_brain_overrides() -> void
```
- Modulates `PlayerBrain.decision_interval` based on pressing intensity
- Filters decision targets based on manager tactics
- Applies manager trait effects (aggressive, cautious, etc.)

**Pressing Control:**
```gdscript
func set_live_pressing(intensity: float) -> void
```
- 0.0 = deep defense
- 0.5 = balanced
- 1.0 = high press
- Modulates player speed targets, decision priorities, and AI timing

**Signals Emitted:**
- `GameEvents.manager_formation_changed(team, formation_name)` — When formation shifts
- `GameEvents.formation_anchors_changed(team, anchors)` — Anchor positions for UI

**DO NOT:**
- Call `_apply_formation()` during match (register it as a response to user/game event only)
- Modify PlayerBrain.player_index (that is done at player spawn)
- Access ball or player state directly for decisions; read MatchWorldModel

---

## PressOffice.gd

**Contract:** Narrative layer. Generates manager quotes and commentary from match events.

**Planned Features (Phase 5):**
- Quote generation from manager personality + match context
- Touchline reactions to key moments
- Post-match commentary and press conference responses
- Integration with WorldEvent log for career-mode narrative

**Current Status:**
- Scaffold exists for event listeners
- Quote templates ready for implementation

---

## Manager Data Schema

See **docs/json-schema.md** for complete schema.

**Key Fields:**
- `manager_id` — Unique identifier
- `trait_bits` — Personality bitmask (aggressive, cautious, etc.)
- `base_tempo` — Pressing intensity (0.0-1.0)
- `defensive_line` — DEEP, MID, AGGRESSIVE
- `formations` — Dictionary of named formations with anchor arrays

**Formation Format:**
```json
{
  "4-3-3": {
    "anchors": [
      [35, 20], [50, 18], [65, 20],  // defenders
      [20, 50], [50, 40], [80, 50],  // midfielders
      [25, 80], [50, 85], [75, 80]   // forwards
    ]
  }
}
```

10 anchors = 10 outfield players (GK is implicit at goal line).

---

## Notes

- Formations are static anchor arrays; dynamic role-based behavior is handled by AI layers
- Manager traits affect AI scoring weights, not direct state changes
- ManagerDirector is per-team; one for home, one for away (not a singleton)
- Formation changes do not interrupt current player actions; they shift anchors gradually
