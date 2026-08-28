# PowerFootball 2D

A weighty, deliberate top-down 2D football game built in **Godot 4.7** (GDScript).
Players have mass, momentum and turning arcs; nothing snaps. Designed
controller-first.

This repository currently contains the **foundation build**: the kinematic weight
system, the pseudo-3D ball solver, both state machines, the collision matrix, the
autoload layer and a playable test pitch.

## Running it

Open the project folder in Godot 4.7 and press F5. `res://pitch/PitchScene.tscn`
is the main scene: four players (one human-controlled, three CPU), one ball, two
goals, a 5-minute clock.

## Controls

| Action | Gamepad | Keyboard |
|---|---|---|
| Move | Left stick (analog — deflection scales pace) | WASD |
| Aim pass/shot | Right stick | Arrow keys |
| Pass / shot | A / Cross — tap passes, hold charges | Space |
| Through ball | X / Square | Q |
| Tackle | B / Circle | E |
| Sprint | RT / R2 (drains stamina) | Left Shift |
| Lob / cross | Y / Triangle | F |
| Switch player | LB / L1 | Tab |
| Super Cancel | RB / R1 | Escape |

## Architecture

```
autoloads/     GameManager (phase, score, clock), GameEvents (signal bus), InputHelper
entities/
  player/      HeavyPlayerController + PlayerStateFactory + PlayerBrain + states/
  ball/        Pseudo3DBall + BallStateFactory + states/
pitch/         PitchScene, PitchBoundary, GoalZone
ui/            HUD
shared/        CollisionLayers
art/           generated placeholder sprites
```

Three rules hold the design together:

1. **Nothing crosses systems directly.** Match events go through `GameEvents`;
   the HUD, camera, goal zones and referee logic never reference each other.
2. **The ball is never a solid obstacle to a player.** Layer 3 does not mask
   layer 2. A hard ball/player contact would zero player velocity inside the
   `move_and_slide()` solver and destroy the momentum model. All contact runs
   through the foot sensor (layer 4) and aerial hitbox (layer 5).
3. **The ball is never parented to a player.** Possession is bookkeeping;
   dribbling is a series of micro-impulses, so any sharp turn separates player
   from ball naturally.

### Measured behaviour of the weight model (75kg defaults)

| Input | Result |
|---|---|
| Standstill to top speed | 0.70s (1.00s to sprint top speed) |
| Coast to a stop | 0.33s / 33px |
| 45° turn at pace | 92% of speed kept |
| 90° turn at pace | 71% kept, 1.6s to recover |
| 180° turn at pace | 10% kept |
| Half stick deflection | 105 px/s of 210 |

---

## Integration checklist — what still needs wiring

**Wiring that is stubbed or partial**

- **Out of bounds.** `PitchBoundary` builds a closed box, so the ball rebounds off
  touchlines instead of going out. `GameEvents.ball_out_of_bounds(side)` is
  declared but never emitted — throw-ins, corners and goal kicks are unbuilt.
- **Fouls and the referee.** `GameEvents.foul_committed` is declared and
  `TackleState` marks where the roll belongs, but no referee consumes it. No
  cards, no free kicks.
- **Half time.** `MatchPhase.HALF_TIME` exists in the enum; nothing drives it.
  `GameManager._end_match()` marks the split point.
- **Super Cancel** only purges a charging kick. It should also sever the CPU
  pathfinding lock in `PlayerBrain` (that is the PES mechanic it is named after).
- **`action_through`** is mapped and unbound — `ChargeKickState` needs a
  lead-the-runner target rather than a direct-to-feet vector.
- **Goalkeepers.** No keeper role, no dive logic, no penalty-area rules.
- **`AerialState`** does not lift the player: `current_z` is wired through the
  renderer but no jump curve drives it.
- **Player switching** picks the teammate nearest the ball; it does not respect
  the aim stick or lock out during dead-ball phases.

**Placeholder assets to replace**

- `art/*.png` are generated flat shapes (16px player disc, 8px ball, blob
  shadow, 32px turf tile). Needed: directional player sprite sheets (idle, run,
  tackle, header), a proper ball, a pitch with markings, and goal frames.
- No audio at all. Hooks that are ready to drive it: `Pseudo3DBall.ball_bounced`,
  `GameEvents.ball_struck`, `tackle_won`, `aerial_contested`, `goal_scored`.
- No fonts or HUD theme — the HUD uses Godot's default Label styling.

**Verify on first open in the editor**

- Godot regenerates `.import` files for `art/*.png` on first import; the scenes
  reference textures by path and will resolve once that finishes.
- Confirm the three autoloads registered in order (GameEvents, GameManager,
  InputHelper) and that the 5 physics layer names appear in Project Settings.
- The FSM classes reference each other's types (`HeavyPlayerController` ⇄
  `PlayerStateFactory` ⇄ states), which is the structure the design calls for.
  If your Godot build reports a cyclic reference, break it by typing the `player`
  parameter in `PlayerState` as `CharacterBody2D`.

**Suggested order for Phase 2 of development**

1. Out-of-bounds detection and restarts (throw-in, corner, goal kick) — the
   match loop cannot be honest without it.
2. Goalkeeper role and penalty-area rules.
3. Formations: give `PlayerBrain.formation_anchor` a team-level formation
   manager instead of per-player spawn positions, and replace direct-seek
   steering with pursue/separate/mark behaviours using
   `Pseudo3DBall.predict_trajectory()` for interception points.
4. Referee and fouls, then cards and set pieces.
5. Animation: sprite sheets driven by state entry, which will also give tackles
   and headers their commitment frames.
6. Feel pass: camera zoom, hit-stop on heavy contact, crowd audio scaling.
