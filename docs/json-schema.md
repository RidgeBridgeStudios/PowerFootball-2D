# JSON Schema for PowerFootball-2D Data Import

Complete specification for authoring player, manager, team, and league JSON. This schema enables systematic import of real squads and is designed for both human and AI-agent readability.

See @../POWERFOOTBALL_MASTER_VISION.md Part V for deep systems context (traits, relationships, reputation).

---

## Field Status Legend

- **IMPLEMENTED** — Currently loaded and active in-game
- **PLANNED** — Reserved in the spec; not yet wired into systems
- **DERIVED** — Auto-calculated; should not be manually authored
- **INTERNAL** — Godot engine use only; not part of JSON authoring

---

## Player Schema

### Required Fields (IMPLEMENTED)

```json
{
  "player_id": "string (unique identifier)",
  "first_name": "string",
  "last_name": "string",
  "shirt_number": "int (1-99)",
  "role": "string (GK, DEF, MID, FWD)",
  "team_id": "string (reference to team)"
}
```

### Physical Attributes (IMPLEMENTED)

```json
{
  "height_cm": "float (160-210)",
  "weight_kg": "float (65-105)",
  "foot_preference": "string (LEFT, RIGHT, BOTH)",
  "max_stamina": "float (0.0-1.0, default 0.8)"
}
```

### Decision Attributes (IMPLEMENTED)

These influence utility scoring and pass selection.

```json
{
  "aggression": "float (0.0-1.0, default 0.5)",
  "work_rate": "float (0.0-1.0, default 0.5)",
  "positioning_iq": "float (0.0-1.0, default 0.5)",
  "pass_accuracy": "float (0.0-1.0, default 0.6)",
  "decision_speed": "float (0.0-1.0, default 0.5)"
}
```

### Traits (PLANNED)

Bitmask-driven modifiers that alter existing systems without creating parallel logic. See Part V of POWERFOOTBALL_MASTER_VISION.md.

```json
{
  "trait_bits": "int (bitmask of applied traits)",
  "trait_names": ["string (human-readable trait names for reference only, not parsed)"]
}
```

**Trait Enumeration** (bitmask values):

| Trait | Bit | Effect |
|---|---|---|
| DeepRunner | 1 | Off-ball channel weighting favors deeper runs |
| WallSplitter | 2 | Free kick specialist; curve advantage |
| PressureImmune | 4 | Resists SLUMP mood penalties |
| HotHeadedTackler | 8 | Higher foul probability in challenges |
| Talisman | 16 | Team mood boost when on pitch; star treatment |
| LockerRoomCancer | 32 | Team mood penalty; conflict events |
| CaptainMaterial | 64 | Increased influence on morale; leadership events |
| StreetBaller | 128 | Influences off-pitch injury risk events |
| PrideGlory | 256 | Strong substitution reaction outcomes |
| VeteranLeader | 512 | Dressing-room event modifier; experience bonus |
| DeadBallSpecialist | 1024 | Penalty and free-kick shot accuracy bonus |
| NightOwl | 2048 | Evening match performance boost (future career mode) |
| IronMan | 4096 | Injury resistance; fatigue accumulation slower |

To combine traits, sum the bit values. Example: `DeepRunner + HotHeadedTackler = 1 + 8 = 9`.

### Derived Fields (INTERNAL, NOT AUTHORED)

```json
{
  "overall_rating": "float (derived from weighted attributes, 0.0-1.0)",
  "reputation": "float (accumulated career events, decays over time)",
  "current_mood": "enum (SLUMP, NORMAL, STREAK, auto-set by MoodSystem)",
  "career_matches_played": "int (auto-incremented)"
}
```

### Relationships (PLANNED)

Persistent relationship data keyed by player ID. Records trust, rivalry, event history. See Part V of POWERFOOTBALL_MASTER_VISION.md.

```json
{
  "relationships": {
    "other_player_id": {
      "trust": "float (0.0-1.0, default 0.5)",
      "rivalry_score": "float (0.0-1.0, default 0.0)",
      "history": ["string (tagged event descriptions)"],
      "last_interaction_match": "int (match number)"
    }
  }
}
```

