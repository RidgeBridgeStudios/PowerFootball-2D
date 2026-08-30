# shared/ — Data Models & Utilities

Data classes, collision setup, and math helpers used throughout the codebase.

## Data Models

### PlayerData.gd

**Contract:** Immutable player attributes loaded from JSON. Extended at runtime by career systems.

**IMPLEMENTED Fields:**
- `player_id: String` — Unique identifier
- `team_id: String` — Team reference
- `first_name: String`, `last_name: String`
- `shirt_number: int`
- `role: String` — Enum-like (GK, DEF, MID, FWD)
- `height_cm: float`, `weight_kg: float`
- `foot_preference: String` — LEFT, RIGHT, BOTH
- `max_stamina: float` — 0.0 to 1.0
- `aggression: float` — Affects utility scoring
- `work_rate: float` — Affects positioning and pressing
- `positioning_iq: float` — Affects off-ball decision quality
- `pass_accuracy: float` — Affects kick scatter
- `decision_speed: float` — Affects decision interval (ManagerDirector uses this)

**PLANNED Fields (Part V, POWERFOOTBALL_MASTER_VISION.md):**
- `trait_bits: int` — Bitmask for deep behavior modifiers
- `relationships: Dictionary[String, RelationshipData]` — Trust/rivalry/history per teammate
- `overall_rating: float` — Derived from weighted attributes
- `reputation: float` — Accumulated career events
- `biography: String` — Narrative context for PressOffice

**DO NOT:**
- Modify PlayerData at runtime; use WorldEvent log for career changes
- Cache PlayerData references; query DataLoader if needed
- Author derived fields (overall_rating, reputation); they are computed

---

### ManagerData.gd

**Contract:** Manager personality and tactical preferences.

**IMPLEMENTED Fields:**
- `manager_id: String` — Unique identifier
- `team_id: String` — Team reference
- `first_name: String`, `last_name: String`
- `trait_bits: int` — Personality traits (bitmask)
- `base_tempo: float` — 0.0 to 1.0; controls pressing intensity
- `defensive_line: String` — DEEP, MID, AGGRESSIVE
- `build_from_back: bool` — If true, GK passes; else long balls

**Formation Library:**
- `formations: Dictionary[String, FormationData]` — Named formations with anchor positions
- Formation name format: "4-3-3", "3-5-2", etc.
- Anchors: array of [x, y] positions for 10 outfield players (GK implicit)

**PLANNED Fields:**
- `press_voice: String` — Speech pattern for PressOffice
- `player_relations: Dictionary[String, ManagerRelation]` — Manager-specific player links

**Usage:**
```gdscript
var mgr = DataLoader.instance.managers[team.manager_id]
var formation = mgr.formations["4-3-3"]
var anchor_pos = formation.anchors[player_anchor_index]
```

---

### TeamData.gd

**Contract:** Team roster and configuration.

**IMPLEMENTED Fields:**
- `team_id: String` — Unique identifier
- `team_name: String`
- `country: String` — ISO 3166-1 alpha-2
- `primary_color: String`, `secondary_color: String` — Hex
- `manager_id: String` — Reference to manager
- `player_ids: Array[String]` — Full squad in order
- `lineup_indices: Array[int]` — Starting XI indices into player_ids

**DO NOT:**
- Modify lineup_indices at runtime; that is for substitution system (Phase 1)
- Change team colors mid-match

---

### LeagueData.gd (PLANNED)

Framework for multi-team progression (Phase 4).

---

## Utilities

### UtilityMath.gd

**Contract:** All AI intercept, occlusion, and sigmoid math.

**Key Methods:**

**Intercept Calculation:**
```gdscript
func calculate_intercept_point(
    pursuer_pos: Vector2,
    pursuer_speed: float,
    ball_pos: Vector2,
    ball_velocity: Vector2,
    ball_deceleration: float,  # friction * FRICTION_SCALE, NOT coefficient alone
    delta: float) -> Vector2
```
Returns ground position where pursuer can intercept ball. Used by AI pathfinding and GK logic.

