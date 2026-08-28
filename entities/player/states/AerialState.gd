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

var _elapsed: float = 0.0
var _connected: bool = false


func enter(player: HeavyPlayerController) -> void:
	_elapsed = 0.0
	_connected = false
	player.is_sprinting = false
	# TODO: drive player.current_z from a jump curve here so the sprite actually
	# leaves the ground; the renderer already offsets by current_z.


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


func _attempt_contact(player: HeavyPlayerController, ball: Pseudo3DBall) -> void:
	var clean: bool = _elapsed >= SWEET_SPOT_START and _elapsed <= SWEET_SPOT_END
	_connected = true

	var aim: Vector2 = Vector2.ZERO
	if player.is_user_controlled:
		aim = InputHelper.get_aim_vector()
	if aim == Vector2.ZERO:
		aim = player.facing_direction

	if clean:
		ball.apply_kick(aim * HEADER_SPEED, HEADER_DOWNWARD_Z)
		if player.is_user_controlled:
			InputHelper.rumble(0.3, 0.8, 0.15)
	else:
		# Glanced it: the ball loops off at a fraction of the pace.
		ball.apply_kick(aim * HEADER_SPEED * MISCUE_RATIO, absf(HEADER_DOWNWARD_Z) * 0.5)

	ball.last_touched_by = player
	GameEvents.aerial_contested.emit(player, clean)
