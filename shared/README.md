# shared/ — Data Models & Utilities

Data classes, collision setup, role configurations, and math helpers used throughout the codebase.

## Data Models

### PlayerData.gd

**Contract:** Pure data container for one player: identity, physical tuning, brain personality, live form, and transient match stats. Saveable as a `.tres` resource. Applied to `HeavyPlayerController` at spawn by `PlayerFactory` and during substitutions via `apply_player_data()`.

**Fields:**
- **Identity:** `player_name: String`, `shirt_number: int`, `position_role: String` ("GK", "CB", "LB", "RB", "DM", "CM", "AM", "LW", "RW", "ST")
- **Physical Tuning:** `mass: float` (default 75.0), `top_speed: float` (default 210.0), `acceleration_time: float` (0.22), `friction_time: float` (0.12), `turning_penalty: float` (0.35), `sprint_multiplier: float` (1.45)
- **Stamina:** `stamina_max: float` (100.0), `stamina_drain: float` (18.0), `stamina_recover: float` (9.0)
- **Brain Personality:** `vision: float` (0.75), `composure: float` (0.60), `aggression: float` (0.80), `formation_ball_weight: float` (0.35), `close_control: float` (0.65), `reflexes: float` (0.60)
- **Form & Career Stats:** `form: float` (0.0–10.0, default 6.5), `career_goals: int`, `career_assists: int`, `last_match_rating: float`, `is_unavailable: bool`
- **Transient Match Stats:** `yellow_cards_this_match: int`, `red_cards_this_match: int` (reset each match by `MatchReferee.bind()`)

---

### ManagerData.gd

**Contract:** Pure data container for one manager: identity, tactical philosophy, squad/signing preferences, personality traits, and career stats.

**Key Fields:**
- **Identity:** `manager_name: String`, `nationality: String`, `experience: int` (1–100), `current_team: String`
- **Tactical Philosophy:** `defensive_line: float` (0.0–1.0), `tempo: float` (0.0–1.0), `width: float` (0.0–1.0), `pressing_intensity: float` (0.0–1.0), `physicality: float` (0.0–1.0)
- **Formations:** `preferred_formation: String` (e.g. "4-4-2"), `attacking_formation: String`, `defensive_formation: String`
- **Squad & Signing:** `youth_trust`, `loyalty_bias`, `form_sensitivity`, `preferred_min_age`, `preferred_max_age`, `budget_flexibility`, `preferred_mass_min`, `preferred_mass_max`, `prized_attribute`, `preferred_playstyle`
- **Personality Traits (Bitmask):** `traits: int` (`HotHead:1`, `Loyalist:2`, `Pragmatist:4`, `Visionary:8`, `Disciplinarian:16`, `MindGames:32`, `Sentimental:64`, `MediaSavvy:128`, `Volatile:256`, `Idealist:512`)
- **Career Stats:** `matches_managed`, `wins`, `draws`, `losses`, `goals_scored`, `goals_conceded`

---

### TeamData.gd

**Contract:** Pure data container for one team: name, colour, full squad array, formation override, and starting lineup indices.

**Fields:**
- `team_name: String`
- `team_color: Color`
- `squad: Array[PlayerData]` — Complete roster (starters + reserves)
- `formation_override: String` — Active formation override chosen in pre-game or pause menu
- `substitutions_made: int` — In-match substitutions counter (max 3)
- `lineup_indices: Array[int]` — 11 indices into `squad` representing current starting/active players

---

### TeamManagementData.gd

**Contract:** Lineup configuration and bench management handler. Provides validation and swaps between starting XI and bench reserves (`swap_players()`, `apply_to_team()`).

---

### PlayerRoleConfig.gd

**Contract:** Data resource representing a single outfield role's tuning parameters (`.tres` presets in `shared/roles/`).
- `role_name: String` ("CB", "CDM", "CM", "ST")
- `anchor_weight: float` — Rigidity of formation anchor (1.0 = rigid, 0.0 = free roam; roam alpha = `1.0 - anchor_weight`)
- `max_chase_distance: float` — Max distance from anchor at which player will chase ball
- `w_dist`, `w_angle`, `w_press`, `w_adv` — Individual pass utility weights
- `pitch_bounds: Rect2` — Normalized zone boundary

---

## Utilities

### PassUtilityScorer.gd

**Contract:** Pure static pass-target scoring across distance falloff (`PREFERRED_DISTANCE = 220.0`), passer facing angle, receiver pressure, and forward advancement.
- `score_pass(...)` → `float` (bare float hot path, 0 allocations)
- `score_pass_breakdown(...)` → `PassScoreBreakdown` (debug-inspectable breakdown)

---

### UtilityMath.gd

**Contract:** Analytical intercept point solver, raycast-free pass lane occlusion, and decay formulas.

**Key Methods:**
```gdscript
func calculate_intercept_point(pursuer_pos, pursuer_speed, ball_pos, ball_velocity, ball_deceleration, delta) -> Vector2
func is_lane_blocked(passer: Vector2, receiver: Vector2, defender: Vector2, min_clearance: float) -> bool
func quadratic_decay(distance: float, radius: float) -> float
```

---

### FormationAnchorMath.gd

**Contract:** Compactness and phase-dependent dynamic anchor calculation (shifting team shape based on possession phase: `IN_POSSESSION`, `OUT_OF_POSSESSION`, `TRANSITION`).

---

### CollisionLayers.gd

**Contract:** Single source of truth for the project's 6-layer collision matrix.

| Layer | Name | Bit Constant | Objects | Masks against |
|---|---|---|---|---|
| 1 | `PitchWorld` | `LAYER_PITCH_WORLD = 1 << 0` | Walls, goalposts, boundaries | Players (2), Ball (3) |
| 2 | `PlayerBodies` | `LAYER_PLAYER_BODIES = 1 << 1` | Player CharacterBody2D | PitchWorld (1), Players (2) |
| 3 | `BallPhysicsBody` | `LAYER_BALL_PHYSICS = 1 << 2` | Ball CharacterBody2D | PitchWorld (1) only |
| 4 | `FootSensorArea` | `LAYER_FOOT_SENSOR = 1 << 3` | Area2D at player feet | BallPhysicsBody (3) only |
| 5 | `AerialHitboxZone` | `LAYER_AERIAL_HITBOX = 1 << 4` | Area2D above shoulders | BallPhysicsBody (3) only |
| 6 | `BoundarySensor` | `LAYER_BOUNDARY_SENSOR = 1 << 5` | Area2D beyond pitch edges | BallPhysicsBody (3) only |

**Critical Physics Invariant:**
- `CharacterBody2D` (Layer 2) masks Layer 1 + 2 ONLY (never Layer 3).
- Ball (Layer 3) masks Layer 1 ONLY.
- All player/ball interactions route through FootSensor (Layer 4) and AerialHitbox (Layer 5).

