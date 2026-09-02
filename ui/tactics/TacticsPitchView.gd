##
## TacticsPitchView
##
## Interactive 2D tactical pitch view. Renders pitch markings, grass bands, and 11
## interactive player tokens representing the active starting XI in the chosen formation.
##
## Features:
## - Interactive click-to-select and click-to-swap directly on the pitch
## - Clear visual selection ring, hover highlight, and swap target indicators
## - Team colors, jersey number, captain armband badge, and role pill
## - In-match stamina bar underneath player tokens
##
## Depends on: TeamManagementData, FormationRegistry, PlayerData, HeavyPlayerController.
##

class_name TacticsPitchView
extends Control

signal slot_selected(slot: int)
signal slots_swapped(slot_a: int, slot_b: int)

const PITCH_BG: Color = Color(0.11, 0.28, 0.12, 1.0)
const PITCH_STRIPE: Color = Color(0.13, 0.32, 0.14, 1.0)
const PITCH_LINE: Color = Color(1.0, 1.0, 1.0, 0.65)
const PITCH_LINE_FAINT: Color = Color(1.0, 1.0, 1.0, 0.25)
const PIN_RADIUS: float = 14.0
const HIT_RADIUS: float = 24.0

const ROLE_COLORS: Dictionary = {
	"GK": Color(0.18, 0.72, 0.35),
	"CB": Color(0.22, 0.50, 0.85),
	"LB": Color(0.20, 0.60, 0.80),
	"RB": Color(0.20, 0.60, 0.80),
	"DM": Color(0.85, 0.65, 0.15),
	"CDM": Color(0.85, 0.65, 0.15),
	"CM": Color(0.90, 0.70, 0.18),
	"LM": Color(0.80, 0.75, 0.20),
	"RM": Color(0.80, 0.75, 0.20),
	"AM": Color(0.95, 0.45, 0.20),
	"CAM": Color(0.95, 0.45, 0.20),
	"LW": Color(0.90, 0.30, 0.30),
	"RW": Color(0.90, 0.30, 0.30),
	"ST": Color(0.95, 0.22, 0.22),
	"CF": Color(0.95, 0.25, 0.25),
}

var _mgmt: TeamManagementData = null
var _selected_slot: int = -1
var _hovered_slot: int = -1
var _is_in_match: bool = false
## Optional live player nodes array to read active stamina during match pause.
var _live_player_nodes: Array[HeavyPlayerController] = []


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_ALL


func setup(mgmt: TeamManagementData, in_match: bool = false, live_players: Array[HeavyPlayerController] = []) -> void:
	_mgmt = mgmt
	_is_in_match = in_match
	_live_player_nodes = live_players
	_selected_slot = -1
	_hovered_slot = -1
	queue_redraw()


func set_selected_slot(slot: int) -> void:
	_selected_slot = slot
	queue_redraw()


func get_selected_slot() -> int:
	return _selected_slot


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		var clicked_slot: int = _find_slot_at_pos(mouse_event.position)
		if clicked_slot >= 0:
			if _selected_slot == -1:
				_selected_slot = clicked_slot
				slot_selected.emit(_selected_slot)
				queue_redraw()
			elif _selected_slot == clicked_slot:
				_selected_slot = -1
				slot_selected.emit(-1)
				queue_redraw()
			else:
				var prev_slot: int = _selected_slot
				slots_swapped.emit(prev_slot, clicked_slot)
				_selected_slot = clicked_slot
				slot_selected.emit(_selected_slot)
				queue_redraw()
			accept_event()
		else:
			if _selected_slot != -1:
				_selected_slot = -1
				slot_selected.emit(-1)
				queue_redraw()
				accept_event()

	var motion_event := event as InputEventMouse
	if motion_event != null and not (event is InputEventMouseButton):
		var prev_hover: int = _hovered_slot
		_hovered_slot = _find_slot_at_pos(motion_event.position)
		if _hovered_slot != prev_hover:
			mouse_default_cursor_shape = CURSOR_POINTING_HAND if _hovered_slot >= 0 else CURSOR_ARROW
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hovered_slot != -1:
			_hovered_slot = -1
			queue_redraw()


