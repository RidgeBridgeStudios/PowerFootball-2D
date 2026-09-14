##
## CenterRefereeVisual
##
## The on-pitch visual arbiter running the Diagonal System of Control (DSC).
## Sprints along the diagonal corridor to maintain clear sightlines between the ball
## and the lead assistant referee, navigates around player congestion, rushes to foul
## incidents, and executes animated yellow/red card presentations with visual flares.
##
## Zero physical collision: purely a visual/kinematic Node2D agent.
## Choke point: queries ball/player positions exclusively via MatchWorldModel.
##
## Depends on: MatchWorldModel, PitchBoundary, RefereeData.
## Exposes: bind(boundary, referee_data), respond_to_foul(pos),
##          present_yellow_card(player_pos), present_red_card(player_pos),
##          gesture_restart(target_pos), reset_position()
##

class_name CenterRefereeVisual
extends Node2D

enum State {
	PATROL_DIAGONAL,       ## Running the diagonal system of control during open play
	RUSH_TO_INCIDENT,      ## Sprinting directly to foul / contested incident spot
	PRESENTING_CARD,       ## Halting in front of player, holding yellow/red card high with flare
	GESTURING_RESTART,     ## Arm extended pointing to restart location
	POST_MATCH_CEREMONY    ## Walking to center spot for half-time / full-time
}

enum CardType {
	NONE,
	YELLOW,
	RED
}

## Kinematic speeds (px/sec)
const SPEED_WALK: float = 110.0
const SPEED_JOG: float = 195.0
const SPEED_SPRINT: float = 330.0
const ACCELERATION: float = 950.0
const FRICTION: float = 1200.0

## Tactical observation distances
const IDEAL_BALL_DISTANCE: float = 180.0
const MIN_BALL_DISTANCE: float = 120.0
const MAX_BALL_DISTANCE: float = 260.0
const AVOID_PLAYER_RADIUS: float = 65.0

## Visual dimensions
const BODY_RADIUS: float = 7.0
const SHADOW_OFFSET_Y: float = 5.0
const CARD_HOLD_DURATION: float = 2.8

var _boundary: PitchBoundary = null
var _referee_data: RefereeData = null

var _state: State = State.PATROL_DIAGONAL
var _current_card: CardType = CardType.NONE
var _card_timer: float = 0.0
var _card_flare_alpha: float = 0.0
var _card_flare_scale: float = 1.0

var _velocity: Vector2 = Vector2.ZERO
var _facing_direction: Vector2 = Vector2.RIGHT
var _incident_target: Vector2 = Vector2.ZERO
var _gesture_target: Vector2 = Vector2.ZERO
var _gesture_timer: float = 0.0

## Uniform colors (High-visibility neon green/yellow kit with black referee shorts)
const COLOR_JERSEY: Color = Color(0.88, 0.98, 0.15, 1.0)
const COLOR_COLLAR: Color = Color(0.12, 0.12, 0.14, 1.0)
const COLOR_SHORTS: Color = Color(0.10, 0.10, 0.12, 1.0)
const COLOR_BADGE: Color = Color(0.20, 0.20, 0.22, 1.0)
const COLOR_CARD_YELLOW: Color = Color(1.0, 0.88, 0.05, 1.0)
const COLOR_CARD_RED: Color = Color(0.95, 0.12, 0.15, 1.0)
const COLOR_SKIN: Color = Color(0.92, 0.74, 0.58, 1.0)


func _ready() -> void:
	z_index = 2


func bind(boundary: PitchBoundary, data: RefereeData) -> void:
	_boundary = boundary
	_referee_data = data
	reset_position()


func reset_position() -> void:
	_state = State.PATROL_DIAGONAL
	_velocity = Vector2.ZERO
	_current_card = CardType.NONE
	_card_timer = 0.0
	_gesture_timer = 0.0
	if _boundary != null:
		global_position = _boundary.get_centre_spot() + Vector2(-60.0, -40.0)
	else:
		global_position = Vector2(-60.0, -40.0)
	_facing_direction = Vector2.RIGHT
	queue_redraw()


