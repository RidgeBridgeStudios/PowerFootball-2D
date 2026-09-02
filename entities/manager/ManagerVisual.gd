##
## ManagerVisual
##
## Visible match manager stationed inside the touchline technical box.
## Represented by an authentic top-down "suit and tie on a dot" token:
## tailored dark jacket, notch lapels, crisp collared dress shirt, and a
## sharp necktie with knot, blade, pointed tip, and metallic tie bar.
##
## Kinematically patrols the technical box, tracks pitch action, and exhibits
## dynamic emotional reactions (goal celebrations, concession despair,
## tactical instruction pointing, and referee/fourth official appeals).
##
## Zero physical collision: purely a visual Node2D presentation agent.
## Choke point: reads ball position via MatchWorldModel.
##
## Depends on: GameEvents, MatchWorldModel, PitchBoundary, ManagerData, TeamData.
## Exposes: bind(boundary, team, manager_data, team_data, box_rect),
##          get_current_state(), get_manager_data()
##

class_name ManagerVisual
extends Node2D

enum State {
	PACING,               ## Tracking play along the touchline within technical box
	OBSERVING,            ## Standing stationary at technical line watching play
	TACTICAL_INSTRUCTION, ## Pointing and shouting tactical adjustments to team
	CELEBRATING,          ## Jubilant celebration after team scores a goal
	DISMAY,               ## Hands on head in dismay after conceding a goal
	APPEALING             ## Arms spread wide appealing foul or card to 4th official
}

const BODY_RADIUS: float = 7.5
const SHADOW_OFFSET_Y: float = 4.5
const SPEED_PACING: float = 55.0
const ACCELERATION: float = 180.0
const CELEBRATION_DURATION: float = 4.2
const DISMAY_DURATION: float = 3.6
const TACTICAL_DURATION: float = 3.2
const APPEAL_DURATION: float = 2.8

## Base Colors
const COLOR_SHIRT: Color = Color(0.96, 0.96, 0.98, 1.0)
const COLOR_SKIN: Color = Color(0.92, 0.74, 0.58, 1.0)
const COLOR_TIE_CLIP: Color = Color(0.88, 0.88, 0.92, 1.0)
const COLOR_HAIR_GREY: Color = Color(0.68, 0.68, 0.72, 1.0)
const COLOR_HAIR_DARK: Color = Color(0.18, 0.15, 0.14, 1.0)

var _boundary: PitchBoundary = null
var _team: int = -1
var _manager_data: ManagerData = null
var _team_data: TeamData = null
var _box_rect: Rect2 = Rect2()

var _state: State = State.PACING
var _state_timer: float = 0.0
var _signals_connected: bool = false

var _suit_color: Color = Color(0.12, 0.13, 0.16, 1.0)
var _lapel_color: Color = Color(0.18, 0.19, 0.23, 1.0)
var _tie_color: Color = Color(0.82, 0.15, 0.18, 1.0)
var _hair_color: Color = COLOR_HAIR_DARK

var _facing_direction: Vector2 = Vector2(0.0, 1.0)
var _target_pos: Vector2 = Vector2.ZERO
var _current_velocity: float = 0.0
var _hop_offset_y: float = 0.0
var _gesture_phase: float = 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 2
	_connect_signals()


func bind(boundary: PitchBoundary, team: int, data: ManagerData, team_data: TeamData, box: Rect2) -> void:
	_boundary = boundary
	_team = team
	_manager_data = data
	_team_data = team_data
	_box_rect = box

	_apply_visual_styling()

	# Start near center-front of the technical box
	var start_x: float = _box_rect.get_center().x
	var start_y: float = _box_rect.end.y - 10.0
	global_position = Vector2(start_x, start_y)
	_target_pos = global_position
	_facing_direction = Vector2(0.0, 1.0)

	_connect_signals()
	queue_redraw()