### Biography (PLANNED)

Free-text fields for agent-driven narrative context.

```json
{
  "bio": "string (300-1000 chars, personal story)",
  "preferred_position_on_pitch": "string (e.g., 'left wing', 'center back')",
  "play_style": "string (e.g., 'technical', 'aggressive', 'creative')"
}
```

### Contract Data (PLANNED)

```json
{
  "contract_year_start": "int (calendar year)",
  "contract_year_end": "int (calendar year)",
  "weekly_wage_currency": "string (ISO 4217, e.g., 'USD', 'EUR')",
  "weekly_wage_amount": "float"
}
```

### Complete Player Example

```json
{
  "player_id": "pl_nordvik_001",
  "first_name": "Erik",
  "last_name": "Soren",
  "shirt_number": 7,
  "role": "FWD",
  "team_id": "team_nordvik",
  "height_cm": 184.0,
  "weight_kg": 82.0,
  "foot_preference": "RIGHT",
  "max_stamina": 0.85,
  "aggression": 0.6,
  "work_rate": 0.7,
  "positioning_iq": 0.65,
  "pass_accuracy": 0.7,
  "decision_speed": 0.6,
  "trait_bits": 17,
  "trait_names": ["DeepRunner", "Talisman"],
  "relationships": {
    "pl_nordvik_002": {
      "trust": 0.8,
      "rivalry_score": 0.1,
      "history": ["successful-combination-play-week-3"],
      "last_interaction_match": 5
    }
  },
  "bio": "Local prospect with flair and confidence.",
  "play_style": "technical"
}
```

---

## Manager Schema

### Required Fields (IMPLEMENTED)

```json
{
  "manager_id": "string (unique identifier)",
  "first_name": "string",
  "last_name": "string",
  "team_id": "string (reference to team)"
}
```

### Personality (IMPLEMENTED)

Bitmask-driven modifiers; same architecture as PlayerData traits.

```json
{
  "trait_bits": "int (bitmask of manager personality traits)",
  "trait_names": ["string (human-readable for reference only)"]
}
```

**Manager Trait Enumeration** (example; expand as needed):

| Trait | Bit | Effect |
|---|---|---|
| Aggressive | 1 | High-press tendency; more fouls accepted |
| Cautious | 2 | Deep defensive setup; lower foul tolerance |
| Offensive | 4 | Formation slant toward attacking |
| Defensive | 8 | Formation slant toward defending |
| Disciplinarian | 16 | Team cohesion boost; harsher subs |
| MoralBooster | 32 | Mood recovery bonus; TouchlineBubble frequency |
| Pragmatist | 64 | Early substitution timing; flexibility |

### Tactics (IMPLEMENTED)

```json
{
  "base_tempo": "float (0.0-1.0, default 0.5, controls pressing frequency)",
  "defensive_line": "string (DEEP, MID, AGGRESSIVE, default MID)",
  "build_from_back": "bool (if true, GK passes rather than long balls)"
}
```

### Formation Library (IMPLEMENTED)

Map formation name to 10-outfield anchor positions (GK is implicit at goal line).

```json
{
  "formations": {
    "4-4-2": {
      "anchors": [
        [50, 25], [30, 20], [70, 20],
        [20, 50], [40, 50], [60, 50], [80, 50],
        [30, 80], [70, 80]
      ]
    },
    "3-5-2": {
      "anchors": [
        [30, 20], [50, 15], [70, 20],
        [15, 50], [35, 50], [65, 50], [85, 50], [50, 55],
        [35, 80], [65, 80]
      ]
    }
  }
}
```

Position indices: [DEF-0, DEF-1, ..., DEF-n, MID-0, ..., FWD-0, FWD-1]

### Press Personality Seed (PLANNED)

Free-text context for agent-driven PressOffice dialogue and touchline reactions.

```json
{
  "press_voice": "string (300-500 chars describing speech pattern, attitude)",
  "signature_phrase": "string (short quote or catchphrase)"
}
```

### Manager Relationships (PLANNED)

Manager-to-player relationship modifiers (separate from player-to-player trust).

