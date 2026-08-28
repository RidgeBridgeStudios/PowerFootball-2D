##
## DribbleState
##
## Loose possession, Sensible Soccer style. The ball is never parented or
## snapped to the player: it is nudged forward with micro-impulses whenever it
## drifts inside the foot sensor. Turn sharply or sprint too hard and the ball
## runs away from you — that separation is the mechanic, not a bug.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall.
## Exposes: the PlayerState interface.
##

class_name DribbleState
extends PlayerState

## Fraction of top speed the touch aims to put on the ball. Above 1.0 the ball
## outruns the player.
const TOUCH_SPEED_RATIO: float = 1.05
## Minimum seconds between touches, so the ball is not carried on a rail.
const TOUCH_INTERVAL: float = 0.22
## Sprinting pushes the ball further out in front — harder to keep, faster to run onto.
const SPRINT_TOUCH_BONUS: float = 1.25
## Close control: dribbling costs a slice of top speed.
const DRIBBLE_SPEED_PENALTY: float = 0.9

var _touch_cooldown: float = 0.0


func enter(player: HeavyPlayerController) -> void:
	_touch_cooldown = 0.0
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball != null:
		ball.set_possessor(player)
		player.possession_gained.emit()


func exit(player: HeavyPlayerController) -> void:
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball != null and ball.possessor == player:
		ball.release_possession()
	player.possession_lost.emit()


func process(player: HeavyPlayerController, delta: float) -> StringName:
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)

	var common: StringName = check_common_transitions(player)
	if common != &"":
		return common

	# Ball has escaped the foot zone: possession is lost, back to running.
	if player.get_ball_in_foot_range() == null:
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	player.apply_kinematic_weight(player.movement_intent * DRIBBLE_SPEED_PENALTY, delta)

	if _touch_cooldown > 0.0:
		return

	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball == null or ball.is_airborne():
		return

	# Push the ball along the running line rather than the stick line: a heavy
	# player cannot redirect the ball faster than they can redirect themselves.
	var touch_direction: Vector2 = player.facing_direction
	if player.movement_intent.length() > 0.05:
		touch_direction = player.movement_intent.normalized()

	var touch_speed: float = player.get_current_top_speed() * TOUCH_SPEED_RATIO
	if player.is_sprinting:
		touch_speed *= SPRINT_TOUCH_BONUS

	ball.apply_kick(touch_direction * touch_speed, 0.0, player)
	ball.set_possessor(player)
	_touch_cooldown = TOUCH_INTERVAL

	# TODO: scale touch distance by a per-player `close_control` attribute and add
	# a shielding variant when the stick points away from the nearest defender.
