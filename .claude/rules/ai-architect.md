---
description: Centralized data caching and time-sliced utility AI rules
paths: ["**/entities/player/**", "**/autoloads/MatchWorldModel*"]
---
## AI & Spatial Decision Invariants

ZERO SCENE TREE POLLING:
  get_tree().get_nodes_in_group() inside _process/_physics_process → PROHIBITED.
  ALL spatial reads → MatchWorldModel.instance.player_positions[i]

TIME-SLICED EVALUATION:
  NPC utility AI MUST use frame-jitter: ShouldUpdate(i, f) = ((i+f) % 15 == 0)
  _steer_for_action() still runs every frame; decision block is gated.

ZERO ALLOCATION IN HOT PATHS:
  Vector2(), Array(), RandomNumberGenerator.new() inside evaluate_tactical_action
  or _physics_process → PROHIBITED. Use pre-allocated class vars.

TOTAL_PLAYERS = 22 (10 outfield + 1 GK × 2 teams). Any other value is a bug.

## Compounded corrections — verified against the source

### Players are DECLARATIVE, not spawned in a loop
All 22 players are `[node ...instance=ExtResource("6_player")]` children of
`$Players` in `pitch/PitchScene.tscn` — eleven `PlayerA_*`, eleven `PlayerB_*`.
There is no instantiate loop anywhere to hang registration off. Do not go
looking for one.

Consequence: index assignment must be self-service from each player's own
`_ready()`, using a static counter, because `_ready()` is the only hook that
fires per player.

```gdscript
# HeavyPlayerController — CORRECT for a declarative layout
static var _auto_index: int = 0

func _ready() -> void:
    process_priority = 100
    world_index = MatchWorldModel.instance.register_player(_auto_index, self, team)
    _auto_index += 1
    if world_index >= 0 and has_node("PlayerBrain"):
        (get_node("PlayerBrain") as PlayerBrain).player_index = world_index
```

A static counter MUST be reset when the roster tears down
(`MatchWorldModel.unregister_all()` does it), or a second match starts
claiming slots at 22 and every player falls off the end of the model.

### Child `_ready()` runs BEFORE parent `_ready()`
`PlayerBrain` is a child of `HeavyPlayerController`, so `PlayerBrain._ready()`
cannot read anything the parent assigns in its own `_ready()` —
`player_index` is still 0 at that point. Connect signals in the child's
`_ready()`; read parent-assigned state later (a decision tick, or a bound
callback). Do not add `await` to paper over this.

### Practice Arena frees 20 of the 22 players
`PitchScene._setup_practice_arena()` calls `queue_free()` on every player but
the human and one keeper. Any cached node array therefore holds freed
references for the rest of the match. EVERY read of `player_nodes[i]` must be
`is_instance_valid()`-guarded — a null check alone does not catch a freed node.

### A shared scratch buffer must have exactly one live call site
`PlayerBrain._find_nearby_opponents()` refills a member `Array[Node2D]` instead
of allocating. That is only safe because one call site exists. Before adding a
second, check that no caller is still iterating the buffer when the other
refills it — `_find_best_pass_target()` and `_find_channel_run_target()` were
deliberately rewritten onto `MatchWorldModel.nearest_opponent_dist_to()` rather
than given a second call to it.

### Group scans that must NOT be routed through MatchWorldModel
The model caches players and the ball only. These remain correct as scene-tree
lookups and were deliberately left alone:

- `ShotLockState`, `ThrowInState`, `ChargeKickState` — `get_nodes_in_group(&"ball")`.
  The model holds a single `ball_node`; these states search for *any* ball and
  filter on `is_frozen` / `is_airborne` / `possessor`. Routing them through the
  model would silently assume one ball.
- `TackleState._find_nearby_opponent()` — `get_nodes_in_group(&"players")`.
  Fires once per mistimed challenge, not per frame, and lives outside the
  brain module. Convertible, but not on any hot path.