**Sigmoid Scoring:**
```gdscript
func sigmoid(x: float, mid: float, slope: float) -> float
```
S-curve for utility normalization. Mid = inflection point; slope = steepness.

**Lane Occlusion & Vector Projection:**
```gdscript
func closest_point_on_segment(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> Vector2
func distance_to_segment(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float
func distance_squared_to_segment(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float
func is_lane_blocked(passer: Vector2, receiver: Vector2, defender: Vector2, min_clearance: float) -> bool
```
Calculates analytical point-to-segment vector projections and tests whether a defender breaches the pass corridor threshold without physics raycasts.

**MatchWorldModel Queries:**
```gdscript
func is_passing_lane_open(start_pos: Vector2, end_pos: Vector2, passer_team_id: int, corridor_width: float = DEFAULT_PASS_LANE_CLEARANCE) -> bool
func get_passing_lane_min_distance(start_pos: Vector2, end_pos: Vector2, passer_team_id: int) -> float
```

**Distance Queries:**
```gdscript
func distance_to_goal(team: int, pos: Vector2) -> float
func distance_to_ball(pos: Vector2) -> float
```

**DO NOT:**
- Call calculate_intercept_point with ball.pitch_friction alone; multiply by FRICTION_SCALE
- Allocate vectors inside these functions (already allocation-free)
- Call these outside decision blocks (they are cheap; pre-computation not needed)

---

### CollisionLayers.gd

**Contract:** Layer constants for physics setup. Read before any collision work.

**Layer Definitions:**
- **Layer 1 (Terrain)** — Pitch boundary, goal zones, walls
- **Layer 2 (Players)** — CharacterBody2D; masks/collides with 1
- **Layer 3 (Ball)** — Ball Area2D; sensed by Layer 2 foot sensor only
- **Layer 4 (FootSensor)** — Invisible detector on each player; senses Layer 3
- **Layer 5 (AerialHitbox)** — For heading contests; senses Layer 3 (ball)

**Physics Invariant:**
- CharacterBody2D masks layers 1 + 2 ONLY
- MUST NOT mask layer 3 (ball) — causes velocity zeroing in solver
- Ball interaction routes through foot sensor (layer 4)

**Usage:**
```gdscript
const LAYER_TERRAIN = 1
const LAYER_PLAYERS = 2
const LAYER_BALL = 3
const LAYER_FOOT_SENSOR = 4
const LAYER_AERIAL = 5
```

---

## Extension Points (Planned)

### RelationshipData (PLANNED — Part V)

Per-teammate relationship tracking:
```gdscript
class_name RelationshipData
extends Resource

@export var trust: float = 0.5
@export var rivalry_score: float = 0.0
@export var history: Array[String] = []
@export var last_interaction_match: int = 0
```

Will be stored in `PlayerData.relationships: Dictionary[String, RelationshipData]`.

Plugs into utility pass scoring:
```gdscript
var rel: RelationshipData = carrier.player_data.relationships.get(candidate.player_id)
var trust_weight: float = lerp(0.6, 1.2, rel.trust if rel else 0.5)
score *= trust_weight
```

### WorldEvent (PLANNED — Part V)

Career-mode event log:
```gdscript
class_name WorldEvent
extends Resource

@export var timestamp_match: int = 0
@export var event_tag: String = ""  # e.g., "training_incident", "media_pressure"
@export var primary_player_id: String = ""
@export var secondary_player_id: String = ""
@export var narrative_context: String = ""
@export var resolved: bool = false
@export var resolution_choice: int = -1
```

Will feed PressOffice and relationship updates.

---

## Notes

- All data is loaded once at boot by DataLoader and never modified (immutable by design)
- Career-mode changes (injuries, transfers, trust) are recorded in WorldEvent log, not by modifying PlayerData
- Trait bitmasks use single-bit flags (1, 2, 4, 8, 16, ...) for cheap testing: `(trait_bits & TRAIT_FLAG) != 0`
- Formation anchors are normalized coordinates; multiply by pitch dimensions when applying to world
