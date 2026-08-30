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
## Vertical launch speed applied to a lobbed ball at full charge. 420 puts the
## apex around 150px, which reads clearly as a cross against the 900px pitch and
## sits well above the 50px aerial-challenge threshold.
const LOB_HEIGHT_SPEED: float = 420.0
## Movement is throttled while winding up — you plant to strike.
const CHARGE_MOVE_PENALTY: float = 0.55
## Maximum distance at which a mis-timed shot still finds the ball, so a
## charge that ends a pixel or two outside the foot sensor doesn't silently
## whiff.
const CONTACT_REACH: float = 48.0

## 0.0-1.0, read by HUD.gd for the power meter.
var charge_ratio: float = 0.0

var _held_time: float = 0.0
var _is_lob: bool = false


func enter(player: HeavyPlayerController) -> void:
	_held_time = 0.0
	charge_ratio = 0.0
	_is_lob = wants(player, &"action_lob")


func exit(_player: HeavyPlayerController) -> void:
	charge_ratio = 0.0


func process(player: HeavyPlayerController, delta: float) -> StringName:
	# Super Cancel: purge the wind-up and hand control straight back.
	if just_wants(player, &"action_cancel"):
		return IDLE

	_held_time += delta
	charge_ratio = clampf(_held_time / CHARGE_TIME, 0.0, 1.0)

	var still_held: bool = wants(player, &"action_kick")
	if still_held and charge_ratio < 1.0:
		return &""

	_release_kick(player)

	# Corner, free and goal kicks are all taken through this state (see
	# SetPieceCoordinator._activate_set_piece). apply_kick() only sets the
	# ball's velocity — it moves on its own next _physics_process tick — so
	# the foot sensor still reports it as overlapping on this exact frame.
	# In a set-piece context that stale overlap must never be read as "still
	# have the ball": the taker just struck a dead ball away and cannot
	# immediately resume dribbling it.
	if GameManager.is_set_piece_active():
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	if player.get_ball_in_foot_range() != null:
		return DRIBBLE
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

	var aim: Vector2 = Vector2.ZERO
	if player.is_user_controlled:
		aim = InputHelper.get_aim_vector()
	if aim == Vector2.ZERO:
		aim = player.facing_direction

	var is_tap: bool = _held_time < TAP_THRESHOLD
	var speed: float = PASS_SPEED if is_tap else lerpf(PASS_SPEED, SHOT_SPEED, charge_ratio)
	var height: float = 0.0
	if _is_lob:
		height = LOB_HEIGHT_SPEED * maxf(charge_ratio, 0.4)

	# Inherit a slice of the striker's momentum: running onto a ball produces a
	# heavier strike than a standing one.
	var inherited: Vector2 = player.velocity * 0.25

	# Accuracy scatter: at full charge, mood determines how much aim jitter applies.
	# A streaking player is locked in; a slumping one sprays the ball.
	var mood_node: MoodSystem = player.get_mood()
	var scatter_mult: float = mood_node.get_kick_accuracy_scatter_multiplier() if mood_node != null else 1.0
	var max_scatter_angle: float = deg_to_rad(12.0) * charge_ratio * scatter_mult
	if max_scatter_angle > 0.001:
		aim = aim.rotated(randf_range(-max_scatter_angle, max_scatter_angle))

	ball.apply_kick(aim * speed + inherited, height, player)

	var action_label: String
	if is_tap:
		action_label = "PASS"
	elif _is_lob:
		action_label = "LOB SHOT"
	else:
		action_label = "SHOT"
	player.show_action_text(action_label)

	GameEvents.ball_struck.emit(player, speed, charge_ratio, not is_tap)

	if is_tap:
		MatchStatsTracker.record_pass_attempt(player, MatchStatsTracker.is_pass_toward_teammate(player, aim))

	if player.is_user_controlled:
		InputHelper.rumble(0.25 * charge_ratio, 0.6 * charge_ratio, 0.12)

	# TODO: split action_through into a lead-the-runner pass target.


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
