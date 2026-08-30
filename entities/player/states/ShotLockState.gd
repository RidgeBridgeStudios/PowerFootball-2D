##
## ShotLockState
##
## FIFA-style shot commit. When the player presses action_kick and the ball is
## not inside the foot sensor but is within LOCK_SEARCH_RADIUS and uncontested,
## the player auto-steers toward it while charging shot power. The strike fires
## when the ball enters foot range OR when the player is close enough and the
## charge is released or maxed. An opponent tackle or possession change cancels
## it. If no shootable ball is found at all, the state bounces straight back out
## on the next process() tick.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, InputHelper,
## MoodSystem (kick accuracy scatter at high charge).
## Exposes: the PlayerState interface plus charge_ratio (read by the HUD meter).
##

class_name ShotLockState
extends PlayerState

## Maximum distance at which auto-lock activates, in pixels.
const LOCK_SEARCH_RADIUS: float = 120.0
## Seconds to build full shot power (mirrors ChargeKickState.CHARGE_TIME).
const CHARGE_TIME: float = 0.8
const PASS_SPEED: float = 260.0
const SHOT_SPEED: float = 620.0
const LOB_HEIGHT_SPEED: float = 420.0
## Movement speed while locked on — the player runs toward the ball at pace.
const LOCK_MOVE_PENALTY: float = 0.75
## Cancel if the ball is still unreachable after this long.
const LOCK_TIMEOUT: float = 1.2
## How close (px) the player must be to the ball before the shot fires even
## if the ball is not yet inside the foot sensor.
const CLOSE_ENOUGH_DIST: float = 32.0

## 0.0-1.0, read by the HUD for the power meter — same convention as
## ChargeKickState.
var charge_ratio: float = 0.0

var _held_time: float = 0.0
var _target_ball: Pseudo3DBall = null
var _is_lob: bool = false


func enter(player: HeavyPlayerController) -> void:
	_held_time = 0.0
	charge_ratio = 0.0
	_is_lob = wants(player, &"action_lob")
	_target_ball = _find_shootable_ball(player)


func exit(_player: HeavyPlayerController) -> void:
	charge_ratio = 0.0


func process(player: HeavyPlayerController, delta: float) -> StringName:
	if just_wants(player, &"action_cancel"):
		return IDLE

	# No shootable ball nearby, stolen by an opponent, or frozen (set piece) —
	# hand control straight back.
	if _target_ball == null:
		return MOVE if player.movement_intent.length() > 0.05 else IDLE
	if _target_ball.possessor != null and _target_ball.possessor != player:
		return MOVE if player.movement_intent.length() > 0.05 else IDLE
	if _target_ball.is_frozen:
		return IDLE

	_held_time += delta
	charge_ratio = clampf(_held_time / CHARGE_TIME, 0.0, 1.0)

	if _held_time >= LOCK_TIMEOUT:
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	var in_range: Pseudo3DBall = player.get_ball_in_foot_range()
	var dist: float = player.global_position.distance_to(_target_ball.global_position)
	var can_shoot: bool = (in_range != null and in_range == _target_ball) or dist <= CLOSE_ENOUGH_DIST

	var button_released: bool = not wants(player, &"action_kick")

	if can_shoot and (button_released or charge_ratio >= 1.0):
		_fire_shot(player)
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	if _target_ball == null:
		return

	# Steer the player toward the ball automatically while the shot charges.
	var to_ball: Vector2 = (_target_ball.global_position - player.global_position).normalized()
	player.apply_kinematic_weight(to_ball * LOCK_MOVE_PENALTY, delta)


func _find_shootable_ball(player: HeavyPlayerController) -> Pseudo3DBall:
	# Walk all balls in the scene. In practice there is only one.
	var balls: Array[Node] = player.get_tree().get_nodes_in_group(&"ball")
	for node: Node in balls:
		var ball := node as Pseudo3DBall
		if ball == null:
			continue
		if ball.is_frozen or ball.is_airborne():
			continue
		# Uncontested, or already loosely ours.
		if ball.possessor != null and ball.possessor != player:
			continue
		var dist: float = player.global_position.distance_to(ball.global_position)
		if dist <= LOCK_SEARCH_RADIUS:
			return ball
	return null


func _fire_shot(player: HeavyPlayerController) -> void:
	# Prefer foot-sensor contact; fall back to the locked target.
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball == null:
		ball = _target_ball
	if ball == null:
		return

	# Close enough to strike but not yet in the sensor — snap it to foot
	# position so apply_kick() lands cleanly, same fallback ChargeKickState uses.
	var dist: float = player.global_position.distance_to(ball.global_position)
	if dist > 0.0 and dist <= CLOSE_ENOUGH_DIST:
		ball.global_position = player.global_position + player.facing_direction * 16.0

	var aim: Vector2 = Vector2.ZERO
	if player.is_user_controlled:
		aim = InputHelper.get_aim_vector()
	if aim == Vector2.ZERO:
		aim = player.facing_direction

	var speed: float = lerpf(PASS_SPEED, SHOT_SPEED, charge_ratio)
	var height: float = LOB_HEIGHT_SPEED * maxf(charge_ratio, 0.4) if _is_lob else 0.0

	# Inherit a slice of the striker's momentum, same convention as ChargeKickState.
	var inherited: Vector2 = player.velocity * 0.25

	var mood_node: MoodSystem = player.get_mood()
	var scatter_mult: float = mood_node.get_kick_accuracy_scatter_multiplier() if mood_node != null else 1.0
	var max_scatter_angle: float = deg_to_rad(12.0) * charge_ratio * scatter_mult
	if max_scatter_angle > 0.001:
		aim = aim.rotated(randf_range(-max_scatter_angle, max_scatter_angle))

	ball.apply_kick(aim * speed + inherited, height, player)
	player.show_action_text("LOB SHOT" if _is_lob else "SHOT")
	GameEvents.ball_struck.emit(player, speed, charge_ratio, true)
	if player.is_user_controlled:
		InputHelper.rumble(0.25 * charge_ratio, 0.6 * charge_ratio, 0.12)
