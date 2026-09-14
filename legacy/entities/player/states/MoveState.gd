##
## MoveState
##
## Free running. This is where the weight model does its work: the state feeds
## the raw analog vector — magnitude included — straight into
## HeavyPlayerController.apply_kinematic_weight(), which handles the
## acceleration ramp and the turning penalty.
##
## Depends on: PlayerState, HeavyPlayerController.
## Exposes: the PlayerState interface.
##

class_name MoveState
extends PlayerState

## Below this deflection the player is considered to have released the stick.
const IDLE_THRESHOLD: float = 0.05
## Speed below which, with no input, we hand back to Idle.
const IDLE_SPEED: float = 12.0


func process(player: HeavyPlayerController, _delta: float) -> StringName:
	var common: StringName = check_common_transitions(player)
	if common != &"":
		return common

	var catch_ball: Pseudo3DBall = player.get_ball_in_catch_range()
	if catch_ball != null:
		return GOALKEEPER_HOLD

	var nearby_ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if nearby_ball != null and (nearby_ball.possessor == null or nearby_ball.possessor == player):
		return DRIBBLE

	if player.movement_intent.length() <= IDLE_THRESHOLD and player.velocity.length() <= IDLE_SPEED:
		return IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	player.apply_kinematic_weight(player.movement_intent, delta)