func _find_slot_at_pos(pos: Vector2) -> int:
	if _mgmt == null:
		return -1
	var positions: Array[Vector2] = FormationRegistry.positions_for(_mgmt.formation)
	var r := Rect2(Vector2.ZERO, size)
	var margin := Vector2(28.0, 24.0)
	var usable_size: Vector2 = r.size - margin * 2.0

	for i in range(positions.size()):
		var norm: Vector2 = positions[i]
		var pin_pos: Vector2 = margin + Vector2(norm.x * usable_size.x, norm.y * usable_size.y)
		if pos.distance_squared_to(pin_pos) <= HIT_RADIUS * HIT_RADIUS:
			return i
	return -1


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x < 50.0 or r.size.y < 50.0:
		return

	# Pitch grass and lawn bands
	_draw_pitch_background(r)
	_draw_pitch_lines(r)

	if _mgmt == null or _mgmt.team == null:
		return

	var positions: Array[Vector2] = FormationRegistry.positions_for(_mgmt.formation)
	var margin := Vector2(28.0, 24.0)
	var usable_size: Vector2 = r.size - margin * 2.0

	var team_col: Color = _mgmt.team.team_color
	var sec_col: Color = _mgmt.team.secondary_color
	var gk_col: Color = _mgmt.team.gk_color

	for slot in range(positions.size()):
		var norm: Vector2 = positions[slot]
		var pin_pos: Vector2 = margin + Vector2(norm.x * usable_size.x, norm.y * usable_size.y)

		var p: PlayerData = null
		if slot < _mgmt.lineup.size():
			var sq_idx: int = _mgmt.lineup[slot]
			if sq_idx >= 0 and sq_idx < _mgmt.team.squad.size():
				p = _mgmt.team.squad[sq_idx]

		var slot_role: String = _mgmt.get_slot_role(slot)
		var is_gk: bool = (slot == 0) or (slot_role == "GK")
		var is_cap: bool = (slot == _mgmt.captain_slot) or (p != null and p.is_captain)
		var is_selected: bool = (slot == _selected_slot)
		var is_hovered: bool = (slot == _hovered_slot)

		_draw_player_token(pin_pos, p, slot_role, is_gk, is_cap, is_selected, is_hovered, team_col, sec_col, gk_col)


func _draw_pitch_background(r: Rect2) -> void:
	draw_rect(r, PITCH_BG)
	# Alternating vertical grass stripes
	var stripe_count: int = 10
	var stripe_w: float = r.size.x / float(stripe_count)
	for i in range(stripe_count):
		if i % 2 == 1:
			var stripe_rect := Rect2(Vector2(i * stripe_w, 0.0), Vector2(stripe_w, r.size.y))
			draw_rect(stripe_rect, PITCH_STRIPE)