```json
{
  "player_relations": {
    "player_id": {
      "relationship_type": "string (MENTOR, ADVERSARY, FAVORITE, UNDERDOG)",
      "influence": "float (0.0-1.0, how much this relationship affects decisions)"
    }
  }
}
```

### Complete Manager Example

```json
{
  "manager_id": "mgr_nordvik_001",
  "first_name": "Johan",
  "last_name": "Berg",
  "team_id": "team_nordvik",
  "trait_bits": 5,
  "trait_names": ["Aggressive", "Offensive"],
  "base_tempo": 0.7,
  "defensive_line": "MID",
  "build_from_back": false,
  "formations": {
    "4-3-3": {
      "anchors": [
        [35, 20], [50, 18], [65, 20],
        [20, 50], [50, 40], [80, 50],
        [25, 80], [50, 85], [75, 80]
      ]
    }
  },
  "press_voice": "Energetic, demands intensity. Quick to praise effort over perfection.",
  "signature_phrase": "Attack is the best defense!"
}
```

---

## Team Schema

### Required Fields (IMPLEMENTED)

```json
{
  "team_id": "string (unique identifier)",
  "team_name": "string",
  "country": "string (ISO 3166-1 alpha-2, e.g., 'SE', 'ES')",
  "primary_color": "string (hex, e.g., '#0033AA')",
  "secondary_color": "string (hex, e.g., '#FFFFFF')",
  "manager_id": "string (reference to manager)",
  "player_ids": ["string (list of player IDs, in squad order)"],
  "lineup_indices": ["int (starting XI player indices in squad)"]
}
```

### Complete Team Example

```json
{
  "team_id": "team_nordvik",
  "team_name": "FC Nordvik",
  "country": "SE",
  "primary_color": "#001A4D",
  "secondary_color": "#FFFFFF",
  "manager_id": "mgr_nordvik_001",
  "player_ids": [
    "pl_nordvik_001",
    "pl_nordvik_002",
    "pl_nordvik_003",
    "pl_nordvik_004",
    "pl_nordvik_005",
    "pl_nordvik_006",
    "pl_nordvik_007",
    "pl_nordvik_008",
    "pl_nordvik_009",
    "pl_nordvik_010",
    "pl_nordvik_011"
  ],
  "lineup_indices": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
}
```

---

## League Schema (PLANNED)

Framework for multi-team progression and season structure.

```json
{
  "league_id": "string (unique identifier)",
  "league_name": "string",
  "season_year": "int",
  "teams": ["string (list of team IDs)"],
  "fixtures": [
    {
      "match_id": "string",
      "home_team_id": "string",
      "away_team_id": "string",
      "round": "int",
      "scheduled_date": "string (ISO 8601)"
    }
  ]
}
```

---

## Loading and Validation

### DataLoader (IMPLEMENTED)

The `autoloads/DataLoader.gd` handles JSON parsing and instantiation:

```gdscript
@onready var players: Dictionary[String, PlayerData] = {}
@onready var managers: Dictionary[String, ManagerData] = {}
@onready var teams: Dictionary[String, TeamData] = {}
```

### Trait Bitmask Parsing

When authoring JSON, use the `trait_bits` integer directly or provide `trait_names` as a reference aid (trait_names is not parsed; only trait_bits is used by the engine).

To compute trait_bits, sum the relevant bit values. Example:
- `DeepRunner` (1) + `Talisman` (16) = 17

### Validation Rules

1. All `*_id` fields must be globally unique within the import.
2. `player_ids` in TeamData must match actual player `player_id` values.
3. `manager_id` in TeamData must reference an existing ManagerData.
4. Attribute values (aggression, work_rate, etc.) must be in range [0.0, 1.0].
5. Formation anchors must be within pitch bounds; recommended range [0, 100] for normalized coordinates.
6. Duplicate entries for the same `player_id` or `manager_id` override previous definitions.

---

## Future Directions

- **Injury Registry**: Persistent injury tracking per player (part of Phase 1 systems).
- **Transfer History**: Career progression across teams (part of Phase 4 systems).
- **Media Sentiment**: Press office historical context and reputation modifiers.
- **Staff Roles**: Coaching staff, medical team, tactical analysts (part of Phase 4 systems).
