##
## AerialState
##
## Headers and volleys. Entered when a ball above AERIAL_TRIGGER_HEIGHT enters
## the aerial hitbox; contact quality depends on when the player commits inside
## a short timing window, so a well-read cross is a skill, not a collision.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, InputHelper.
## Exposes: the PlayerState interface.
##

class_name AerialState
extends PlayerState

## Seconds the player is committed to the aerial attempt.
const WINDOW: float = 0.35
## Contact within this slice of the window is a clean strike.
const SWEET_SPOT_START: float = 0.1
const SWEET_SPOT_END: float = 0.25
const HEADER_SPEED: float = 420.0
## Downward header: a negative launch drives the ball into the turf.
const HEADER_DOWNWARD_Z: float = -120.0
## Speed retained by a mistimed contact.
const MISCUE_RATIO: float = 0.35

## Volley/bicycle kick each require facing_goal_dot to clear this threshold
## in their respective direction — matching the existing "clear enough to
## act on" convention used elsewhere for a facing/direction read (see
## PlayerBrain._find_best_pass_target()'s forward_dot < -0.2 backward-pass
## veto). Without this, "not facing goal" (dot <= 0.0) covers a full 180°
## arc, so bicycle kick fired for any merely-ambiguous facing_direction —
## routine for a throw-in receiver who has just turned in to meet the ball
## rather than squared up to goal — instead of the course spec's
## deliberately rare, spectacular case. Header is the default for
## everything inside this neutral band. See AGENTS_ERRATA.md
## (bicycle-kick-dominates-ambiguous-facing).
const FACING_CLARITY_THRESHOLD: float = 0.2

const JUMP_PEAK_Z: float = 28.0   ## pixels above ground at peak
const JUMP_GRAVITY: float = 320.0  ## px/s² pulling current_z back to 0

var _elapsed: float = 0.0
var _connected: bool = false
var _z_velocity: float = 0.0


func enter(player: HeavyPlayerController) -> void:
	_elapsed = 0.0
	_connected = false
	player.is_sprinting = false
	_z_velocity = JUMP_PEAK_Z / (WINDOW * 0.5)
	player.current_z = 0.0


func process(player: HeavyPlayerController, delta: float) -> StringName:
	_elapsed += delta

	if not _connected:
		var ball: Pseudo3DBall = player.get_ball_in_aerial_range()
		if ball != null and ball.position_z > AERIAL_TRIGGER_HEIGHT:
			_attempt_contact(player, ball)

	if _elapsed >= WINDOW:
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	# Airborne: no steering authority, only the momentum carried into the jump.
	player.apply_kinematic_weight(Vector2.ZERO, delta)

	_z_velocity -= JUMP_GRAVITY * delta
	player.current_z = maxf(player.current_z + _z_velocity * delta, 0.0)
	player.body_collider.disabled = player.current_z > 1.0


func exit(player: HeavyPlayerController) -> void:
	player.current_z = 0.0
	_z_velocity = 0.0


func _attempt_contact(player: HeavyPlayerController, ball: Pseudo3DBall) -> void:
	var clean: bool = _elapsed >= SWEET_SPOT_START and _elapsed <= SWEET_SPOT_END
	_connected = true

	var opp_goal_x: float = 800.0 if player.team == 0 else -800.0
	var to_goal: Vector2 = Vector2(opp_goal_x - player.global_position.x, -player.global_position.y).normalized()
	var facing_goal_dot: float = player.facing_direction.dot(to_goal)

	var power_mult: float = 1.0
	var launch_z: float = HEADER_DOWNWARD_Z
	var action_name: String = "HEADER"

	if ball.position_z >= 10.0 and ball.position_z <= 20.0 and facing_goal_dot > FACING_CLARITY_THRESHOLD:
		power_mult = 1.5
		launch_z = 20.0
		action_name = "VOLLEY"
	elif ball.position_z >= 5.0 and ball.position_z <= 25.0 and facing_goal_dot < -FACING_CLARITY_THRESHOLD:
		power_mult = 2.0
		launch_z = 60.0
		action_name = "BICYCLE KICK"
	else:
		power_mult = 1.0
		launch_z = HEADER_DOWNWARD_Z
		action_name = "HEADER"

	var text_color: Color = Color.WHITE
	if action_name == "BICYCLE KICK":
		text_color = Color(1.0, 0.85, 0.20)
	elif action_name == "VOLLEY":
		text_color = Color(1.0, 0.95, 0.40)
	else:
		text_color = Color(0.60, 0.85, 1.0)

	player.show_action_text(action_name, text_color)

	var aim: Vector2 = Vector2.ZERO
	if player.is_user_controlled:
		aim = InputHelper.get_aim_vector()
	if aim == Vector2.ZERO:
		aim = player.facing_direction if action_name != "BICYCLE KICK" else -player.facing_direction

	var speed: float = HEADER_SPEED * power_mult
	if not clean:
		speed *= MISCUE_RATIO
		launch_z = absf(launch_z) * 0.5

	ball.apply_kick(aim.normalized() * speed, launch_z, player)
	if player.is_user_controlled and clean:
		InputHelper.rumble(0.35 * power_mult, 0.75 * power_mult, 0.15)

	GameEvents.aerial_contested.emit(player, clean)
