# PowerFootball 2D

A weighty, deliberate top-down 2D football game built in **Godot 4.7** (GDScript).
Players have mass, momentum and turning arcs; nothing snaps. Designed controller-first.

**Vision:** Dwarf Fortress with a football. Simple visuals, deep social simulation. See @./POWERFOOTBALL_MASTER_VISION.md.

**Current state:** Foundation build with core physics, AI, manager systems, and 22-player matches playable. See @./ROADMAP.md for what's next.

## Running it

Open the project folder in Godot 4.7 and press F5. `res://ui/MainMenu.tscn` is
the main scene — pick Kick Off (team select) or Practice Arena to load
`res://pitch/PitchScene.tscn`: four players (one human-controlled, three CPU),
one ball, two goals, a 5-minute clock.

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

## Architecture at a Glance

See **@./CLAUDE.md** for invariants and boot order. See **@./llms.txt** for static repo map.

```
autoloads/     MatchWorldModel (spatial cache), GameEvents (signal bus), GameManager, data loaders
entities/
  player/      HeavyPlayerController (weight model), PlayerBrain (utility AI), states/
  ball/        Pseudo3DBall (physics), states/
  manager/     ManagerDirector (formations), PressOffice (narrative)
  referee/     MatchReferee (rules)
pitch/         PitchScene, PitchBoundary, GoalZone, markings
ui/            MainMenu, HUD, pause, pregame screens
shared/        PlayerData, ManagerData, UtilityMath, CollisionLayers
tools/         gdcheck.py (static checker)
docs/          json-schema.md (data import spec)
```

**Three architectural rules:**

1. **Nothing crosses systems directly.** Match events → GameEvents signal bus. HUD, camera, referee never reference each other.
2. **The ball is not a physics obstacle.** Layer 3 (ball) does not mask layer 2 (players). Possession is bookkeeping; contact flows through foot sensor (layer 4).
3. **The ball is never parented to a player.** Dribbling is micro-impulses. Sharp turns separate player from ball naturally.

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

## What's Next?

See **@./ROADMAP.md** for the complete 5-phase feature checklist.

**Phase 1** (Gameplay Completeness) priorities:
- Substitutions + reserves UI
- Yellow/red card implementation
- Offside detection
- Injury system
- Match stats screen + full-time scoreboard
- Goalkeeper dive commitment

See **@./POWERFOOTBALL_MASTER_VISION.md** for deep systems design, architectural rationale, and long-term vision.

---

## First Setup in Godot

1. Open the project folder in Godot 4.7
2. Godot regenerates `.import` files for `art/*.png` on first open
3. Confirm autoload boot order in Project Settings → Autoload
4. Confirm 5 physics layer names in Project Settings → Physics → 2D
5. Press F5; select Kick Off or Practice Arena to play

**Troubleshooting cyclic type references:** If Godot reports a cyclic reference in FSM classes, type the `player` parameter in `PlayerState` as `CharacterBody2D` instead of the specific controller type.
