---
description: Centralized data caching and time-sliced utility AI rules
paths: ["**/entities/player/**", "**/autoloads/MatchWorldModel*"]
---
## AI & Spatial Decision Invariants

ZERO SCENE TREE POLLING:
  get_tree().get_nodes_in_group() inside _process/_physics_process -> PROHIBITED.
  ALL spatial reads -> MatchWorldModel.instance.player_positions[i]

TIME-SLICED EVALUATION:
  NPC utility AI MUST use frame-jitter: ShouldUpdate(i, f) = ((i+f) % 15 == 0)
  _steer_for_action() still runs every frame; decision block is gated.

ZERO ALLOCATION IN HOT PATHS:
  Vector2(), Array(), RandomNumberGenerator.new() inside evaluate_tactical_action
  or _physics_process -> PROHIBITED. Use pre-allocated class vars.

TOTAL_PLAYERS = 22 (10 outfield + 1 GK x 2 teams). Any other value is a bug.