func _draw_pitch_lines(r: Rect2) -> void:
	# Outer border
	draw_rect(r, PITCH_LINE, false, 2.0)

	# Halfway line
	var mid_x: float = r.size.x * 0.5
	draw_line(Vector2(mid_x, 0.0), Vector2(mid_x, r.size.y), PITCH_LINE, 1.5)

	# Centre circle and spot
	var center := r.size * 0.5
	var circle_radius: float = r.size.y * 0.16
	draw_arc(center, circle_radius, 0.0, TAU, 48, PITCH_LINE, 1.5)
	draw_circle(center, 3.0, PITCH_LINE)

	# Left Penalty Box (Home goal)
	var pen_w: float = r.size.x * 0.16
	var pen_h: float = r.size.y * 0.54
	var pen_y: float = (r.size.y - pen_h) * 0.5
	draw_rect(Rect2(0.0, pen_y, pen_w, pen_h), PITCH_LINE, false, 1.5)

	# Left Goal Box
	var goal_w: float = r.size.x * 0.06
	var goal_h: float = r.size.y * 0.28
	var goal_y: float = (r.size.y - goal_h) * 0.5
	draw_rect(Rect2(0.0, goal_y, goal_w, goal_h), PITCH_LINE, false, 1.2)

	# Left Penalty Spot and Arc
	var pen_spot_left := Vector2(r.size.x * 0.11, r.size.y * 0.5)
	draw_circle(pen_spot_left, 2.5, PITCH_LINE)
	draw_arc(pen_spot_left, circle_radius * 0.75, -PI * 0.35, PI * 0.35, 24, PITCH_LINE, 1.2)

	# Right Penalty Box (Away goal)
	draw_rect(Rect2(r.size.x - pen_w, pen_y, pen_w, pen_h), PITCH_LINE, false, 1.5)

	# Right Goal Box
	draw_rect(Rect2(r.size.x - goal_w, goal_y, goal_w, goal_h), PITCH_LINE, false, 1.2)

	# Right Penalty Spot and Arc
	var pen_spot_right := Vector2(r.size.x * 0.89, r.size.y * 0.5)
	draw_circle(pen_spot_right, 2.5, PITCH_LINE)
	draw_arc(pen_spot_right, circle_radius * 0.75, PI * 0.65, PI * 1.35, 24, PITCH_LINE, 1.2)

	# Corner arcs
	draw_arc(Vector2(0, 0), 12.0, 0.0, PI * 0.5, 12, PITCH_LINE_FAINT, 1.2)
	draw_arc(Vector2(0, r.size.y), 12.0, -PI * 0.5, 0.0, 12, PITCH_LINE_FAINT, 1.2)
	draw_arc(Vector2(r.size.x, 0), 12.0, PI * 0.5, PI, 12, PITCH_LINE_FAINT, 1.2)
	draw_arc(Vector2(r.size.x, r.size.y), 12.0, PI, PI * 1.5, 12, PITCH_LINE_FAINT, 1.2)


