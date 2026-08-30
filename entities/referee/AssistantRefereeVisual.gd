##
## AssistantRefereeVisual
##
## Touchline match official (Linesman) patrolling the boundary line.
## Dynamically mirrors the 2nd-to-last defender's position (the offside line) or the
## ball across their assigned half of the pitch, and executes animated flag signals
## for offside, throw-ins, corner kicks, and goal kicks.
##
## Zero physical collision: purely a visual/kinematic Node2D agent outside the pitch.
## Choke point: queries defensive lines and ball positions exclusively via MatchWorldModel.
##
## Depends on: MatchWorldModel, PitchBoundary.
## Exposes: bind(boundary, is_top_touchline), signal_offside(),
##          signal_throw_in(direction_x), signal_corner(corner_pos),
##          signal_goal_kick(), reset_flag()
##

class_name AssistantRefereeVisual
extends Node2D

enum FlagSignal {
	IDLE_DOWN,        ## Flag held lowered along side
	RAISED_OFFSIDE,   ## Flag held straight up vertically (offside call)
	SIGNAL_THROWIN,   ## Flag pointed at 45 deg angle in attack direction
	SIGNAL_CORNER,    ## Flag pointed down toward corner flag
	SIGNAL_GOALKICK   ## Flag pointed horizontally toward 6-yard box
}

const SPEED_PATROL: float = 240.0
const ACCELERATION: float = 850.0
const FRICTION: float = 1100.0

const BODY_RADIUS: float = 6.5
const SHADOW_OFFSET_Y: float = 4.0
const TOUCHLINE_OFFSET_Y: float = 18.0

var is_top_touchline: bool = true
var _boundary: PitchBoundary = null

var _flag_state: FlagSignal = FlagSignal.IDLE_DOWN
var _flag_timer: float = 0.0
var _throwin_direction: float = 1.0

var _velocity_x: float = 0.0
var _facing_direction: Vector2 = Vector2.DOWN
var _patrol_min_x: float = 0.0
var _patrol_max_x: float = 0.0
var _fixed_y: float = 0.0

## Uniform & Flag colors
const COLOR_JERSEY: Color = Color(0.88, 0.98, 0.15, 1.0)
const COLOR_SHORTS: Color = Color(0.10, 0.10, 0.12, 1.0)
const COLOR_FLAG_YELLOW: Color = Color(1.0, 0.85, 0.05, 1.0)
const COLOR_FLAG_RED: Color = Color(0.92, 0.15, 0.15, 1.0)
const COLOR_SKIN: Color = Color(0.92, 0.74, 0.58, 1.0)
const COLOR_POLE: Color = Color(0.25, 0.25, 0.28, 1.0)


func _ready() -> void:
	z_index = 2


func bind(boundary: PitchBoundary, top_touchline: bool) -> void:
	_boundary = boundary
	is_top_touchline = top_touchline
	_recompute_bounds()
	reset_flag()


func _recompute_bounds() -> void:
	if _boundary == null:
		return
	var rect: Rect2 = _boundary.get_pitch_rect()
	var half_w: float = rect.size.x * 0.5
	var half_h: float = rect.size.y * 0.5

	if is_top_touchline:
		# AR1 covers Top touchline on the RIGHT half (Team 1 defending side / +X half)
		_fixed_y = rect.position.y - TOUCHLINE_OFFSET_Y
		_patrol_min_x = -30.0
		_patrol_max_x = half_w + 10.0
		_facing_direction = Vector2.DOWN
		global_position = Vector2(half_w * 0.5, _fixed_y)
	else:
		# AR2 covers Bottom touchline on the LEFT half (Team 0 defending side / -X half)
		_fixed_y = rect.end.y + TOUCHLINE_OFFSET_Y
		_patrol_min_x = -half_w - 10.0
		_patrol_max_x = 30.0
		_facing_direction = Vector2.UP
		global_position = Vector2(-half_w * 0.5, _fixed_y)


func _physics_process(delta: float) -> void:
	_tick_offside_tracking(delta)
	_tick_flag_signal(delta)
	queue_redraw()


## --- Offside Line & Touchline Tracking --------------------------------------