func _apply_visual_styling() -> void:
	# Tailored suit variations based on team or manager characteristics
	if _team == 0:
		_suit_color = Color(0.11, 0.12, 0.15, 1.0) # Deep charcoal / midnight
		_lapel_color = Color(0.17, 0.18, 0.22, 1.0)
	else:
		_suit_color = Color(0.13, 0.14, 0.18, 1.0) # Slate navy
		_lapel_color = Color(0.19, 0.20, 0.25, 1.0)

	# Distinctive necktie color (use team secondary/primary accent or classic crimson)
	if _team_data != null and _team_data.secondary_color.a > 0.1:
		_tie_color = _team_data.secondary_color
		# Ensure tie has contrast against white shirt
		if _tie_color.get_luminance() > 0.75:
			_tie_color = _team_data.team_color
	else:
		_tie_color = Color(0.85, 0.16, 0.20, 1.0) # Classic silk red tie

	# Hair styling: seasoned managers have silver/grey hair, younger have dark/brown
	if _manager_data != null and _manager_data.experience > 55:
		_hair_color = COLOR_HAIR_GREY
	else:
		_hair_color = COLOR_HAIR_DARK


func _connect_signals() -> void:
	if _signals_connected:
		return
	_signals_connected = true

	if not GameEvents.goal_scored.is_connected(_on_goal_scored):
		GameEvents.goal_scored.connect(_on_goal_scored)
	if not GameEvents.manager_formation_changed.is_connected(_on_manager_formation_changed):
		GameEvents.manager_formation_changed.connect(_on_manager_formation_changed)
	if not GameEvents.emergency_tactics_triggered.is_connected(_on_emergency_tactics_triggered):
		GameEvents.emergency_tactics_triggered.connect(_on_emergency_tactics_triggered)
	if not GameEvents.referee_awarded_foul.is_connected(_on_referee_awarded_foul):
		GameEvents.referee_awarded_foul.connect(_on_referee_awarded_foul)
	if not GameEvents.yellow_card_shown.is_connected(_on_yellow_card_shown):
		GameEvents.yellow_card_shown.connect(_on_yellow_card_shown)
	if not GameEvents.red_card_shown.is_connected(_on_red_card_shown):
		GameEvents.red_card_shown.connect(_on_red_card_shown)


func _on_goal_scored(scoring_team: int) -> void:
	if scoring_team == _team:
		_set_state(State.CELEBRATING, CELEBRATION_DURATION)
	else:
		_set_state(State.DISMAY, DISMAY_DURATION)


func _on_manager_formation_changed(team: int, _formation: String) -> void:
	if team == _team:
		_set_state(State.TACTICAL_INSTRUCTION, TACTICAL_DURATION)


func _on_emergency_tactics_triggered(team: int) -> void:
	if team == _team:
		_set_state(State.TACTICAL_INSTRUCTION, TACTICAL_DURATION + 0.8)


func _on_referee_awarded_foul(awarded_to_team: int, _pos: Vector2) -> void:
	if awarded_to_team != _team and awarded_to_team != -1:
		_set_state(State.APPEALING, APPEAL_DURATION)


func _on_yellow_card_shown(_player: HeavyPlayerController, carded_team: int) -> void:
	if carded_team == _team:
		_set_state(State.APPEALING, APPEAL_DURATION + 0.4)


func _on_red_card_shown(_player: HeavyPlayerController, carded_team: int) -> void:
	if carded_team == _team:
		_set_state(State.APPEALING, APPEAL_DURATION + 1.2)


func _set_state(new_state: State, duration: float) -> void:
	_state = new_state
	_state_timer = duration
	_gesture_phase = 0.0


func _process(delta: float) -> void:
	_update_timers(delta)
	_update_kinematics(delta)
	queue_redraw()