func _draw_player_token(
	pos: Vector2, p: PlayerData, role_str: String, is_gk: bool,
	is_cap: bool, is_selected: bool, is_hovered: bool,
	team_col: Color, sec_col: Color, gk_col: Color
) -> void:
	var base_col: Color = gk_col if is_gk else team_col

	# Drop shadow
	draw_circle(pos + Vector2(1.5, 2.5), PIN_RADIUS + 1.0, Color(0.0, 0.0, 0.0, 0.40))

	# Selection pulsing ring
	if is_selected:
		var pulse: float = (sin(Time.get_ticks_msec() * 0.008) + 1.0) * 0.5
		var sel_color := Color(1.0, 0.85, 0.15, 0.85).lerp(Color(0.2, 0.9, 1.0, 0.95), pulse)
		draw_circle(pos, PIN_RADIUS + 5.0 + pulse * 2.0, sel_color, false, 2.5)
		draw_arc(pos, PIN_RADIUS + 2.0, 0.0, TAU, 32, Color.WHITE, 1.5)
	elif is_hovered:
		draw_circle(pos, PIN_RADIUS + 3.0, Color(1.0, 1.0, 1.0, 0.50), false, 2.0)
	elif _selected_slot != -1:
		# Highlight as valid swap target
		draw_circle(pos, PIN_RADIUS + 2.0, Color(0.3, 0.85, 0.4, 0.35), false, 1.5)

	# Captain gold outer rim
	if is_cap:
		draw_circle(pos, PIN_RADIUS + 2.0, Color(1.0, 0.82, 0.12, 1.0), false, 2.0)
	else:
		draw_circle(pos, PIN_RADIUS + 1.0, Color(0.08, 0.08, 0.10, 0.85), false, 1.5)

	# Pin main circle body
	draw_circle(pos, PIN_RADIUS, base_col)

	# Inner secondary color trim ring
	draw_circle(pos, PIN_RADIUS * 0.82, sec_col, false, 1.2)

	# Jersey shirt number
	var number_str: String = str(p.shirt_number) if p != null else "?"
	var lum: float = base_col.r * 0.299 + base_col.g * 0.587 + base_col.b * 0.114
	var text_col: Color = Color.WHITE if lum < 0.60 else Color(0.08, 0.08, 0.10)
	var outline_col: Color = Color(0.05, 0.05, 0.08, 0.95) if lum < 0.60 else Color(1.0, 1.0, 1.0, 0.95)

	var num_size: Vector2 = ThemeDB.fallback_font.get_string_size(number_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
	var num_pos: Vector2 = pos + Vector2(-num_size.x * 0.5, num_size.y * 0.32)

	draw_string_outline(ThemeDB.fallback_font, num_pos, number_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, 2, outline_col)
	draw_string(ThemeDB.fallback_font, num_pos, number_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, text_col)

	# Role pill badge underneath pin
	var role_col: Color = ROLE_COLORS.get(role_str, Color(0.8, 0.7, 0.2))
	var pill_size := Vector2(28.0, 11.0)
	var pill_pos := Vector2(pos.x - pill_size.x * 0.5, pos.y + PIN_RADIUS + 2.0)
	var pill_rect := Rect2(pill_pos, pill_size)

	draw_rect(pill_rect, Color(0.05, 0.05, 0.08, 0.85), true)
	draw_rect(pill_rect, role_col, false, 1.2)

	var role_text_size: Vector2 = ThemeDB.fallback_font.get_string_size(role_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 8)
	var role_text_pos := pill_pos + Vector2((pill_size.x - role_text_size.x) * 0.5, role_text_size.y * 0.9)
	draw_string(ThemeDB.fallback_font, role_text_pos, role_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)

	# Short player name label below role pill
	if p != null:
		var surname: String = _get_surname(p.player_name)
		var name_size: Vector2 = ThemeDB.fallback_font.get_string_size(surname, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
		var name_pos := Vector2(pos.x - name_size.x * 0.5, pill_pos.y + pill_size.y + 10.0)

		# Name background banner for high legibility over turf
		var name_bg := Rect2(name_pos.x - 3.0, name_pos.y - name_size.y + 2.0, name_size.x + 6.0, name_size.y + 2.0)
		draw_rect(name_bg, Color(0.06, 0.08, 0.06, 0.75), true)
		draw_string_outline(ThemeDB.fallback_font, name_pos, surname, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, 2, Color(0.05, 0.05, 0.05, 0.95))
		draw_string(ThemeDB.fallback_font, name_pos, surname, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.95, 0.95, 0.95))

	# Live Stamina Bar (during match pause)
	if _is_in_match and p != null:
		var st_ratio: float = _resolve_live_stamina(p)
		var bar_w: float = 24.0
		var bar_h: float = 3.0
		var bar_pos := Vector2(pos.x - bar_w * 0.5, pos.y - PIN_RADIUS - 6.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.1, 0.1, 0.1, 0.8))
		var st_col := Color(0.2, 0.85, 0.3).lerp(Color(0.9, 0.2, 0.2), 1.0 - st_ratio)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * st_ratio, bar_h)), st_col)

	# Captain golden 'C' badge
	if is_cap:
		var cap_badge_pos := pos + Vector2(PIN_RADIUS * 0.75, -PIN_RADIUS * 0.75)
		draw_circle(cap_badge_pos, 4.2, Color(1.0, 0.82, 0.12, 1.0))
		draw_circle(cap_badge_pos, 4.2, Color(0.1, 0.1, 0.12, 1.0), false, 1.0)
		var c_size: Vector2 = ThemeDB.fallback_font.get_string_size("C", HORIZONTAL_ALIGNMENT_CENTER, -1, 6)
		draw_string(ThemeDB.fallback_font, cap_badge_pos + Vector2(-c_size.x * 0.5, c_size.y * 0.35), "C", HORIZONTAL_ALIGNMENT_CENTER, -1, 6, Color(0.1, 0.1, 0.12))


func _get_surname(full_name: String) -> String:
	var parts: PackedStringArray = full_name.split(" ")
	if parts.size() > 1:
		return parts[parts.size() - 1]
	return full_name


func _resolve_live_stamina(p: PlayerData) -> float:
	for node in _live_player_nodes:
		if is_instance_valid(node) and node.squad_index == p.shirt_number:
			var max_st: float = maxf(node.stamina_max, 1.0)
			return clampf(node.current_stamina / max_st, 0.0, 1.0)
	return 1.0