func _physics_process(delta: float) -> void:
	match _state:
		State.PATROL_DIAGONAL:
			_tick_patrol(delta)
		State.RUSH_TO_INCIDENT:
			_tick_rush(delta)
		State.PRESENTING_CARD:
			_tick_card_presentation(delta)
		State.GESTURING_RESTART:
			_tick_gesture(delta)
		State.POST_MATCH_CEREMONY:
			_tick_ceremony(delta)

	# Apply kinematic velocity
	if not _velocity.is_zero_approx():
		global_position += _velocity * delta
		_clamp_to_pitch()
		if _velocity.length_squared() > 100.0:
			_facing_direction = _facing_direction.lerp(_velocity.normalized(), delta * 8.0).normalized()

	queue_redraw()


## --- Diagonal System of Control (DSC) Movement -----------------------------

func _tick_patrol(delta: float) -> void:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return

	var ball_pos: Vector2 = world.ball_position
	var ball_vel: Vector2 = world.ball_velocity

	# Target diagonal: The line runs roughly from quadrant II (-X, -Y) to quadrant IV (+X, +Y).
	# This keeps the center ref opposite the lead linesman (AR1 top right, AR2 bottom left).
	var target_pos: Vector2 = _compute_dsc_target(ball_pos, ball_vel)

	# Avoid stepping onto crowded players
	target_pos = _apply_player_avoidance(target_pos)

	# Steer toward target
	var to_target: Vector2 = target_pos - global_position
	var dist: float = to_target.length()

	var desired_speed: float = SPEED_WALK
	if dist > 200.0 or ball_vel.length() > 400.0:
		desired_speed = SPEED_SPRINT
	elif dist > 80.0:
		desired_speed = SPEED_JOG

	if dist > 15.0:
		var desired_vel: Vector2 = to_target.normalized() * desired_speed
		_velocity = _velocity.move_toward(desired_vel, ACCELERATION * delta)
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, FRICTION * delta)

	# Face towards ball
	if ball_pos.distance_squared_to(global_position) > 25.0:
		var to_ball: Vector2 = (ball_pos - global_position).normalized()
		_facing_direction = _facing_direction.lerp(to_ball, delta * 6.0).normalized()


func _compute_dsc_target(ball_pos: Vector2, ball_vel: Vector2) -> Vector2:
	if _boundary == null:
		return ball_pos + Vector2(-120.0, -80.0)

	var pitch_rect: Rect2 = _boundary.get_pitch_rect()
	var half_w: float = pitch_rect.size.x * 0.45
	var half_h: float = pitch_rect.size.y * 0.40

	# Ideal diagonal offset:
	# When ball is in +X half, ref favors lower side (+Y offset) so AR1 (top) has unobstructed view.
	# When ball is in -X half, ref favors upper side (-Y offset) so AR2 (bottom) has unobstructed view.
	var side_bias_y: float = (ball_pos.x / maxf(half_w, 1.0)) * (half_h * 0.55)

	# Observation offset vector: stays behind and to the diagonal side of play
	var attack_dir_x: float = 1.0 if ball_vel.x >= 0.0 else -1.0
	var offset_x: float = -attack_dir_x * IDEAL_BALL_DISTANCE * 0.85
	var offset_y: float = side_bias_y

	# Clamp offset distance within comfort band
	var target: Vector2 = ball_pos + Vector2(offset_x, offset_y)
	target.x = clampf(target.x, pitch_rect.position.x + 60.0, pitch_rect.end.x - 60.0)
	target.y = clampf(target.y, pitch_rect.position.y + 50.0, pitch_rect.end.y - 50.0)

	return target