func _update_timers(delta: float) -> void:
	_gesture_phase += delta * 6.0

	if _state_timer > 0.0:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_state = State.PACING

	if _state == State.CELEBRATING:
		# Energetic celebratory hop
		_hop_offset_y = -absf(sin(_gesture_phase * 2.0)) * 5.0
	else:
		_hop_offset_y = 0.0


func _update_kinematics(delta: float) -> void:
	if _box_rect.size == Vector2.ZERO:
		return

	var min_x: float = _box_rect.position.x + 14.0
	var max_x: float = _box_rect.end.x - 14.0
	var touchline_y: float = _box_rect.end.y - 8.0
	var benchline_y: float = _box_rect.position.y + 10.0

	match _state:
		State.PACING:
			# Track ball's X position smoothly, staying within technical box boundaries
			var ball_pos: Vector2 = MatchWorldModel.ball_position
			var desired_x: float = clampf(ball_pos.x, min_x, max_x)
			_target_pos = Vector2(desired_x, touchline_y)

			# Face towards the pitch / ball
			var to_ball: Vector2 = (ball_pos - global_position).normalized()
			if to_ball.y < 0.2:
				to_ball.y = 0.5
			_facing_direction = to_ball.normalized()

		State.OBSERVING:
			# Stand stationary near the technical box line
			_target_pos = Vector2(global_position.x, touchline_y)
			_facing_direction = Vector2(0.0, 1.0)

		State.TACTICAL_INSTRUCTION:
			# Step right up to the front touchline edge
			_target_pos = Vector2(clampf(global_position.x, min_x, max_x), _box_rect.end.y - 4.0)
			_facing_direction = Vector2(0.0, 1.0)

		State.CELEBRATING:
			# Run forward toward pitch edge with fist pumps
			_target_pos = Vector2(global_position.x, _box_rect.end.y - 4.0)
			_facing_direction = Vector2(0.0, 1.0)

		State.DISMAY:
			# Step back towards the bench with head down
			_target_pos = Vector2(global_position.x, benchline_y)
			_facing_direction = Vector2(0.0, -1.0)

		State.APPEALING:
			# Turn toward fourth official (center halfway line at x=0)
			var to_fourth: Vector2 = Vector2(-signf(global_position.x), 0.3).normalized()
			_facing_direction = to_fourth

	# Kinematic position lerp
	var diff_x: float = _target_pos.x - global_position.x
	if absf(diff_x) > 2.0:
		var move_speed: float = SPEED_PACING
		if _manager_data != null and _manager_data.has_trait(1): # HotHead paces faster
			move_speed *= 1.35
		var target_vel: float = signf(diff_x) * move_speed
		_current_velocity = move_toward(_current_velocity, target_vel, ACCELERATION * delta)
	else:
		_current_velocity = move_toward(_current_velocity, 0.0, ACCELERATION * 1.5 * delta)

	global_position.x += _current_velocity * delta
	global_position.y = move_toward(global_position.y, _target_pos.y, SPEED_PACING * 0.8 * delta)


