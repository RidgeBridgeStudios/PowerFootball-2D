##
## ThrowInState
##
## A throw-in is deliberately distinct from ChargeKickState: the ball is held
## above the head and released with a flat arc (impulse_z is always 0), which
## keeps a touchline restart from becoming a cheap lofted long pass. Hold
## action_kick to charge distance, release to throw. The taker cannot move
## while winding up — you plant both feet for a throw, you do not run with it.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, InputHelper,
##             GameEvents, GameManager.
## Exposes: the PlayerState interface plus charge_ratio (read by the HUD meter).
##

class_name ThrowInState
extends PlayerState

## Seconds of hold to reach a full-distance throw.
const CHARGE_TIME: float = 0.6
const MIN_SPEED: float = 300.0
const MAX_SPEED: float = 700.0

## 0.0-1.0, read by PlayerStateFactory.get_charge_ratio() for the HUD meter.
var charge_ratio: float = 0.0

var _held_time: float = 0.0
var _held: bool = false


func enter(_player: HeavyPlayerController) -> void:
	_held_time = 0.0
	_held = false
	charge_ratio = 0.0


func exit(_player: HeavyPlayerController) -> void:
	charge_ratio = 0.0


func process(player: HeavyPlayerController, delta: float) -> StringName:
	# CPU takers have no button to hold. Release immediately rather than
	# reading Input directly, which would pick up the human's device instead.
	if not player.is_user_controlled:
		_release_throw(player)
		return _post_release_state(player)

	if wants(player, &"action_kick"):
		_held = true
		_held_time += delta
		charge_ratio = clampf(_held_time / CHARGE_TIME, 0.0, 1.0)
	elif _held:
		_release_throw(player)
		return _post_release_state(player)

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	# Planted: friction only, same as the charge-kick wind-up.
	player.apply_kinematic_weight(Vector2.ZERO, delta)


func _post_release_state(player: HeavyPlayerController) -> StringName:
	return DRIBBLE if player.get_ball_in_foot_range() != null else IDLE


func _release_throw(player: HeavyPlayerController) -> void:
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball == null:
		return

	var aim: Vector2 = Vector2.ZERO
	if player.is_user_controlled:
		aim = InputHelper.get_aim_vector()
	if aim == Vector2.ZERO:
		aim = player.facing_direction

	var speed: float = lerpf(MIN_SPEED, MAX_SPEED, charge_ratio)
	# Flat trajectory is the point of a throw-in — impulse_z stays 0.
	ball.apply_kick(aim.normalized() * speed, 0.0, player)
	GameEvents.ball_struck.emit(player, speed, charge_ratio)
	GameManager.restart_play()
