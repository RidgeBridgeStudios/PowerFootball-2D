##
## IdleState
##
## Standing still. Friction is still running underneath, so entering Idle at
## pace produces a heavy coast to a halt rather than a stop — leaving Idle is
## about intent, not about being motionless.
##
## Depends on: PlayerState, HeavyPlayerController.
## Exposes: the PlayerState interface.
##

class_name IdleState
extends PlayerState

## Stick deflection needed to break out of idle. Just above the input deadzone
## so the transition is deliberate.
const MOVE_THRESHOLD: float = 0.05


func enter(player: HeavyPlayerController) -> void:
	# TODO: play the idle animation once placeholder art is replaced with a
	# sprite sheet; the controller only rotates a static sprite today.
	player.is_sprinting = false


func process(player: HeavyPlayerController, _delta: float) -> StringName:
	var common: StringName = check_common_transitions(player)
	if common != &"":
		return common

	if player.get_ball_in_foot_range() != null and player.movement_intent.length() > MOVE_THRESHOLD:
		return DRIBBLE

	if player.movement_intent.length() > MOVE_THRESHOLD:
		return MOVE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	# No input vector: apply_kinematic_weight() decays velocity under friction.
	player.apply_kinematic_weight(Vector2.ZERO, delta)