func _draw() -> void:
	var root_pos: Vector2 = Vector2(0.0, _hop_offset_y)

	# 1. Ground Drop Shadow
	var shadow_pos: Vector2 = Vector2(0.0, SHADOW_OFFSET_Y)
	draw_circle(shadow_pos, BODY_RADIUS * 1.05, Color(0.0, 0.0, 0.0, 0.38))

	# 2. Tailored Suit Jacket (body circle token)
	draw_circle(root_pos, BODY_RADIUS, _suit_color)

	# 3. Suit Back & Shoulder Contour
	var back_offset: Vector2 = root_pos - _facing_direction * (BODY_RADIUS * 0.35)
	draw_circle(back_offset, BODY_RADIUS * 0.55, _suit_color.darkened(0.18))

	# 4. White Dress Shirt V-Opening
	var perp: Vector2 = Vector2(-_facing_direction.y, _facing_direction.x)
	var chest_center: Vector2 = root_pos + _facing_direction * (BODY_RADIUS * 0.08)
	var v_top_left: Vector2 = chest_center - _facing_direction * (BODY_RADIUS * 0.42) - perp * (BODY_RADIUS * 0.36)
	var v_top_right: Vector2 = chest_center - _facing_direction * (BODY_RADIUS * 0.42) + perp * (BODY_RADIUS * 0.36)
	var v_bottom: Vector2 = chest_center + _facing_direction * (BODY_RADIUS * 0.44)
	var shirt_poly := PackedVector2Array([v_top_left, v_top_right, v_bottom])
	draw_colored_polygon(shirt_poly, COLOR_SHIRT)

	# 5. Suit Lapels (Notch lapels on either side of the shirt opening)
	var lapel_l_out: Vector2 = v_top_left - perp * (BODY_RADIUS * 0.22) + _facing_direction * (BODY_RADIUS * 0.16)
	var lapel_l_notch: Vector2 = v_top_left - perp * (BODY_RADIUS * 0.10) + _facing_direction * (BODY_RADIUS * 0.38)
	var lapel_left_poly := PackedVector2Array([v_top_left, lapel_l_out, lapel_l_notch, v_bottom])
	draw_colored_polygon(lapel_left_poly, _lapel_color)

	var lapel_r_out: Vector2 = v_top_right + perp * (BODY_RADIUS * 0.22) + _facing_direction * (BODY_RADIUS * 0.16)
	var lapel_r_notch: Vector2 = v_top_right + perp * (BODY_RADIUS * 0.10) + _facing_direction * (BODY_RADIUS * 0.38)
	var lapel_right_poly := PackedVector2Array([v_top_right, lapel_r_out, lapel_r_notch, v_bottom])
	draw_colored_polygon(lapel_right_poly, _lapel_color)

	# 6. Distinctive Necktie Graphic
	# Tie knot at the collar
	var knot_top: Vector2 = chest_center - _facing_direction * (BODY_RADIUS * 0.38)
	var knot_tl: Vector2 = knot_top - perp * 1.5
	var knot_tr: Vector2 = knot_top + perp * 1.5
	var knot_bl: Vector2 = knot_top + _facing_direction * 2.2 - perp * 1.0
	var knot_br: Vector2 = knot_top + _facing_direction * 2.2 + perp * 1.0
	var knot_poly := PackedVector2Array([knot_tl, knot_tr, knot_br, knot_bl])
	draw_colored_polygon(knot_poly, _tie_color.darkened(0.12))

	# Tie blade flowing down the center
	var tie_start: Vector2 = knot_top + _facing_direction * 2.0
	var blade_bl: Vector2 = tie_start + _facing_direction * 3.6 - perp * 1.3
	var blade_br: Vector2 = tie_start + _facing_direction * 3.6 + perp * 1.3
	var tie_tip: Vector2 = tie_start + _facing_direction * 5.0
	var blade_poly := PackedVector2Array([knot_bl, knot_br, blade_br, tie_tip, blade_bl])
	draw_colored_polygon(blade_poly, _tie_color)

	# Shiny Metallic Tie Bar / Clip
	var clip_pos: Vector2 = tie_start + _facing_direction * 2.0
	draw_line(clip_pos - perp * 1.5, clip_pos + perp * 0.4, COLOR_TIE_CLIP, 1.0)

	# Collar edges
	draw_line(v_top_left, knot_top, COLOR_SHIRT, 1.2)
	draw_line(v_top_right, knot_top, COLOR_SHIRT, 1.2)

	# 7. Head & Groomed Hair
	var head_pos: Vector2 = root_pos - _facing_direction * (BODY_RADIUS * 0.22)
	draw_circle(head_pos, BODY_RADIUS * 0.42, COLOR_SKIN)
	var hair_offset: Vector2 = head_pos - _facing_direction * (BODY_RADIUS * 0.14)
	draw_circle(hair_offset, BODY_RADIUS * 0.38, _hair_color)

	# 8. Dynamic Action Arms & Gestures
	_draw_action_arms(root_pos, perp)


