@../CLAUDE.md
@./.claude/rules/

# Course Implementation Specification: Retro 2.5D Arcade Soccer Game (Godot 4.x)

This document serves as the authoritative, standalone technical handoff specification for an AI coding agent. It contains the complete architectural blueprints, data structures, mathematical equations, scene configurations, and step-by-step implementation phases derived from the course videos and technical reports.

---

## 1. Course Objective

The objective of this project is to develop a complete, high-performance, retro-style arcade soccer game in Godot 4.x. The game supports single-player vs. CPU tournament modes, local 1v1 PvP, and local co-op play on a single screen.

### Inspirations & Reference Games

| Game | Platform | What It Contributes |
|---|---|---|
| **Super Soccer / Super Formation Soccer** | SNES | Core 2.5D perspective, sprite-scale depth illusion, snappy arcade physics |
| **Dwarf Fortress** | PC | Data-driven entity system, composition-over-inheritance, JSON roster design |
| **Power Pros Baseball** | GCN/Wii | Exaggerated "chibi" player proportions, team cosmetics, CPU AI personality |
| **FIFA '98–'02** | PS2 | Tournament bracket structure, squad selection screen, goal celebrations |
| **Pro Evolution Soccer 3–5** | PS2 | Passing feel, player weight, momentum-based tackling feedback |

### Dual-Track Architecture & Conflict Resolution

During development, a fundamental structural conflict exists between the two primary source tracks:

1. **Track A (The GameDev Tavern / Nicholas — Primary "Super Soccer" Track):** A 2.5D arcade soccer simulation utilizing custom pixel art, pre-rendered 2D sprite sheets, a customized **AnimatableBody2D** for the ball governed by **manual physics kinematics** to achieve 100% deterministic, snappy gameplay, and a composition-based node state machine for players and ball.
2. **Track B (Godot Dev Checkpoint / Spitty Syntax — Alternative Foundation):** A flat top-down 2D simulation using Kenney's Sports Pack modular vector limbs (separately-rigged feet, hands, and body) assembled under a "rig" node, a **RigidBody2D** for the ball governed entirely by **engine-level rigid body physics** (mass, linear dampening, bounce material), and character-direct push impulses on physics collisions.

**This specification is designed around Track A** because it constitutes the complete, 24-episode end-to-end game system (Tournament loops, AI, Shaders, UI, Kickoffs, Goalkeepers). However, if the active Git repository utilizes Kenney's modular limb assets and a RigidBody2D ball, refer to the **Track B Appendix** inside individual phases to adapt physics impulses and rigging configurations.

---

## 2. Final Product and User-Facing Behavior

The completed game delivers a fast-paced, highly responsive, zero-friction arcade experience:

