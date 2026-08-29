##
## ThrowInState
##
## A throw-in is deliberately distinct from ChargeKickState: the ball is held
## above the head and released with a flat arc (impulse_z is always 0), which
## keeps a touchline restart from becoming a cheap lofted long pass. Hold
## action_kick to charge distance, release to throw. The taker cannot move
## while winding up — you plant both feet for a throw, you do not run with it.
##
## After releasing the throw the taker transitions to IDLE/MOVE unconditionally
## — never to DRIBBLE. apply_kick() only sets the ball's velocity; the ball
## itself only moves on its own next _physics_process tick. Querying the foot
## sensor in the same frame as the kick therefore always reports the ball as
## still overlapping (it hasn't moved yet), which would otherwise immediately
## flip the taker back into DribbleState. The _released flag sidesteps the
## sensor entirely once the throw has gone out.
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
## Seconds a CPU taker waits before auto-throwing. Gives GameManager/
## SetPieceCoordinator a frame to finish placing the ball before the throw is
## evaluated, so the CPU doesn't fire at charge_ratio 0 on its very first tick.
const CPU_THROW_DELAY: float = 0.1
## A throw released this close to the taker is still accepted even if it falls
## a pixel or two outside the foot sensor's radius due to placement rounding.
const NEARBY_BALL_RADIUS: float = 40.0

## 0.0-1.0, read by PlayerStateFactory.get_charge_ratio() for the HUD meter.
var charge_ratio: float = 0.0

var _held_time: float = 0.0
var _held: bool = false
## True from the moment the throw is released. Once set, the foot sensor is
## never consulted again for this state's remaining lifetime.
var _released: bool = false
var _cpu_timer: float = 0.0


func enter(_player: HeavyPlayerController) -> void:
	_held_time = 0.0
	_held = false
	_released = false
	_cpu_timer = 0.0
	charge_ratio = 0.0


func exit(_player: HeavyPlayerController) -> void:
	charge_ratio = 0.0


func process(player: HeavyPlayerController, delta: float) -> StringName:
	# Defense in depth: once released, never re-derive state from the foot
	# sensor, regardless of how we got here.
	if _released:
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	# CPU takers have no button to hold. Wait one beat, then release at half
	# charge rather than reading Input directly, which would pick up the
	# human's device instead.
	if not player.is_user_controlled:
		_cpu_timer += delta
		if _cpu_timer >= CPU_THROW_DELAY:
			charge_ratio = 0.5
			_held_time = CHARGE_TIME * charge_ratio
			_release_throw(player)
			return MOVE if player.movement_intent.length() > 0.05 else IDLE
		return &""

	if wants(player, &"action_kick"):
		_held = true
		_held_time += delta
		charge_ratio = clampf(_held_time / CHARGE_TIME, 0.0, 1.0)
	elif _held:
		_release_throw(player)
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	# Planted: friction only, same as the charge-kick wind-up.
	player.apply_kinematic_weight(Vector2.ZERO, delta)


func _release_throw(player: HeavyPlayerController) -> void:
	if _released:
		return

	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball == null:
		ball = _find_nearby_ball(player, NEARBY_BALL_RADIUS)

	if ball == null:
		# Nothing to throw — the phase may have already moved on elsewhere.
		_released = true
		return

	# Someone else grabbed the ball before the throw fired; do nothing.
	if ball.possessor != null and ball.possessor != player:
		_released = true
		return

	var aim: Vector2 = Vector2.ZERO
	if player.is_user_controlled:
		aim = InputHelper.get_aim_vector()
	if aim == Vector2.ZERO:
		aim = player.facing_direction

	var speed: float = lerpf(MIN_SPEED, MAX_SPEED, charge_ratio)
	# Flat trajectory is the point of a throw-in — impulse_z stays 0.
	ball.apply_kick(aim.normalized() * speed, 0.0, player)
	player.show_action_text("THROW")
	GameEvents.ball_struck.emit(player, speed, charge_ratio)
	GameManager.restart_play()

	# Set after apply_kick so the ball's velocity is already committed.
	_released = true


func _find_nearby_ball(player: HeavyPlayerController, radius: float) -> Pseudo3DBall:
	var balls: Array[Node] = player.get_tree().get_nodes_in_group(&"ball")
	for node: Node in balls:
		var b := node as Pseudo3DBall
		if b == null or b.is_frozen:
			continue
		if player.global_position.distance_to(b.global_position) <= radius:
			return b
	return null