func _tick_offside_tracking(delta: float) -> void:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or _boundary == null:
		return

	# Determine target X position (tracking 2nd last defender or ball in this half)
	var defending_team: int = 1 if is_top_touchline else 0
	var target_x: float = _compute_target_x(world, defending_team)

	target_x = clampf(target_x, _patrol_min_x, _patrol_max_x)

	var diff_x: float = target_x - global_position.x
	if absf(diff_x) > 6.0:
		var dir_x: float = signf(diff_x)
		var desired_vel: float = dir_x * SPEED_PATROL
		_velocity_x = move_toward(_velocity_x, desired_vel, ACCELERATION * delta)
	else:
		_velocity_x = move_toward(_velocity_x, 0.0, FRICTION * delta)

	global_position.x += _velocity_x * delta
	global_position.x = clampf(global_position.x, _patrol_min_x, _patrol_max_x)
	global_position.y = _fixed_y

	# Slight facing tilt toward the ball
	var ball_pos: Vector2 = world.ball_position
	var base_facing: Vector2 = Vector2.DOWN if is_top_touchline else Vector2.UP
	var to_ball_x: float = clampf((ball_pos.x - global_position.x) / 300.0, -0.4, 0.4)
	_facing_direction = (base_facing + Vector2(to_ball_x, 0.0)).normalized()


## Computes the 2nd-to-last defender line for the defending team or the ball X,
## whichever is closest to that defending team's goal line.
func _compute_target_x(world: MatchWorldModel, defending_team: int) -> float:
	var goal_line_x: float = _boundary.get_goal_centre(defending_team).x
	var goal_direction: float = 1.0 if defending_team == 1 else -1.0

	var deepest_score: float = -INF
	var second_deepest_score: float = -INF
	var second_deepest_x: float = goal_line_x

	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		if not world.is_slot_live(i):
			continue
		if world.player_teams[i] != defending_team:
			continue

		var px: float = world.player_positions[i].x
		var score: float = px * goal_direction

		if score > deepest_score:
			second_deepest_score = deepest_score
			if second_deepest_score > -INF:
				second_deepest_x = world.player_positions[i].x
			deepest_score = score
		elif score > second_deepest_score:
			second_deepest_score = score
			second_deepest_x = px

	var ball_x: float = world.ball_position.x
	# If ball is closer to the goal than 2nd defender, track the ball
	if (ball_x - second_deepest_x) * goal_direction > 0.0:
		return ball_x

	return second_deepest_x


## --- Flag Signaling ---------------------------------------------------------

func signal_offside() -> void:
	_flag_state = FlagSignal.RAISED_OFFSIDE
	_flag_timer = 3.5


func signal_throw_in(direction_x: float) -> void:
	_flag_state = FlagSignal.SIGNAL_THROWIN
	_throwin_direction = 1.0 if direction_x >= 0.0 else -1.0
	_flag_timer = 2.5


func signal_corner(_corner_pos: Vector2) -> void:
	_flag_state = FlagSignal.SIGNAL_CORNER
	_flag_timer = 2.5


func signal_goal_kick() -> void:
	_flag_state = FlagSignal.SIGNAL_GOALKICK
	_flag_timer = 2.5


func reset_flag() -> void:
	_flag_state = FlagSignal.IDLE_DOWN
	_flag_timer = 0.0


func _tick_flag_signal(delta: float) -> void:
	if _flag_timer > 0.0:
		_flag_timer -= delta
		if _flag_timer <= 0.0:
			_flag_state = FlagSignal.IDLE_DOWN


## --- Visual Rendering -------------------------------------------------------

func _draw() -> void:
	# 1. Shadow
	var shadow_pos: Vector2 = Vector2(0.0, SHADOW_OFFSET_Y)
	draw_circle(shadow_pos, BODY_RADIUS * 1.0, Color(0.0, 0.0, 0.0, 0.35))

	# 2. Main Body & Uniform
	draw_circle(Vector2.ZERO, BODY_RADIUS, COLOR_JERSEY)

	# 3. Shorts (back side)
	var back_dir: Vector2 = -_facing_direction * (BODY_RADIUS * 0.45)
	draw_circle(back_dir, BODY_RADIUS * 0.55, COLOR_SHORTS)

	# 4. Head / Skin
	var head_pos: Vector2 = _facing_direction * (BODY_RADIUS * 0.25)
	draw_circle(head_pos, BODY_RADIUS * 0.45, COLOR_SKIN)

	# 5. Flag
	_draw_flag()


