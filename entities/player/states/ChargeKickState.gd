##
## ChargeKickState
##
## Hold-to-charge passing and shooting. Commitment is the point: a tap plays a
## safe short pass, a full hold is a high-risk strike, and the charge is spent
## whether or not the contact is clean.
##
##   tap  (< TAP_THRESHOLD)  -> short ground pass at PASS_SPEED
##   hold (up to CHARGE_TIME) -> power scales linearly to SHOT_SPEED
##
## Aim comes from the right stick, falling back to the run direction, so the
## mechanic works one-handed and on the keyboard.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, InputHelper,
## MoodSystem (kick accuracy scatter at high charge).
## Exposes: the PlayerState interface plus charge_ratio (read by the HUD meter).
##

class_name ChargeKickState
extends PlayerState

## Seconds of hold to reach a full-power strike.
const CHARGE_TIME: float = 0.8
## Holds shorter than this resolve as a tapped pass.
const TAP_THRESHOLD: float = 0.15
const PASS_SPEED: float = 260.0
const SHOT_SPEED: float = 620.0
## Vertical launch speed applied to a lobbed ball at full charge.
const LOB_HEIGHT_SPEED: float = 420.0
## Movement is throttled while winding up — you plant to strike.
const CHARGE_MOVE_PENALTY: float = 0.55
## Maximum distance at which a mis-timed shot still finds the ball, so a
## charge that ends a pixel or two outside the foot sensor doesn't silently
## whiff.
const CONTACT_REACH: float = 48.0
## Lockout duration applied to the kicker's foot sensor so a struck ball isn't
## immediately re-possessed on release frames.
const PASS_RELEASE_LOCKOUT: float = 0.50

## 0.0-1.0, read by HUD.gd for the power meter.
var charge_ratio: float = 0.0

var _held_time: float = 0.0
var _is_lob: bool = false
var _aim_accumulator: Vector2 = Vector2.ZERO

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func enter(player: HeavyPlayerController) -> void:
	_held_time = 0.0
	charge_ratio = 0.0
	_aim_accumulator = Vector2.ZERO
	_is_lob = wants(player, &"action_lob")


func exit(_player: HeavyPlayerController) -> void:
	charge_ratio = 0.0


func process(player: HeavyPlayerController, delta: float) -> StringName:
	# Super Cancel: purge the wind-up and hand control straight back.
	if just_wants(player, &"action_cancel"):
		return IDLE

	_held_time += delta
	var raw_ratio: float = clampf(_held_time / CHARGE_TIME, 0.0, 1.0)
	# Eased power ratio (quadratic easing curve)
	charge_ratio = raw_ratio * raw_ratio

	if player.is_user_controlled:
		var aim_input: Vector2 = InputHelper.get_aim_vector()
		if aim_input != Vector2.ZERO:
			_aim_accumulator += aim_input * delta

	var still_held: bool = wants(player, &"action_kick")
	if still_held and raw_ratio < 1.0:
		return &""

	_release_kick(player)
	player.ball_control_lockout = PASS_RELEASE_LOCKOUT

	return MOVE if player.movement_intent.length() > 0.05 else IDLE


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	player.apply_kinematic_weight(player.movement_intent * CHARGE_MOVE_PENALTY, delta)