func _draw_action_arms(root_pos: Vector2, perp: Vector2) -> void:
	match _state:
		State.TACTICAL_INSTRUCTION:
			# Extended arm pointing directly towards pitch
			var arm_start: Vector2 = root_pos + perp * (BODY_RADIUS * 0.7)
			var arm_end: Vector2 = arm_start + _facing_direction * (BODY_RADIUS + 8.0)
			draw_line(arm_start, arm_end, _suit_color, 2.4)
			draw_circle(arm_end, 2.0, COLOR_SKIN)
			# Pointing finger
			draw_line(arm_end, arm_end + _facing_direction * 3.0, COLOR_SKIN, 1.2)

		State.CELEBRATING:
			# Both arms raised high in victory celebration with clenched fists
			var wave: float = sin(_gesture_phase * 2.5) * 2.0
			var c_left_shoulder: Vector2 = root_pos - perp * (BODY_RADIUS * 0.7)
			var c_left_fist: Vector2 = c_left_shoulder + _facing_direction * (BODY_RADIUS + 7.0 + wave) - perp * 4.0
			draw_line(c_left_shoulder, c_left_fist, _suit_color, 2.4)
			draw_circle(c_left_fist, 2.2, COLOR_SKIN)

			var c_right_shoulder: Vector2 = root_pos + perp * (BODY_RADIUS * 0.7)
			var c_right_fist: Vector2 = c_right_shoulder + _facing_direction * (BODY_RADIUS + 7.0 - wave) + perp * 4.0
			draw_line(c_right_shoulder, c_right_fist, _suit_color, 2.4)
			draw_circle(c_right_fist, 2.2, COLOR_SKIN)

		State.DISMAY:
			# Hands brought to head
			var d_left_hand: Vector2 = root_pos - perp * (BODY_RADIUS * 0.45) - _facing_direction * (BODY_RADIUS * 0.2)
			var d_right_hand: Vector2 = root_pos + perp * (BODY_RADIUS * 0.45) - _facing_direction * (BODY_RADIUS * 0.2)
			draw_circle(d_left_hand, 2.2, COLOR_SKIN)
			draw_circle(d_right_hand, 2.2, COLOR_SKIN)

		State.APPEALING:
			# Arms outspread towards 4th official in protest
			var a_left_shoulder: Vector2 = root_pos - perp * (BODY_RADIUS * 0.6)
			var a_left_palm: Vector2 = a_left_shoulder + _facing_direction * (BODY_RADIUS + 5.0) - perp * 6.0
			draw_line(a_left_shoulder, a_left_palm, _suit_color, 2.2)
			draw_circle(a_left_palm, 2.0, COLOR_SKIN)

			var a_right_shoulder: Vector2 = root_pos + perp * (BODY_RADIUS * 0.6)
			var a_right_palm: Vector2 = a_right_shoulder + _facing_direction * (BODY_RADIUS + 5.0) + perp * 6.0
			draw_line(a_right_shoulder, a_right_palm, _suit_color, 2.2)
			draw_circle(a_right_palm, 2.0, COLOR_SKIN)

		_:
			# Pacing / Observing: hands at sides or tucked in pockets
			var p_left_hand: Vector2 = root_pos - perp * (BODY_RADIUS * 0.85) + _facing_direction * (BODY_RADIUS * 0.2)
			var p_right_hand: Vector2 = root_pos + perp * (BODY_RADIUS * 0.85) + _facing_direction * (BODY_RADIUS * 0.2)
			draw_circle(p_left_hand, 1.8, _suit_color.darkened(0.2))
			draw_circle(p_right_hand, 1.8, _suit_color.darkened(0.2))


func get_current_state() -> State:
	return _state


func get_manager_data() -> ManagerData:
	return _manager_data