func _apply_player_avoidance(target: Vector2) -> Vector2:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return target

	var push_vector: Vector2 = Vector2.ZERO
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		if not world.is_slot_live(i):
			continue
		var player_pos: Vector2 = world.player_positions[i]
		var d_sq: float = target.distance_squared_to(player_pos)
		if d_sq < AVOID_PLAYER_RADIUS * AVOID_PLAYER_RADIUS and d_sq > 1.0:
			var d: float = sqrt(d_sq)
			var push_dir: Vector2 = (target - player_pos) / d
			var strength: float = (AVOID_PLAYER_RADIUS - d) / AVOID_PLAYER_RADIUS
			push_vector += push_dir * strength * 45.0

	return target + push_vector


func _clamp_to_pitch() -> void:
	if _boundary == null:
		return
	var rect: Rect2 = _boundary.get_pitch_rect()
	global_position.x = clampf(global_position.x, rect.position.x + 25.0, rect.end.x - 25.0)
	global_position.y = clampf(global_position.y, rect.position.y + 25.0, rect.end.y - 25.0)


## --- Incident & Card Presentation -------------------------------------------

func respond_to_foul(foul_pos: Vector2) -> void:
	_incident_target = foul_pos
	_state = State.RUSH_TO_INCIDENT


func present_yellow_card(player_pos: Vector2) -> void:
	_incident_target = player_pos
	_current_card = CardType.YELLOW
	_card_timer = CARD_HOLD_DURATION
	_card_flare_alpha = 1.0
	_card_flare_scale = 0.4
	_state = State.PRESENTING_CARD


func present_red_card(player_pos: Vector2) -> void:
	_incident_target = player_pos
	_current_card = CardType.RED
	_card_timer = CARD_HOLD_DURATION + 0.6
	_card_flare_alpha = 1.0
	_card_flare_scale = 0.4
	_state = State.PRESENTING_CARD


func gesture_restart(target_pos: Vector2) -> void:
	_gesture_target = target_pos
	_gesture_timer = 1.8
	_state = State.GESTURING_RESTART


func _tick_rush(delta: float) -> void:
	var to_target: Vector2 = _incident_target - global_position
	var dist: float = to_target.length()

	if dist > 45.0:
		var desired_vel: Vector2 = to_target.normalized() * SPEED_SPRINT
		_velocity = _velocity.move_toward(desired_vel, ACCELERATION * 1.5 * delta)
		_facing_direction = to_target.normalized()
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		if dist <= 48.0 and _current_card == CardType.NONE:
			_state = State.PATROL_DIAGONAL


func _tick_card_presentation(delta: float) -> void:
	var to_player: Vector2 = _incident_target - global_position
	var dist: float = to_player.length()

	if dist > 48.0:
		var desired_vel: Vector2 = to_player.normalized() * SPEED_SPRINT
		_velocity = _velocity.move_toward(desired_vel, ACCELERATION * 1.5 * delta)
		_facing_direction = to_player.normalized()
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, FRICTION * 1.8 * delta)
		if dist > 5.0:
			_facing_direction = to_player.normalized()

	_card_timer -= delta
	_card_flare_scale = minf(_card_flare_scale + delta * 2.5, 1.3)
	if _card_timer < 0.6:
		_card_flare_alpha = maxf(_card_timer / 0.6, 0.0)
	else:
		_card_flare_alpha = 0.95 + sin(Time.get_ticks_msec() * 0.012) * 0.05

	if _card_timer <= 0.0:
		_current_card = CardType.NONE
		_state = State.PATROL_DIAGONAL


func _tick_gesture(delta: float) -> void:
	_velocity = _velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	if (_gesture_target - global_position).length_squared() > 10.0:
		_facing_direction = (_gesture_target - global_position).normalized()

	_gesture_timer -= delta
	if _gesture_timer <= 0.0:
		_state = State.PATROL_DIAGONAL


func _tick_ceremony(delta: float) -> void:
	var center_spot: Vector2 = _boundary.get_centre_spot() if _boundary != null else Vector2.ZERO
	var to_center: Vector2 = center_spot - global_position
	var dist: float = to_center.length()

	if dist > 20.0:
		_velocity = _velocity.move_toward(to_center.normalized() * SPEED_WALK, ACCELERATION * delta)
		_facing_direction = to_center.normalized()
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, FRICTION * delta)


