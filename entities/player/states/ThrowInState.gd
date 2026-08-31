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
## A hand-thrown restart is physically weaker than a kicked ball — MAX_SPEED
## is capped at ChargeKickState.PASS_SPEED (260.0) rather than exceeding it.
## Previously 300.0-700.0, which made even a lightly-charged throw-in faster
## than ChargeKickState.PASS_SPEED (260.0) and a fully-charged one faster
## than SHOT_SPEED (620.0) — a two-handed overhead toss out-pacing a
## full-power kicked strike, which is why throws were crossing the full
## width of the pitch. See AGENTS_ERRATA.md
## (throw-in-speed-exceeds-kicked-shot-speed).
const MIN_SPEED: float = 120.0
const MAX_SPEED: float = 260.0
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

	# CPU takers use PlayerBrain to find a target.
	if not player.is_user_controlled:
		var brain: Node = player.get_node_or_null("PlayerBrain")
		if brain != null and brain.get("current_action") == &"Pass":
			_held = true
			_held_time += delta
			charge_ratio = clampf(_held_time / CHARGE_TIME, 0.0, 1.0)
			if charge_ratio >= 0.5:
				_release_throw(player)
				return MOVE if player.movement_intent.length() > 0.05 else IDLE
		else:
			_held = false
			charge_ratio = 0.0
		return &""

	if wants(player, &"action_kick"):
		_held = true
		_held_time += delta
		charge_ratio = clampf(_held_time / CHARGE_TIME, 0.0, 1.0)
		if charge_ratio >= 1.0:
			_release_throw(player)
			return MOVE if player.movement_intent.length() > 0.05 else IDLE
	elif _held:
		_release_throw(player)
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	# Project the movement vector so the player can ONLY move parallel to the touchline.
	var intent: Vector2 = player.movement_intent
	intent.y = 0.0
	player.apply_kinematic_weight(intent, delta)


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
	var ai_brain: PlayerBrain = player.brain
	var pass_target: HeavyPlayerController = null
	if not player.is_user_controlled and ai_brain != null:
		pass_target = ai_brain.get("_cached_pass_target") as HeavyPlayerController
		if pass_target != null:
			aim = (pass_target.global_position + pass_target.velocity * 0.3) - player.global_position

	if player.is_user_controlled:
		aim = InputHelper.get_aim_vector()
	if aim == Vector2.ZERO:
		aim = player.facing_direction

	var speed: float = lerpf(MIN_SPEED, MAX_SPEED, charge_ratio)
	# Apply 3D impulse so the ball is lobbed into play. Pseudo3DBall.
	# air_resistance (0.08) is a slow exponential decay — the ball keeps
	# almost all of its horizontal speed for the whole time it's airborne,
	# unlike the much stronger ground friction. A long hang time therefore
	# directly multiplies total throw distance on top of MIN/MAX_SPEED, so
	# this is scaled down proportionately with the speed reduction above
	# rather than left at its old range (150.0-350.0) while only the
	# horizontal speed was fixed.
	var z_impulse: float = lerpf(60.0, 150.0, charge_ratio)
	ball.apply_kick(aim.normalized() * speed, z_impulse, player)

	if not player.is_user_controlled and pass_target != null:
		var trust_sys: TrustSystem = player.get_trust_system() if player.has_method(&"get_trust_system") else null
		if trust_sys != null:
			trust_sys.register_pass(TrustSystem.player_key(pass_target))
		var target_brain: PlayerBrain = pass_target.brain
		if target_brain != null:
			target_brain.set(&"_pass_lock_timer", 0.35)
			target_brain.set(&"_pass_lock_passer", ball.possessor)
	
	player.show_action_text("THROW")
	GameEvents.ball_struck.emit(player, speed, charge_ratio, false)
	MatchStatsTracker.record_pass_attempt(player, MatchStatsTracker.is_pass_toward_teammate(player, aim))
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