func _draw_flag() -> void:
	var hand_pos: Vector2 = Vector2.ZERO
	var pole_dir: Vector2 = Vector2.ZERO
	var pole_length: float = 16.0

	var flutter_offset: float = sin(Time.get_ticks_msec() * 0.015) * 1.8

	match _flag_state:
		FlagSignal.IDLE_DOWN:
			# Flag held pointing along the touchline, resting low
			hand_pos = _facing_direction.rotated(PI * 0.5) * (BODY_RADIUS * 0.9)
			pole_dir = Vector2.RIGHT if is_top_touchline else Vector2.LEFT
			pole_length = 12.0

		FlagSignal.RAISED_OFFSIDE:
			# Flag held straight UP vertically
			hand_pos = Vector2(0.0, -BODY_RADIUS * 0.8)
			pole_dir = Vector2.UP
			pole_length = 20.0

		FlagSignal.SIGNAL_THROWIN:
			# Pointed 45 deg in throwin direction
			hand_pos = Vector2(_throwin_direction * BODY_RADIUS * 0.8, -BODY_RADIUS * 0.5)
			pole_dir = Vector2(_throwin_direction, -0.65).normalized()
			pole_length = 17.0

		FlagSignal.SIGNAL_CORNER:
			# Pointed down towards corner
			var corner_dir_x: float = 1.0 if is_top_touchline else -1.0
			hand_pos = Vector2(corner_dir_x * BODY_RADIUS * 0.8, BODY_RADIUS * 0.5)
			pole_dir = Vector2(corner_dir_x, 0.85).normalized()
			pole_length = 16.0

		FlagSignal.SIGNAL_GOALKICK:
			# Pointed horizontally toward penalty box
			var goal_dir_x: float = -1.0 if is_top_touchline else 1.0
			hand_pos = Vector2(goal_dir_x * BODY_RADIUS * 0.8, 0.0)
			pole_dir = Vector2(goal_dir_x, 0.0)
			pole_length = 17.0

	# Draw Pole
	var pole_end: Vector2 = hand_pos + pole_dir * pole_length
	draw_line(hand_pos, pole_end, COLOR_POLE, 2.0)

	# Draw Checkered Quartered Flag Fabric
	var flag_normal: Vector2 = pole_dir.rotated(PI * 0.5)
	if _flag_state == FlagSignal.RAISED_OFFSIDE:
		flag_normal = Vector2.RIGHT

	var flag_w: float = 10.0
	var flag_h: float = 7.0
	var flag_base: Vector2 = pole_end
	var flag_tip: Vector2 = pole_end + flag_normal * (flag_w + flutter_offset)

	# Quartered diamonds / checkers
	var p0: Vector2 = flag_base
	var p1: Vector2 = flag_base - pole_dir * flag_h
	var p2: Vector2 = p1 + flag_normal * (flag_w + flutter_offset)
	var p3: Vector2 = flag_tip

	var mid_p01: Vector2 = (p0 + p1) * 0.5
	var mid_p12: Vector2 = (p1 + p2) * 0.5
	var mid_p23: Vector2 = (p2 + p3) * 0.5
	var mid_p30: Vector2 = (p3 + p0) * 0.5
	var center: Vector2 = (p0 + p2) * 0.5

	# Draw 4 checkered quadrants
	draw_polygon(PackedVector2Array([p0, mid_p30, center, mid_p01]), PackedColorArray([COLOR_FLAG_YELLOW, COLOR_FLAG_YELLOW, COLOR_FLAG_YELLOW, COLOR_FLAG_YELLOW]))
	draw_polygon(PackedVector2Array([mid_p01, center, mid_p12, p1]), PackedColorArray([COLOR_FLAG_RED, COLOR_FLAG_RED, COLOR_FLAG_RED, COLOR_FLAG_RED]))
	draw_polygon(PackedVector2Array([center, mid_p23, p2, mid_p12]), PackedColorArray([COLOR_FLAG_YELLOW, COLOR_FLAG_YELLOW, COLOR_FLAG_YELLOW, COLOR_FLAG_YELLOW]))
	draw_polygon(PackedVector2Array([mid_p30, p3, mid_p23, center]), PackedColorArray([COLOR_FLAG_RED, COLOR_FLAG_RED, COLOR_FLAG_RED, COLOR_FLAG_RED]))