func _release_kick(player: HeavyPlayerController) -> void:
	# Prefer a ball already inside the foot sensor.
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()

	# Fallback: no ball in the sensor, but one is within CONTACT_REACH px —
	# snap it to foot position and strike anyway. Prevents a genuine "swung
	# and missed" from degrading into a 1px sensor-edge whiff.
	if ball == null:
		ball = _nearest_ground_ball(player)
		if ball != null:
			ball.global_position = player.global_position + player.facing_direction * 16.0

	if ball == null:
		# Swung and missed — the charge is spent regardless.
		return

	var aim: Vector2 = _get_resolved_aim(player)

	var is_tap: bool = _held_time < TAP_THRESHOLD
	var cpu_brain: PlayerBrain = player.brain as PlayerBrain if not player.is_user_controlled else null
	# CPU set-piece tuning: Goal kicks, corner kicks, and free kicks
	if not player.is_user_controlled and GameManager.is_set_piece_active():
		if GameManager.current_phase == GameManager.MatchPhase.GOAL_KICK:
			is_tap = false
			charge_ratio = 0.85
			_is_lob = true
		elif GameManager.current_phase == GameManager.MatchPhase.CORNER_KICK:
			is_tap = false
			charge_ratio = 0.70
			_is_lob = true
		elif GameManager.current_phase == GameManager.MatchPhase.FREE_KICK:
			if cpu_brain != null and cpu_brain.has_free_kick_intent():
				is_tap = cpu_brain.free_kick_is_tap
				charge_ratio = cpu_brain.free_kick_charge_ratio
				_is_lob = cpu_brain.free_kick_is_lob

	var speed: float = PASS_SPEED if is_tap else lerpf(PASS_SPEED, SHOT_SPEED, charge_ratio)
	var height: float = 0.0
	if _is_lob:
		var lob_dist: float = lerpf(180.0, 450.0, charge_ratio)
		height = _calculate_lob_velocity_z(lob_dist, speed, ball.gravity)

	# Inherit momentum directionally: only the component of the striker's run
	# that pushes along the aim adds weight, so a cross-body strike is not
	# artificially boosted by sideways run speed.
	var run_dot: float = clampf(player.velocity.normalized().dot(aim), 0.0, 1.0)
	var inherited: Vector2 = aim * (player.velocity.length() * run_dot * 0.30)

	# Accuracy scatter: at full charge, mood determines how much aim jitter applies.
	# A streaking player is locked in; a slumping one sprays the ball.
	var mood_node: MoodSystem = player.get_mood()
	var scatter_mult: float = mood_node.get_kick_accuracy_scatter_multiplier() if mood_node != null else 1.0
	var max_scatter_angle: float = deg_to_rad(12.0) * charge_ratio * scatter_mult
	if max_scatter_angle > 0.001:
		_rng.seed = player.get_instance_id() + GameManager.get_match_tick()
		var scatter: float = clampf(_gaussian_scatter(max_scatter_angle * 0.4), -max_scatter_angle, max_scatter_angle)
		aim = aim.rotated(scatter)

	ball.apply_kick(aim * speed + inherited, height, player)
	if not is_tap and charge_ratio > 0.65:
		GameEvents.powerful_shot_landed.emit(player, speed, charge_ratio)

	var action_label: String
	if not player.is_user_controlled and GameManager.is_set_piece_active():
		if GameManager.current_phase == GameManager.MatchPhase.FREE_KICK and cpu_brain != null and cpu_brain.has_free_kick_intent():
			action_label = cpu_brain.free_kick_action_label
		elif GameManager.current_phase == GameManager.MatchPhase.GOAL_KICK:
			action_label = "GOAL KICK"
		elif GameManager.current_phase == GameManager.MatchPhase.CORNER_KICK:
			action_label = "CROSS"
		elif is_tap:
			action_label = "PASS"
		elif _is_lob:
			action_label = "LOB SHOT"
		else:
			action_label = "SHOT"
	elif is_tap:
		action_label = "PASS"
	elif _is_lob:
		action_label = "LOB SHOT"
	var label_color: Color = Color.WHITE
	if action_label == "SHOT" or action_label == "LOB SHOT":
		label_color = Color(1.0, 0.92, 0.35)
	elif action_label == "CROSS":
		label_color = Color(0.40, 0.85, 1.0)
	elif action_label == "PASS":
		label_color = Color(0.85, 0.95, 1.0)
	player.show_action_text(action_label, label_color)

	GameEvents.ball_struck.emit(player, speed, charge_ratio, not is_tap)

	if is_tap or action_label == "PASS":
		MatchStatsTracker.record_pass_attempt(player, MatchStatsTracker.is_pass_toward_teammate(player, aim))

	if player.is_user_controlled:
		InputHelper.rumble(0.25 * charge_ratio, 0.6 * charge_ratio, 0.12)


func _get_resolved_aim(player: HeavyPlayerController) -> Vector2:
	if _aim_accumulator.length_squared() > 0.001:
		return _aim_accumulator.normalized()
	if player.is_user_controlled:
		var instant_aim: Vector2 = InputHelper.get_aim_vector()
		if instant_aim != Vector2.ZERO:
			return instant_aim.normalized()
	return player.facing_direction


func _calculate_lob_velocity_z(distance: float, speed_xy: float, gravity: float = 580.0) -> float:
	var safe_speed: float = maxf(speed_xy, 100.0)
	var safe_dist: float = maxf(distance, 50.0)
	var vz: float = (gravity * safe_dist) / (1.8 * safe_speed)
	return clampf(vz, 120.0, 480.0)


## Box–Muller Gaussian sample scaled to `sigma`. Only mutates _rng state, no
## other side effects.
func _gaussian_scatter(sigma: float) -> float:
	var u1: float = maxf(_rng.randf(), 0.0001)
	var u2: float = _rng.randf()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2) * sigma


func _nearest_ground_ball(player: HeavyPlayerController) -> Pseudo3DBall:
	var balls: Array[Node] = player.get_tree().get_nodes_in_group(&"ball")
	var closest: Pseudo3DBall = null
	var closest_dist: float = CONTACT_REACH
	for node: Node in balls:
		var b := node as Pseudo3DBall
		if b == null or b.is_frozen or b.is_airborne():
			continue
		if b.possessor != null and b.possessor != player:
			continue
		var d: float = player.global_position.distance_to(b.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = b
	return closest