- **World Cup Tournament Mode:** Players select from 8 distinct national squads (e.g., France, Germany, Spain, Italy, Brazil, USA, Canada). Each team has unique, data-driven attributes (speed, power) and distinct visual cosmetics.
- **Match Progression:** A bracket-based tournament starts at the Quarterfinals. To win, the player must win 3 matches in a row. Regular matches last 2 minutes (120 seconds). Ties are prohibited; drawing games immediately enter sudden-death Overtime (Golden Goal rule).
- **No Out-of-Bounds Interruption:** To maintain high tempo, all traditional football interruptions (throw-ins, corners, out-of-bounds, offsides, fouls) are eliminated. The ball bounces off pitch walls, keeping the ball continuously in play.
- **Positional Ball Carriage (Dribbling):** The ball is kept dynamically at the player's feet, switching sides based on player heading, and procedurally oscillating via a cosine wave to simulate active "tapping" during runs.
- **Dynamic Local Aiming:** Features 8-way digital aiming with temporal weighted averaging, allowing players on keyboards to aim at "in-between" analog angles (e.g., 22.5°).
- **Special Moves & Aerial Acrobatics:** High passes (lobbed over players' heads for distances > 130px) trigger specialized vertical states:
  - **Headers:** Jump forward to head a ball in the air.
  - **Volley Kicks:** Execute a powerful volley strike when facing the target goal.
  - **Bicycle Kicks:** Execute a spectacular acrobatic kick when facing away from the target goal.
  - **Chest Control:** Trap a high-flying ball on the chest, temporarily stalling the player's movement (500ms) and dropping the ball to the ground.
- **Tackling & Hurt States:** Defensive sliding tackles apply dynamic deceleration and slide friction. Hitting the ball carrier knocks them into a **Hurt state** (sliding backward, popping up 0.1px in simulated vertical space to trigger jump-arc gravity, and releasing the ball to tumble along the ground in the direction of the tackle).
- **Active Player Swapping:** Clicking the pass button without the ball swaps control to the non-goalie CPU teammate closest to the ball.
- **Request Pass:** Clicking the pass button when a CPU teammate has possession commands them to execute a lead-predicted pass to the human player.
- **Goalkeeping AI:** Goalkeepers patrol the goal line vertically, track the ball's Y-coordinate, execute automatic dives using ball velocity raycasting, physically block the ball with `GoalieHands`, and knock down offensive crowd players via a `PermanentDamageEmitterArea`.
- **Match Reset Coordination:** A central referee state machine pauses the game clock upon goals, executes player and ball teleportation to kickoff positions, reassigns human control to active offense players, and resumes play once the kickoff pass is triggered.

---

## 3. Technology Stack and Prerequisites

- **Engine:** Godot Engine 4.4.1 (or 4.4/4.6 depending on track).
- **Renderer:** GL Compatibility (mandatory for HTML5/WebGL exports to platforms like itch.io).
- **Editor Profile Configuration:** Focused 2D profile (disable 3D Editor, Asset Library, and Node3D options to optimize Node creation and search).
- **Core Languages:** GDScript (object-oriented, type-safe, contract-driven), GDShader (for character palette swapping).
- **Visual Standards:** Pixel-perfect integer scale, nearest-neighbor texture filtering, upscaled 5x from a base resolution of 280x180 to 1400x900.
- **Assets Required (Folder structure `res://assets/`):**
  - `soccer_player.png`: 6x13 layout sprite sheet.
  - `soccer_ball.png`: 4-frame ball texture.
  - `b-shadow.png`: Drop shadow sprite.
  - `1P.png`, `2P.png`, `CPU.png`: Control overhead indicator icons.
  - `goal-bottom.png`, `goal-top.png`, `goal.png` (Goal popup), `time_up.png` (Times-up popup).
  - `pixelled.ttf` (or `pixel.ttf`): Pixel-art font for themes.
  - Country flag textures under `res://ui/flags/flag-[country].png`.

---

## 4. Learning Path and Dependency Order

To build the project without structural regressions, implement the codebase in this precise sequence:

```
[01. Setup & Graphics] ──> [02. Basic 8-Way Movement] ──> [03. Composition State Machine]
                                                                    │
[06. Environmental boundaries] <── [05. Dribble & Shoot] <── [04. Ball Physics & Friction]
             │
[07. Precise Passing Kinematics] ──> [08. Vertical Gravity & Headers]
                                                  │
[11. Team AI & Steering] <── [10. Shaders & JSON] <── [09. Volley / Bicycle & Chest Control]
             │
[12. Defensive Tackling / Hurt] ──> [13. Goalkeeper AI] ──> [14. Referee Loop & UI HUD]
```

---

## 5. Architecture Overview

The system uses a decoupled, event-driven, composition-based architecture. Direct node paths (`get_parent()`, `get_node()`) are strictly forbidden; instead, we use **Dependency Injection (DI)** and a **Global Event Bus (Autoload)**.

### Simulation Stack

```
┌──────────────────────────────────────────────────────┐
│  LAYER 5 — Match Director (GameManager Autoload)     │
│  Referee FSM · Score · Timer · OvertimeState         │
├──────────────────────────────────────────────────────┤
│  LAYER 4 — World Coordination (ActorsContainer.gd)   │
│  Spawning · Team sorting · Control relay · Kickoff   │
├──────────────────────────────────────────────────────┤
│  LAYER 3 — Entity Logic (player.gd / ball.gd)        │
│  CharacterBody2D FSM · BallState FSM · AIBehavior    │
├──────────────────────────────────────────────────────┤
│  LAYER 2 — Signals (GameEvents Autoload)             │
│  team_scored · ball_possessed · kickoff_ready · etc. │
├──────────────────────────────────────────────────────┤
│  LAYER 1 — Data (squads.json / PlayerResource.gd)    │
│  JSON roster · @export_flags traits · DataLoader     │
└──────────────────────────────────────────────────────┘
                         ↑
              No layer may reference a layer above it.
              All cross-layer communication via Signals.
```

### Event Bus Pattern (`res://autoloads/game_events.gd` / `GameEvents`)

A registered global Autoload acting as the central signal relay, preventing circular dependencies between goals, players, ball, UI, and match state:

- `team_scored(country: String)`: Emitted by goal nets on ball entry.
- `score_changed`: Emitted by GameManager after updating the score.
- `team_reset`: Emitted by GameStateReset to trigger player/ball repositioning.
- `kickoff_ready`: Emitted by ActorsContainer when all 12 players have reset.
- `kickoff_started`: Emitted by GameStateKickoff on user pass input.
- `ball_possessed(player_name: String)`: Emitted when a player gains ball control.
- `ball_released`: Emitted when the ball is shot or passed.
- `game_over(winner_country: String)`: Emitted when the match concludes.

### Global Referee State Machine (`res://scenes/game_manager/game_manager.gd` / `GameManager`)

An Autoload manager tracking scores, country names, active time, and driving match states:

- **InPlayState:** Tracks match countdown, evaluates standard play.
- **ScoredState:** Freezes game timer, triggers player celebration/mourning, waits 3 seconds.
- **ResetState:** Tells players to walk to kickoff positions and registers readiness.
- **KickoffState:** Centers the ball, locks movement, waits for user pass to start play.
- **OvertimeState:** Sudden-death loop, triggers GameOver on first score.
- **GameOverState:** Triggers win/loss animations and player celebrations.

### Player Scene Composition

The player is a unified scene containing role-specific components enabled dynamically:

- `CharacterBody2D (Root)`: Handles physics slides, heading, and state factory.
  - `Sprite2D (Unique Name %PlayerSprite)`: Player artwork.
  - `AnimationPlayer (Unique Name %AnimationPlayer)`: Sprite-frame controller.
  - `CollisionShape2D`: Capsule collider for ground bounds.
  - `Area2D (%TackleDamageEmitterArea)`: Disabled by default; monitors tackles.
  - `Area2D (%OpponentDetectionArea)`: Capsule FOV used for proactive AI passing.
  - `Area2D (%TeammateDetectionArea)`: Cone polygon used for teammate scans.
  - `Area2D (%BallDetectionArea)`: Head-level capsule detecting high balls.
  - `Area2D (%PermanentDamageEmitterArea)`: Goalie-only knockdown hitbox.
  - `AnimatableBody2D (%GoalieHands)`: Goalie-only physical ball block body.
  - `AIBehavior (Child Node)`: Dynamic node injected based on role.

---

## 6. Repository and File Structure

Optimize the repository using this standardized directory tree:

```
res://
├── .gitignore
├── project.godot
├── game_theme.tres                # Global custom theme file
├── squads.json                    # Squad data registry
├── shaders/
│   └── replace_color.gdshader     # CanvasItem palette-swap shader
├── resources/
│   └── player_resource.gd         # Custom PlayerResource configuration
├── autoloads/
│   └── game_events.gd             # Global Event Bus Autoload
├── utils/
│   ├── data_loader.gd             # Roster data loader Autoload
│   ├── key_utils.gd               # Static input handling class
│   ├── score_helper.gd            # Pure static scoreboard formatter
│   ├── flag_helper.gd             # Pure static flag preloader / cache
│   └── time_helper.gd             # Pure static clock text formatter
├── scenes/
│   ├── world.tscn                 # Primary world scene
│   ├── world.gd
│   ├── ui/
│   │   ├── ui.tscn                # UI HUD layer scene
│   │   └── ui.gd
│   ├── characters/
│   │   ├── player.tscn            # Base player character body scene
│   │   ├── player.gd
│   │   ├── actors_container.gd    # Spawning, team sorting, & control relay
│   │   ├── character_states/
│   │   │   ├── player_state.gd    # Base virtual state class
│   │   │   ├── player_state_factory.gd
│   │   │   ├── player_state_moving.gd
│   │   │   ├── player_state_tackling.gd
│   │   │   ├── player_state_recovering.gd
│   │   │   ├── player_state_prepping_shot.gd
│   │   │   ├── player_state_shooting.gd
│   │   │   ├── player_state_passing.gd
│   │   │   ├── player_state_header.gd
│   │   │   ├── player_state_volley_kick.gd
│   │   │   ├── player_state_bicycle_kick.gd
│   │   │   ├── player_state_chest_control.gd
│   │   │   ├── player_state_hurt.gd
│   │   │   ├── player_state_celebrating.gd
│   │   │   ├── player_state_mourning.gd
│   │   │   └── player_state_resetting.gd
│   │   └── AI/
│   │       ├── AI_behavior.gd     # Base virtual AI behavior class
│   │       ├── AI_behavior_factory.gd
│   │       ├── AI_behavior_field.gd
│   │       └── AI_behavior_goalie.gd
│   ├── objects/
│   │   ├── ball.tscn              # Base ball animatable scene
│   │   ├── ball.gd
│   │   └── ball_states/
│   │       ├── ball_state.gd      # Base virtual ball state class
│   │       ├── ball_state_factory.gd
│   │       ├── ball_state_free_form.gd
│   │       ├── ball_state_carried.gd
│   │       └── ball_state_shot.gd
│   └── environment/
│       ├── goal.tscn              # Physical goal frame/net scene
│       └── goal.gd
```

---

## 7. Core Systems

### A. Finite State Machine (FSM) Pattern

The FSM is established via a **Composition over Inheritance** model. Every state is a discrete node instantiated by a State Factory and injected with dependencies upon entrance:

```
[Player Script] ──(Instantiates State)──> [PlayerStateFactory]
       │                                         │
       ├──(Injects player reference)             └──> Returns new State node
       └──(add_child.call_deferred())
```

*Lifecycle hooks:*

- `_enter_tree()`: Runs on-entry logic (e.g., play state animation, zero out velocities).
- `_process(delta)`: Computes active timers, input pooling, and transitions.
- `_physics_process(delta)`: Drives the physics velocity modifications and moves players.
- `_exit_tree()`: Cleans up connections, resets transient indicators (e.g., resetting sprite scale offsets).

*Switch State Routine (In Player Controller):*

```gdscript
# res://scenes/characters/player.gd
func switch_state(new_state_enum: PlayerStateEnum, state_data: PlayerStateData = null):
    if current_state:
        current_state.queue_free()

    current_state = PlayerStateFactory.get_fresh_state(new_state_enum)
    current_state.setup(self, %AnimationPlayer, %BallDetectionArea, %TackleDamageEmitterArea, %OpponentDetectionArea)
    current_state.state_transition_requested.connect(switch_state)
    current_state.name = "PlayerStateMachine_" + PlayerStateEnum.keys()[new_state_enum]
    call_deferred("add_child", current_state)
```

*Note: A parallel state machine is implemented on the Ball (`Ball.State { CARRIED, FREE_FORM, SHOT }`).*

### B. Dynamic AI Behavior & Steering Engine

To scale AI behaviors cleanly and prevent giant, nested conditional structures inside the player loops, we implement the **Action Pattern**. Outfield AI (`AIBehaviorField`) and Goalies (`AIBehaviorGoalie`) are separated into distinct modules inheriting from a generic base class (`AIBehavior`).

**AI Behavior Throttling:** AI ticks are throttled to every 200ms with random millisecond offsets (±50ms per entity) to prevent CPU spikes from all 10 field players evaluating simultaneously.

**Player Role Enum & Trait Bitmask:**

```gdscript
# res://scenes/characters/player.gd
enum Role { GOALKEEPER = 0, DEFENDER = 1, MIDFIELDER = 2, FORWARD = 3 }

@export_flags("CanHead:1", "CanVolley:2", "CanBicycle:4", "CanChest:8", "CanDive:16") 
var traits: int = 0
```

#### Simplified Arcade Steering Blending

To prevent players from slipping like a "spaceship on ice," steering forces are calculated as **normalized directional vectors**. These forces are scaled by dynamic weight parameters (0.0 to 1.0) based on contextual world events, added together, capped, and assigned directly to immediate velocities:

$$\vec{F}_{\text{total}} = \text{clamp}\left( w_1 \vec{f}_{\text{on-duty}} + w_2 \vec{f}_{\text{spawn}} + w_3 \vec{f}_{\text{assist}} + w_4 \vec{f}_{\text{proximity}},\ 1.0 \right)$$

$$\vec{v}_{\text{immediate}} = \vec{F}_{\text{total}} \times v_{\text{max}}$$

### C. Shader-Based Character Palette Swap

To maintain memory efficiency, we use a single grayscale-modulated player sprite sheet (`soccer_player.png`). Jerseys, shorts, socks, and skin tones are swapped on the fly using a custom 2D shader (`replace_color.gdshader`) reading from 2D palette textures:

```
[Grayscale Sprite] ──> [Shader: replace_color.gdshader] ──> [Output Player Screen]
                             ▲                 ▲
                     [Team Palette]     [Skin Palette]
```

*Critical Implementation Safeguard:* The Sprite's Material resource must have **"Local to Scene"** enabled. If disabled, Godot batches the material draw calls, causing *every* player on the field to render with the exact colors of the last spawned player.

---

## 8. Data Models and State

### A. Squad Configuration Database (`res://squads.json`)

The squad rosters are registered in a JSON database mapping team configurations dynamically:

```json
[
  {
    "country": "France",
    "players": [
      { "name": "K. Mbappe",     "skin": 2, "role": 3, "speed": 95.0, "power": 110.0 },
      { "name": "A. Griezmann",  "skin": 0, "role": 3, "speed": 85.0, "power": 90.0  },
      { "name": "O. Giroud",     "skin": 0, "role": 2, "speed": 75.0, "power": 100.0 },
      { "name": "L. Hernandez",  "skin": 0, "role": 1, "speed": 80.0, "power": 85.0  },
      { "name": "R. Varane",     "skin": 1, "role": 1, "speed": 82.0, "power": 80.0  },
      { "name": "H. Lloris",     "skin": 0, "role": 0, "speed": 70.0, "power": 75.0  }
    ]
  }
]
```

### B. Custom Resource Wrapper (`res://resources/player_resource.gd`)

```gdscript
class_name PlayerResource
extends Resource

@export var full_name: String
@export var skin_color: Player.SkinColor
@export var role: Player.Role
@export var speed: float
@export var power: float

func _init(p_name: String = "", p_skin: int = 0, p_role: int = 0, p_speed: float = 80.0, p_power: float = 80.0):
    full_name = p_name
    skin_color = p_skin as Player.SkinColor
    role = p_role as Player.Role
    speed = p_speed
    power = p_power
```

### C. State Data Payloads (`PlayerStateData` & `BallStateData`)

Signals and state switches utilize structured data containers rather than untyped dictionaries, preserving type-safety.

```gdscript
# res://scenes/characters/character_states/player_state_data.gd
class_name PlayerStateData

var shot_direction: Vector2 = Vector2.ZERO
var shot_power: float = 0.0
var pass_target: Player = null
var hurt_direction: Vector2 = Vector2.ZERO
var reset_position: Vector2 = Vector2.ZERO

static func build() -> PlayerStateData:
    return PlayerStateData.new()

func set_shot_direction(dir: Vector2) -> PlayerStateData:
    shot_direction = dir
    return self

func set_shot_power(pwr: float) -> PlayerStateData:
    shot_power = pwr
    return self

func set_pass_target(target: Player) -> PlayerStateData:
    pass_target = target
    return self

func set_hurt_direction(dir: Vector2) -> PlayerStateData:
    hurt_direction = dir
    return self

func set_reset_position(pos: Vector2) -> PlayerStateData:
    reset_position = pos
    return self
```

---

## 9. UI / UX Behavior

The HUD is isolated inside a dedicated `CanvasLayer` scene to prevent camera-offset scrolling.

### A. Layout Node Hierarchy

```
UI (CanvasLayer)
└── UIContainer (Control) [Anchor: Full Rect]
    ├── Background (ColorRect) [Color: #222222, Size: 200x14, Anchor: Bottom Center]
    │   └── HBoxContainer [Anchor: Full Rect, Alignment: Center, Separation: 0, Size: 200x15, Pos Y: -1]
    │       ├── PlayerLabel (Label) [Text: "", Min Size X: 60px, Align: Left, Color: Subtle Gray]
    │       ├── HomeFlagTexture (TextureRect) [Stretch: Keep, Min Size Y: 14px, Placeholder flag]
    │       ├── ScoreLabel (Label) [Text: "0 - 0", Align: Center, Min Size X: 28px]
    │       ├── AwayFlagTexture (TextureRect) [Stretch: Keep, Min Size Y: 14px, Placeholder flag]
    │       └── TimeLabel (Label) [Text: "02:00", Align: Right, Min Size X: 60px]
    ├── Mask (ColorRect) [Color: #000000, Modulate Alpha: 0, Anchor: Full Rect]
    ├── GoalTexture (TextureRect) [Texture: goal.png, Anchor: Center, Pivot: 66,21, Scale: 0]
    ├── GoalScorerLabel (Label) [Text: "", Color: #ece000, Size: 100x14, Anchor: Center, Pos Y: 120]
    ├── ScoreInfoLabel (Label) [Text: "", Color: #e95000, Size: 120x14, Anchor: Center, Pos Y: 135]
    └── TimesUpTexture (TextureRect) [Texture: timelap.png, Anchor: Center, Pivot: 155,10, Scale: 0]
```

### B. HUD Static Optimization Helpers

To avoid rendering bottlenecks and micro-stuttering, UI string modifications and resource loading are managed through pure static classes (no processing ticks):

1. **`ScoreHelper`:** Formats score strings (`get_score_text(array)` → `"1 - 0"`) and processes leading team info (`get_current_score_text(...)` → `"France leads 2-1"` or `"Teams are tied 0-0"`).
2. **`FlagHelper`:** Holds a preloader dictionary `flag_textures: Dictionary = {}`. When the UI requests `get_texture(country)`, it inspects the dictionary first. If absent, it reads `res://ui/flags/flag-[country].png` once from disk and caches it, eliminating frame drops during match kickoff.
3. **`TimeHelper`:** Formats seconds to clock text (`get_time_text(seconds)` → `"MM:SS"`) and handles `"OVERTIME"` displays.

---

## 10. Main Algorithms and Business Rules

### A. Closed-Form Kinematic Pass Velocity Calculation (Deterministic Passing)

To ensure the ball lands exactly at a teammate's feet, we bypass general physics solvers and calculate required velocities in a single frame using calculus integration of constant friction deceleration (a = -f):

$$v^2_{\text{final}} = v_0^2 + 2ax \implies 0 = v_0^2 - 2fx \implies v_0 = \sqrt{2 \cdot d \cdot f}$$

```gdscript
# res://scenes/objects/ball.gd
func pass_to(destination: Vector2, lock_duration: float = 0.5):
    var direction = global_position.direction_to(destination)
    var distance = global_position.distance_to(destination)
    var current_friction = friction_ground if height <= 0.0 else friction_air

    # Calculate exact initial velocity to stop exactly at target
    velocity = direction * sqrt(2.0 * distance * current_friction)

    # Emit State transition with lockout payload to prevent instant re-captures
    var state_data = BallStateData.build().set_lock_duration(lock_duration)
    transition_to_state(Ball.State.FREE_FORM, state_data)
```

### B. Goalkeeper Patrol & Lateral Tracking Heuristic

The goalkeeper AI does not wander. It is physically bound to its spawn X-coordinate and vertical patrol lines, mimicking retro 16-bit arcade sweeps:

$$\text{Target}_y = \text{clamp}\left( \text{Ball}_y,\ \text{Goal}_{\text{top\_target}},\ \text{Goal}_{\text{bottom\_target}} \right)$$

$$\vec{D}_{\text{destination}} = \left( \text{Spawn}_x,\ \text{Target}_y \right)$$

$$\text{Proximity Factor} = \text{clamp}\left( \frac{\text{Distance}(\text{Goalie}, \vec{D})}{10.0},\ 0.0,\ 1.0 \right)$$

$$\vec{v}_{\text{goalie}} = \vec{D}_{\text{normalized}} \times \text{Proximity Factor} \times v_{\text{max}}$$

*Implementation safeguard:* The **Proximity Factor** acts as a deceleration cushion. When further than 10 pixels, the goalie runs at maximum speed. Within 10 pixels, speed decays linearly to 0, ensuring they settle perfectly into position without mechanical jitters or overshoots.

### C. Ball Trajectory Raycasting for GK Dive

To identify when a goalkeeper should dive to block a shot, we attach a `RayCast2D` (`%ScoringRaycast`) to the ball's center, configured to scan *only* the Goal's scoring line area (Layer 5).

1. Every physics frame, the ball rotates the raycast: `scoring_raycast.rotation = velocity.angle()`.
2. When a player executes a shot and `velocity.length() > 0`, the goalkeeper AI queries:

```gdscript
if ball.scoring_raycast.is_colliding() and ball.scoring_raycast.get_collider() == opponent_goal.scoring_area:
    trigger_goalie_dive()
```

### D. Vector Dot Product for Facing Checks (Aerial Shot Aiming)

When receiving high-flying balls, the player is stationary (v = 0). Aiming is auto-directed to the opponent's Goal targets using the vector dot product of the player's heading vector H and the direction vector to the goal D:

$$\cos(\theta) = \vec{H} \cdot \vec{D}$$

```gdscript
# Inside Player State Machine
func is_facing_target_goal() -> bool:
    var direction_to_goal = global_position.direction_to(target_goal.global_position)
    return player.heading.dot(direction_to_goal) > 0.0
```

- **If positive (cos(θ) > 0):** Player is facing target goal → executes **Volley Kick** (power ×1.5, height bounds 10–20px).
- **If negative (cos(θ) ≤ 0):** Player is facing away → executes **Bicycle Kick** (power ×2.0, height bounds 5–25px).

### E. Off-Pitch World Events (`WorldEvent` Struct)

```gdscript
# res://autoloads/game_events.gd — WorldEvent payload
class_name WorldEvent

enum Type {
    GOAL_SCORED,
    TACKLE_LANDED,
    PASS_REQUESTED,
    PLAYER_SWAPPED,
    MATCH_RESET,
    KICKOFF_TRIGGERED,
    GAME_OVER
}

var type: Type
var instigator: Node = null   # Player or Ball that caused the event
var data: Dictionary = {}     # Flexible payload (e.g., { "country": "France", "scorer": "K. Mbappe" })

static func build(t: Type) -> WorldEvent:
    var e = WorldEvent.new()
    e.type = t
    return e

func with_instigator(node: Node) -> WorldEvent:
    instigator = node
    return self

func with_data(key: String, value: Variant) -> WorldEvent:
    data[key] = value
    return self
```

---

## 11. Setup and Build Instructions

1. **System Prerequisite:** Download and launch Godot Engine 4.4.1 (or 4.6 depending on track).
2. **Project Generation:**
   - Create a new Godot project directory. Select the **Compatibility** renderer.
   - Close Godot. Copy the unzipped `assets/` directory (fonts, art, audio) directly into the root folder.
   - Establish Git tracking:
     ```bash
     git init
     # Create .gitignore using Godot's template (excludes .godot/, .tmp/, local cache)
     git add -A
     git commit -m "Initialize project and assets"
     ```
3. **Editor Interface Configuration:**
   - Navigate to `Editor > Manage Editor Features`.
   - Create a custom profile named `"2D"`.
   - Disable: **3D Editor**, **Asset Library**, and **Node3D** options.
4. **Project Settings Configuration:**
   - `Display/Window/Size/Viewport Width`: 280
   - `Display/Window/Size/Viewport Height`: 180
   - `Display/Window/Size/Window Width Override`: 1400
   - `Display/Window/Size/Window Height Override`: 900 (5x logic).
   - `Display/Window/Stretch/Mode`: Viewport
   - `Display/Window/Stretch/Aspect`: Keep
   - `Display/Window/Stretch/Scale Mode`: Integer.
   - `Rendering/Textures/Canvas Textures/Default Texture Filter`: Nearest (preserves pixel boundaries).
   - Set custom Project Theme to `res://game_theme.tres`.

---

## 12. Implementation Phases

Follow this detailed breakdown to complete development. *Note: If working in an existing repository, check the status of preceding files before writing states.*

```
PHASE 1: Core Setup, Environment & Input Abstraction
├── Configure Resolution (280x180), upsizing overrides (1400x900) & Nearest Filtering
├── Assemble World Scene, Pitch Layers (Grass, Pattern, Lines) with Color Modulations
└── Implement Static key_utils.gd for standardized multi-input (P1, P2, CPU) mapping

PHASE 2: Decoupled Entity State Machines
├── Build base PlayerState.gd and PlayerStateFactory.gd
├── Implement Moving, Tackling (200ms duration) and Recovering (500ms) states
├── Configure Ball scene, Collision layers (Layer 1: Walls, 2: Players, 3: Ball)
└── Build BallState base class, Carried & FreeForm states; integrate Possession checks

PHASE 3: Procedural Carriage, Aiming & Passing Math
├── Program dynamic dribbling, x-axis Cosine oscillation & spatial offsets
├── Build temporal Shot direction accumulation & exponential charge-up easing
├── Write teammate cone-of-vision Area2D polygon coordinates in the Player scene
└── Code the deterministic closed-form pass_to() velocity calculations on Ball.gd

PHASE 4: World Boundaries, Camera & Height-based Physics
├── Assemble Static bounds, goals Y-sort frames & goal scoring/backnet Area2Ds
├── Configure predictive smoothing Camera (Smoothing 8 on carriage, 5 on loose balls)
├── Implement simulated Y-axis Sprite height offsets for Ball & Player scenes
└── Build air_connect bounds (10-30px) & generic can_air_interact capability queries

PHASE 5: Acrobatics & Stun Controls
├── Write Header (min 10, max 30), Volley (min 10, max 20) & Bicycle (min 5, max 25) states
└── Build ChestControl state (500ms stall) triggered by high balls (>10px) on players

PHASE 6: Roster Injection & Shader Jerseys
├── Build DataLoader Autoload to ingest squads.json into PlayerResource wrappers
├── Write symmetrical pawns container spawning layout with spawns.scale.x = -1.0 flip
└── Implement replace_color.gdshader material swaps; enable Local to Scene on player sprite

PHASE 7: Positioning AI & Steering Blend
├── Build Action Pattern base class and Field/Goalie AI subclass scripts
├── Implement 200ms throttled ticks with random millisecond offsets to prevent CPU spikes
├── Write distance-squared On-Duty sorting & exponential ease weight decays
└── Program Carrier Arrival deceleration, Anti-Clump repulsion & Formation-Assist steering

PHASE 8: Goalkeeping, Dives & Combat Safeguards
├── Program Goalkeeper vertical patrol, clamp limits & proximity concern speed curves
├── Configure ball-headedness Raycasting colliding with opponent's Scoring Area
├── Write Goalie diving state (0.5s recovery) & GoalieHands / PermanentDamageEmitter areas
└── Implement can_carry_ball() overrides to prevent goalies from pocketing blocks

PHASE 9: Active Player Swapping & Request Pass
├── Code Pass requests to command CPU carriers to pass back to human players
└── Implement distance-squared team sorting in ActorsContainer for instant character swaps

PHASE 10: Tournament FSM, Referee Rules & UI Animations
├── Build GameManager referee state machine (InPlay, Scored, Reset, Kickoff, Overtime, GameOver)
├── Configure kickoff markers, player resetting states & ball kickoff passes
└── Design CanvasLayer HUD, preloaded static helper cache & Goal/Time Up anims
```

---

## 13. Detailed Requirements by Phase

### Phase 1: Core Setup, Environment & Input Abstraction

**Objective:** Establish the visual canvas, viewport overrides, and device-agnostic input mapping.

- **Environment Assembly:** In the `World` scene, construct a `Node2D` backgrounds container. Add three `Sprite2D` nodes:
  - `Grass`: Set Modulate Hex to `#84cd2a`. Disable "Centered".
  - `Pattern`: Set Modulate Hex to `#498b00`. Disable "Centered".
  - `Lines`: Set Modulate Hex to `#f0f0f0`. Disable "Centered".
- **Visual Offset & Convention:** Every object scene (Player, Ball) must standardise the Y-Sort origin convention: **Set root coordinate to (0,0), aligning the feet/ground contact area directly with the origin, and handling visual heights or sprite centers purely via Sprite Offsets** (Player Sprite Offset: x: -16, y: -32).
- **Input Abstraction (`key_utils.gd`):** Map keyboard inputs for P1 Arrow keys, brackets (Pass: `[`, Shoot: `]`), and WASD + tilde/1 keys for P2. Use Physical Key mappings for WASD inputs to preserve structural layout across international layouts (e.g., AZERTY). Return normalized movement vectors via `Input.get_vector()` to resolve diagonal speed advantage bugs (+41% speed boost) for free.

### Phase 2: Decoupled Entity State Machines

**Objective:** Build the core state mechanics for players and the ball to separate movement, tackling, and possession logic.

- **Player FSM Configuration:** Register `PlayerStateEnum { MOVING, TACKLING, RECOVERING, HURT }` inside `Player.gd`.
  - **Moving State:** Pulls normalized inputs from `key_utils`. If shoot/kick is pressed and player has velocity.x != 0, transitions to `Tackling`.
  - **Tackling State:** On enter, triggers `"tackle"` animation (Frame 30). Enforce linear deceleration using move_toward with `GROUND_FRICTION = 250`. Once velocity hits zero, set `is_tackle_complete = true`, log the timestamp, and trigger transition to `Recovering` after a 200ms delay.
  - **Recovering State:** On enter, sets velocity to zero and plays `"recover"` animation (Frame 18). Holds for 500ms before returning to `Moving`.
- **Ball Configuration:** Create an `AnimatableBody2D` root named `Ball`. Add a `Sprite2D` (%BallSprite, offset (-5, -10)), `CollisionShape2D` (5px CircleShape2D), and an `Area2D` (%PlayerDetectionArea, 4px CircleShape2D, monitoring Layer 2 (Players)). Using an AnimatableBody2D allows players to possession-carry the ball without colliding physically and triggering engine jitter.
- **Positional Ball States:**
  - **FreeForm:** Default state. Listens to `%PlayerDetectionArea.body_entered`. On contact, assigns the overlapping player as the ball's carrier and transitions ball state to `Carried`.
  - **Carried:** Teleports the ball's position to follow the player origin, overriding external physics.

*Track B Adaptation:* If building on Spitty's foundation, the ball is a `RigidBody2D`. Enable Continuous Collision Detection (Continuous CD) to prevent the ball from tunneling through goalposts at high speeds. To move the ball, implement a slide collision loop in the player's movement update:

```gdscript
# res://scenes/characters/player.gd (Track B Adaptation)
func push_rigid_bodies():
    for i in get_slide_collision_count():
        var collision = get_slide_collision(i)
        var collider = collision.get_collider()
        if collider is RigidBody2D:
            var push_dir = -collision.get_normal()
            collider.apply_central_impulse(push_dir * push_force)
```

*Safeguard:* Change player's **Motion Mode** from Grounded to **Floating** inside the Inspector. Grounded assumes platformer physics, causing Straight-Down hits to be interpreted as landing on a floor, gluing the player and ball together to rocket off-screen.

### Phase 3: Procedural Carriage, Aiming & Passing Math

**Objective:** Establish the visual fluidness of dribbling, charging shots, aiming averaging, and cone target scanning.

- **Carried Dribbling Oscillations:** In `PlayerStateCarried`, apply a constant Vector2 offset of (10, 4) multiplied by player `heading.x` (1 for Right, -1 for Left) to position the ball at the feet. When moving (`velocity.x != 0`), add a procedural cosine wave offset to the ball's X position to simulate rhythmic tapping:
  
  $$\text{variation\_x} = \cos(\text{dribble\_time} \times 10.0) \times 3.0$$

- **Aiming Temporal Averaging (Keyboard Analog Emulation):** When the player enters the `PreppingShot` state, zero out player velocity and initialize `shot_direction = Vector2.ZERO`. Each frame, accumulate input directions: `shot_direction += get_input_vector() * delta`. Normalize this vector *only once* when the button is released. This averages the input over the duration of the charge, allowing keyboard players to aim at fine angles impossible on an 8-way grid.
- **Shot Power Easing:** Calculate the power bonus using an exponential easing curve of 2.0, rewarding players who hold for the full duration:
  
  $$\text{power\_bonus} = \text{ease}\left( \frac{\text{duration\_press}}{\text{max\_duration}},\ 2.0 \right)$$

- **Cone of Vision Teammate Scan:** Add an `Area2D` named `%TeammateDetectionArea` to the Player scene with a `CollisionPolygon2D` mapped to coordinates: `(0, -40), (280, -150), (330, -100), (330, 100), (280, 150), (0, 40)`. On movement updates, rotate the area to match the player's heading direction.

### Phase 4: World Boundaries, Camera & Height-based Physics

**Objective:** Constrain entities to the pitch, implement a predictive tracking camera, and simulate the illusion of 3D height for aerial balls.

- **Static Boundary Bodies:** Add `StaticBody2D` with `CollisionShape2D` rectangles along all four pitch edges. Assign Wall layer (Layer 1). Set physics material `bounce = 0.6` for elastic wall rebounds.
- **Camera Tracking Logic:** Attach a `Camera2D` to the World scene. In `_process(delta)`, blend position toward a weighted midpoint:
  - When ball is carried: `lerp(camera.position, ball.position, 8.0 * delta)`
  - When ball is loose/shot: `lerp(camera.position, ball.position, 5.0 * delta)`
- **Height Simulation (Y-axis Illusion):** Both `Ball` and `Player` nodes maintain an internal `height: float` variable. Each frame, the node's actual `global_position.y` is offset by `-height` to simulate vertical lift without true 3D physics:
  - Ball airborne: `height += vertical_velocity * delta; vertical_velocity -= GRAVITY * delta`
  - Landing detected: `if height <= 0.0: height = 0.0; bounce()`
- **Air Interaction Window:** A player can only connect with an aerial ball if `abs(ball.height - player.height) < 20.0` and the ball is within range. This `can_air_interact()` check gates all header/volley/bicycle state transitions.

### Phase 5: Acrobatics & Stun Controls

**Objective:** Implement the full suite of aerial skill states — headers, volleys, bicycle kicks, and chest traps.

All aerial states are entered only when `BallDetectionArea` triggers `body_entered` while `ball.height > 10.0`:

| State | Trigger Condition | Power Modifier | Height Bounds | Duration |
|---|---|---|---|---|
| **Header** | Ball in air, player jumps toward it | ×1.0 | 10–30px | 400ms |
| **Volley Kick** | Facing target goal (dot > 0) | ×1.5 | 10–20px | 300ms |
| **Bicycle Kick** | Facing away from goal (dot ≤ 0) | ×2.0 | 5–25px | 500ms |
| **Chest Control** | Ball height > 10px, no directional intent | ×0 (drops) | 0px (lands) | 500ms stall |

### Phase 6: Roster Injection & Shader Jerseys

**Objective:** Load squad data from JSON, spawn all 12 players with correct roles and flipped orientations, and apply per-team palette shaders.

- **DataLoader Autoload:** Reads `res://squads.json` on `_ready()`. Converts each player dictionary into a `PlayerResource` instance. Stores both squads in a `teams: Dictionary = { "home": [], "away": [] }`.
- **Symmetrical Spawning:** `ActorsContainer` spawns 6 home + 6 away players. Away players receive `scale.x = -1.0` and have their spawn positions mirrored across the pitch center (x = 140px).
- **Shader Material Safety:** After setting `%PlayerSprite.material = team_shader_material`, always call `%PlayerSprite.material = %PlayerSprite.material.duplicate()` and set `local_to_scene = true` if not already done in the `.tres` resource.

### Phase 7: Positioning AI & Steering Blend

**Objective:** Build dynamic field player AI using the Action Pattern with weighted vector steering.

- **On-Duty Role Assignment:** Sort all non-goalie field players by distance-squared to ball each tick. Closest player is assigned `on_duty = true`. All others blend toward formation positions.
- **Four Steering Forces (see Section 7B for the formula):**
  1. **On-Duty Force:** Moves active player toward ball.
  2. **Spawn/Formation Force:** Returns idle players toward their default formation position.
  3. **Assist Force:** Pulls support players into passing lanes ahead of the ball carrier.
  4. **Anti-Clump Proximity Force:** Repels players who are too close together (< 20px separation).
- **Tick Throttling Code Pattern:**
  ```gdscript
  # res://scenes/characters/AI/AI_behavior_field.gd
  var _tick_timer: float = 0.0
  const TICK_RATE: float = 0.2  # 200ms

  func _process(delta: float) -> void:
      _tick_timer -= delta
      if _tick_timer <= 0.0:
          _tick_timer = TICK_RATE + randf_range(-0.05, 0.05)
          _evaluate_behavior()
  ```

### Phase 8: Goalkeeping, Dives & Combat Safeguards

**Objective:** Implement the goalkeeper as a semi-autonomous agent locked to the goal line.

- **Vertical Patrol:** See Section 10B for the full clamped patrol formula.
- **Dive Trigger:** See Section 10C for the raycast dive detection logic.
- **GoalieHands:** `AnimatableBody2D (%GoalieHands)` is enabled only during dive states. Its collision shape covers the full goal width. After 0.5s, the goalie returns to patrol and `GoalieHands` is disabled again.
- **Crowd Knockdown:** `%PermanentDamageEmitterArea` monitors body overlaps during the dive animation. Any overlapping player node that is not a teammate gets knocked into their `Hurt` state via `switch_state(PlayerStateEnum.HURT, PlayerStateData.build().set_hurt_direction(knockback_dir))`.
- **can_carry_ball() Guard:** Override `can_carry_ball()` in `AIBehaviorGoalie` to always return `false` if the ball is inside the goal mouth area, preventing the goalie from "catching" a goal-bound shot.

### Phase 9: Active Player Swapping & Request Pass

**Objective:** Give the human player seamless control transfer between teammates.

- **Swap Logic:** On pass button press with no possession, `ActorsContainer` iterates `home_players`, filters out the goalkeeper and currently controlled player, sorts by `distance_squared_to(ball.global_position)`, and calls `set_human_controlled(true)` on the nearest result. The previous player reverts to `AIBehaviorField`.
- **Request Pass Logic:** On pass button press while a CPU teammate has possession, `ActorsContainer` emits a `pass_requested` signal to the ball carrier. The carrier's AI interrupts its current behavior and calls `ball.pass_to(human_player.global_position + human_player.velocity * LEAD_TIME)` where `LEAD_TIME = 0.3` seconds.

### Phase 10: Tournament FSM, Referee Rules & UI Animations

**Objective:** Wire the complete match loop — scoring, reset, kickoff, overtime, and game over.

- **Goal Detection:** Each `Goal` scene has an `Area2D` named `%ScoringArea`. On `body_entered(ball)`, it emits `GameEvents.team_scored(country)`.
- **GameManager Score Update:** On `team_scored`, increments `scores[country]` and emits `score_changed` to refresh the HUD. Transitions to `ScoredState`.
- **ScoredState:** Broadcasts celebration/mourning signals. Waits 3 seconds via `await get_tree().create_timer(3.0).timeout`. Then transitions to `ResetState`.
- **ResetState:** Emits `team_reset`. Each player's `PlayerStateResetting` walks them toward their kickoff position and emits `reset_complete` when arrived. When all 12 have confirmed, `ActorsContainer` emits `kickoff_ready`.
- **KickoffState:** On `kickoff_ready`, teleports ball to center (140, 90). Locks all player movement. On next pass input from human player, emits `kickoff_started` and transitions to `InPlayState`.
- **UI Goal Animations:** Use `Tween` to scale `GoalTexture` from 0 to 1 over 0.3s (elastic out), hold 2s, then scale back to 0. `GoalScorerLabel` fades in with the scorer's name.

---

## 14. Known Constraints, Gotchas & Errata

| # | Issue | Root Cause | Fix |
|---|---|---|---|
| 1 | All players render with the same team color | Material `Local to Scene` is disabled on `%PlayerSprite` | Enable in Inspector or duplicate via `material.duplicate()` |
| 2 | Ball tunnels through goalposts at high speed | RigidBody2D CCD disabled (Track B only) | Enable Continuous CD mode on ball's RigidBody2D |
| 3 | Diagonal movement 41% faster | Movement vector not normalized | Use `Input.get_vector()` which auto-normalizes |
| 4 | All AI evaluates in the same frame | No tick stagger | Add `randf_range(-0.05, 0.05)` offset per entity |
| 5 | Goalie "catches" goal-bound shots | `can_carry_ball()` not overridden | Return `false` in `AIBehaviorGoalie` when ball is in goal mouth |
| 6 | Player and ball fuse together (Track B) | CharacterBody2D Motion Mode = Grounded | Switch to Floating mode |
| 7 | Header triggers on ground balls | Height check missing | Gate `BallDetectionArea` connect behind `ball.height > 10.0` |
| 8 | Pass overshoots target | Wrong friction constant used | Use `friction_air` when `ball.height > 0`, else `friction_ground` |

---

## 15. AI Agent Protocol

This section is for Claude Code (and any future AI coding agent) operating on this repository. Follow these rules precisely.

### Session Initialization

At the start of every coding session, run these commands verbatim:

```bash
# 1. Orient yourself — confirm branch and latest commit
git log --oneline -10

# 2. Survey open work
cat ROADMAP.md

# 3. Check for errata that override spec content
cat AGENTS_ERRATA.md

# 4. Confirm which files already exist for the current phase
ls -la scenes/characters/character_states/
ls -la scenes/objects/ball_states/
ls -la autoloads/
```

### Context Hygiene Zones

| Zone | Files | Agent Rule |
|---|---|---|
| **Authoritative Spec** | `docs/course_implementation_specification.md` | Read-only. Never modify. Source of truth for all architecture decisions. |
| **Errata** | `AGENTS_ERRATA.md` | Read-only. Contains corrections that supersede this spec. Always check before implementing. |
| **Roadmap** | `ROADMAP.md` | Update checkbox state only. Never add or remove tasks without explicit instruction. |
| **Active Code** | `scenes/`, `autoloads/`, `shared/`, `utils/` | Write zone. All GDScript work happens here. |
| **Rules** | `.claude/rules/` | Read-only. Agent behavior constraints loaded at session start. |

### Feature Development Loop

For every new feature or phase task, execute in this exact order:

1. **Read** the relevant phase section in this spec (Section 13).
2. **Check** `AGENTS_ERRATA.md` for any corrections to that phase.
3. **Survey** existing files — never overwrite a file without reading it first.
4. **Implement** the minimum viable code to satisfy the phase objective.
5. **Verify** that signals connect cleanly: no `get_parent()`, no `get_node("/root/...")`.
6. **Update** the `ROADMAP.md` checkbox for the completed task.
7. **Commit** with a message format: `feat(phaseN): <concise description>`.

### Prompt Templates

**Starting a new phase:**
```
I am starting Phase [N]: [Phase Name]. 
Read docs/course_implementation_specification.md Section 13 Phase [N] and AGENTS_ERRATA.md. 
Survey existing files in [relevant directory]. 
Implement the first task: [specific task from phase list].
Do not proceed to the next task until I confirm this one works.
```

**Fixing a bug:**
```
Bug: [symptom description].
Suspected cause: [your theory].
Files involved: [list].
Read the relevant section of the spec before touching any code.
Propose the fix as a diff first; wait for my approval before applying.
```

**Architecture question:**
```
I want to [description of desired behavior].
Before writing any code, check if this conflicts with the spec (docs/course_implementation_specification.md) or AGENTS_ERRATA.md.
If it does conflict, explain the conflict and ask how to proceed.
```

### Pre-Flight Checklist (Before Every Commit)

- [ ] No `get_parent()` or hardcoded node paths — use injected references only
- [ ] No `@onready var x = $SomeNode` on cross-scene references — use DI via `setup()`
- [ ] All new signals are declared in `GameEvents` autoload, not on individual nodes
- [ ] `%PlayerSprite.material` has `local_to_scene = true` on any scene with palette shader
- [ ] Any new Area2D has its collision layer/mask explicitly set in code, not left at defaults
- [ ] `ROADMAP.md` checkbox updated for completed task
- [ ] Commit message follows `feat(phaseN):` / `fix(phaseN):` / `refactor:` convention

### Error Compounding Rule

If a bug cannot be resolved in 2 iterations, **stop**. Do not attempt a third speculative fix. Instead:

1. Revert to the last clean commit: `git stash` or `git checkout -- <file>`
2. Report the exact error message and the two attempted fixes
3. Ask for a human decision before continuing

This rule exists because compounding speculative fixes on a Godot scene graph create state corruption that is extremely difficult to unwind.

---

## Appendix: Track B Adapter Reference

If the active repository uses Kenney Sports Pack assets and a `RigidBody2D` ball, apply these overrides to the Track A spec:

| Track A Spec | Track B Override |
|---|---|
| Ball root: `AnimatableBody2D` | Ball root: `RigidBody2D` with CCD enabled |
| Ball movement: set `velocity` directly | Ball movement: `apply_central_impulse()` |
| Player collision mode: Grounded | Player collision mode: **Floating** |
| Possession: teleport ball to player origin | Possession: disable RigidBody physics via `freeze = true`; reposition manually |
| Rigging: single `Sprite2D` from sprite sheet | Rigging: modular `body`, `feet_L`, `feet_R`, `hands` nodes under a `rig` Node2D |
| pass_to(): uses kinematic friction formula | pass_to(): calls `apply_central_impulse(direction * calculated_force)` |