## --- Visual Rendering -------------------------------------------------------

func _draw() -> void:
	# 1. Shadow
	var shadow_pos: Vector2 = Vector2(0.0, SHADOW_OFFSET_Y)
	draw_circle(shadow_pos, BODY_RADIUS * 1.05, Color(0.0, 0.0, 0.0, 0.38))

	# 2. Main Body & High-Vis Uniform
	draw_circle(Vector2.ZERO, BODY_RADIUS, COLOR_JERSEY)

	# 3. Black referee shorts & collar accents
	var facing_angle: float = _facing_direction.angle()
	var back_dir: Vector2 = -_facing_direction * (BODY_RADIUS * 0.45)
	draw_circle(back_dir, BODY_RADIUS * 0.55, COLOR_SHORTS)

	# 4. Referee badge on chest (small dark rectangle/circle on left chest)
	var badge_pos: Vector2 = _facing_direction.rotated(0.6) * (BODY_RADIUS * 0.45)
	draw_rect(Rect2(badge_pos - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), COLOR_BADGE, true)

	# 5. Head / Skin
	var head_pos: Vector2 = _facing_direction * (BODY_RADIUS * 0.25)
	draw_circle(head_pos, BODY_RADIUS * 0.45, COLOR_SKIN)

	# 6. Card Presentation Visual & Flare
	if _state == State.PRESENTING_CARD and _current_card != CardType.NONE:
		_draw_card_and_flare()
	elif _state == State.GESTURING_RESTART:
		_draw_gesture_arm()


func _draw_card_and_flare() -> void:
	var card_color: Color = COLOR_CARD_YELLOW if _current_card == CardType.YELLOW else COLOR_CARD_RED

	# Arm extended high
	var arm_offset: Vector2 = _facing_direction.rotated(-0.5) * (BODY_RADIUS + 9.0)
	draw_line(Vector2.ZERO, arm_offset, COLOR_SKIN, 2.5)

	# Card rectangle held in hand
	var card_center: Vector2 = arm_offset + Vector2(0.0, -8.0)
	var card_rect := Rect2(card_center - Vector2(4.5, 6.5), Vector2(9.0, 13.0))

	# Card shadow / border
	draw_rect(card_rect.grow(1.0), Color(0.1, 0.1, 0.1, 0.9), false, 1.0)
	# Card body
	draw_rect(card_rect, card_color, true)

	# Card visual flare: glowing aura + 4-pointed star rays
	if _card_flare_alpha > 0.05:
		var flare_col: Color = card_color
		flare_col.a = _card_flare_alpha * 0.45
		var aura_radius: float = 16.0 * _card_flare_scale
		draw_circle(card_center, aura_radius, flare_col)

		# Star rays
		var ray_len: float = 24.0 * _card_flare_scale
		var ray_col: Color = Color(1.0, 1.0, 1.0, _card_flare_alpha * 0.85)
		draw_line(card_center - Vector2(ray_len, 0.0), card_center + Vector2(ray_len, 0.0), ray_col, 1.5)
		draw_line(card_center - Vector2(0.0, ray_len), card_center + Vector2(0.0, ray_len), ray_col, 1.5)
		var diag_len: float = ray_len * 0.6
		draw_line(card_center - Vector2(diag_len, diag_len), card_center + Vector2(diag_len, diag_len), ray_col, 1.0)
		draw_line(card_center - Vector2(-diag_len, diag_len), card_center + Vector2(-diag_len, diag_len), ray_col, 1.0)


func _draw_gesture_arm() -> void:
	var arm_end: Vector2 = _facing_direction * (BODY_RADIUS + 12.0)
	draw_line(Vector2.ZERO, arm_end, COLOR_SKIN, 2.5)
	draw_circle(arm_end, 2.0, COLOR_JERSEY)
