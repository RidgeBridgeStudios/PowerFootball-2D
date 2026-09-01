##
## FourthOfficialVisual
##
## Technical area match official stationed near the halfway line touchline.
## Steps forward and raises a dual-LED electronic substitution board (Red Out / Green In)
## whenever a substitution is confirmed in the match.
##
## Zero physical collision: purely a visual Node2D agent stationed outside the pitch.
##
## Depends on: DataLoader, PlayerData, PitchBoundary.
## Exposes: bind(boundary), present_substitution(team, out_idx, in_idx), reset()
##

class_name FourthOfficialVisual
extends Node2D

const BODY_RADIUS: float = 6.5
const SHADOW_OFFSET_Y: float = 4.0
const BOARD_HOLD_DURATION: float = 3.6

enum BoardMode { SUB, STOPPAGE }

var _boundary: PitchBoundary = null
var _board_mode: BoardMode = BoardMode.SUB
var _is_presenting_board: bool = false
var _board_timer: float = 0.0
var _out_number: int = 0
var _in_number: int = 0
var _stoppage_minutes: int = 0
var _board_alpha: float = 0.0
var _board_scale: float = 0.8

var _base_position: Vector2 = Vector2.ZERO
var _raised_position: Vector2 = Vector2.ZERO

## Colors
const COLOR_JACKET: Color = Color(0.18, 0.18, 0.22, 1.0)
const COLOR_TROUSERS: Color = Color(0.10, 0.10, 0.12, 1.0)
const COLOR_SKIN: Color = Color(0.92, 0.74, 0.58, 1.0)
const COLOR_BOARD_BG: Color = Color(0.08, 0.08, 0.10, 0.95)
const COLOR_BOARD_BORDER: Color = Color(0.35, 0.35, 0.40, 1.0)
const COLOR_LED_RED: Color = Color(1.0, 0.15, 0.15, 1.0)
const COLOR_LED_GREEN: Color = Color(0.15, 1.0, 0.25, 1.0)
const COLOR_LED_AMBER: Color = Color(1.0, 0.75, 0.10, 1.0)


func _ready() -> void:
	z_index = 3


func bind(boundary: PitchBoundary) -> void:
	_boundary = boundary
	if _boundary != null:
		var rect: Rect2 = _boundary.get_pitch_rect()
		# Technical area on Top touchline near halfway line
		_base_position = Vector2(0.0, rect.position.y - 36.0)
		_raised_position = Vector2(0.0, rect.position.y - 24.0)
		global_position = _base_position
	reset()


func reset() -> void:
	_is_presenting_board = false
	_board_mode = BoardMode.SUB
	_board_timer = 0.0
	_board_alpha = 0.0
	_board_scale = 0.8
	if _base_position != Vector2.ZERO:
		global_position = _base_position
	queue_redraw()


func present_substitution(team: int, out_idx: int, in_idx: int) -> void:
	_board_mode = BoardMode.SUB
	var out_player: PlayerData = DataLoader.get_player(team, out_idx)
	var in_player: PlayerData = DataLoader.get_player(team, in_idx)

	_out_number = out_player.shirt_number if out_player != null else (out_idx + 1)
	_in_number = in_player.shirt_number if in_player != null else (in_idx + 1)

	_is_presenting_board = true
	_board_timer = BOARD_HOLD_DURATION
	_board_alpha = 0.0
	_board_scale = 0.75


func present_stoppage_time(added_minutes: int) -> void:
	_board_mode = BoardMode.STOPPAGE
	_stoppage_minutes = added_minutes
	_is_presenting_board = true
	_board_timer = BOARD_HOLD_DURATION + 0.8
	_board_alpha = 0.0
	_board_scale = 0.75


func _process(delta: float) -> void:
	if not _is_presenting_board:
		return

	_board_timer -= delta
	if _board_timer > BOARD_HOLD_DURATION - 0.3:
		var t_in: float = (BOARD_HOLD_DURATION - _board_timer) / 0.3
		_board_alpha = clampf(t_in, 0.0, 1.0)
		_board_scale = lerpf(0.75, 1.05, t_in)
		global_position = _base_position.lerp(_raised_position, t_in)
	elif _board_timer < 0.4:
		var t_out: float = _board_timer / 0.4
		_board_alpha = clampf(t_out, 0.0, 1.0)
		_board_scale = lerpf(0.85, 1.0, t_out)
		global_position = _raised_position.lerp(_base_position, 1.0 - t_out)
	else:
		_board_alpha = 1.0
		_board_scale = 1.0
		global_position = _raised_position

	if _board_timer <= 0.0:
		reset()

	queue_redraw()


func _draw() -> void:
	# 1. Shadow
	var shadow_pos: Vector2 = Vector2(0.0, SHADOW_OFFSET_Y)
	draw_circle(shadow_pos, BODY_RADIUS * 1.0, Color(0.0, 0.0, 0.0, 0.35))

	# 2. Tracksuit Jacket & Trousers
	draw_circle(Vector2.ZERO, BODY_RADIUS, COLOR_JACKET)
	draw_circle(Vector2(0.0, -BODY_RADIUS * 0.4), BODY_RADIUS * 0.55, COLOR_TROUSERS)

	# 3. Head (facing downward onto pitch)
	draw_circle(Vector2(0.0, BODY_RADIUS * 0.3), BODY_RADIUS * 0.45, COLOR_SKIN)

	# 4. Electronic Board
	if _is_presenting_board and _board_alpha > 0.01:
		if _board_mode == BoardMode.SUB:
			_draw_substitution_board()
		else:
			_draw_stoppage_board()


func _draw_substitution_board() -> void:
	var board_center: Vector2 = Vector2(0.0, -22.0)
	var board_size: Vector2 = Vector2(48.0, 24.0) * _board_scale
	var board_rect := Rect2(board_center - board_size * 0.5, board_size)

	# Board casing & bevel
	var casing_col: Color = COLOR_BOARD_BG
	casing_col.a = _board_alpha
	draw_rect(board_rect, casing_col, true)
	draw_rect(board_rect, Color(COLOR_BOARD_BORDER.r, COLOR_BOARD_BORDER.g, COLOR_BOARD_BORDER.b, _board_alpha), false, 1.5)

	# Arms holding board
	var arm_col: Color = Color(COLOR_SKIN.r, COLOR_SKIN.g, COLOR_SKIN.b, _board_alpha)
	draw_line(Vector2(-BODY_RADIUS * 0.7, 0.0), board_center + Vector2(-board_size.x * 0.35, board_size.y * 0.4), arm_col, 2.0)
	draw_line(Vector2(BODY_RADIUS * 0.7, 0.0), board_center + Vector2(board_size.x * 0.35, board_size.y * 0.4), arm_col, 2.0)

	# LED Digits: Left side = RED OUT, Right side = GREEN IN
	var half_w: float = board_size.x * 0.5
	var left_box := Rect2(board_rect.position + Vector2(2.0, 2.0), Vector2(half_w - 3.0, board_size.y - 4.0))
	var right_box := Rect2(board_rect.position + Vector2(half_w + 1.0, 2.0), Vector2(half_w - 3.0, board_size.y - 4.0))

	# LED inner compartments
	draw_rect(left_box, Color(0.04, 0.02, 0.02, _board_alpha * 0.8), true)
	draw_rect(right_box, Color(0.02, 0.04, 0.02, _board_alpha * 0.8), true)

	var font: Font = ThemeDB.fallback_font
	var font_size: int = int(12.0 * _board_scale)

	# Red Out Numeral
	var out_str: String = str(_out_number)
	var out_size: Vector2 = font.get_string_size(out_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var out_pos: Vector2 = left_box.get_center() + Vector2(-out_size.x * 0.5, out_size.y * 0.35)
	var red_col: Color = Color(COLOR_LED_RED.r, COLOR_LED_RED.g, COLOR_LED_RED.b, _board_alpha)
	draw_string(font, out_pos, out_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, red_col)

	# Green In Numeral
	var in_str: String = str(_in_number)
	var in_size: Vector2 = font.get_string_size(in_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var in_pos: Vector2 = right_box.get_center() + Vector2(-in_size.x * 0.5, in_size.y * 0.35)
	var green_col: Color = Color(COLOR_LED_GREEN.r, COLOR_LED_GREEN.g, COLOR_LED_GREEN.b, _board_alpha)
	draw_string(font, in_pos, in_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, green_col)


func _draw_stoppage_board() -> void:
	var board_center: Vector2 = Vector2(0.0, -22.0)
	var board_size: Vector2 = Vector2(48.0, 24.0) * _board_scale
	var board_rect := Rect2(board_center - board_size * 0.5, board_size)

	# Board casing & bevel
	var casing_col: Color = COLOR_BOARD_BG
	casing_col.a = _board_alpha
	draw_rect(board_rect, casing_col, true)
	draw_rect(board_rect, Color(COLOR_BOARD_BORDER.r, COLOR_BOARD_BORDER.g, COLOR_BOARD_BORDER.b, _board_alpha), false, 1.5)

	# Arms holding board
	var arm_col: Color = Color(COLOR_SKIN.r, COLOR_SKIN.g, COLOR_SKIN.b, _board_alpha)
	draw_line(Vector2(-BODY_RADIUS * 0.7, 0.0), board_center + Vector2(-board_size.x * 0.35, board_size.y * 0.4), arm_col, 2.0)
	draw_line(Vector2(BODY_RADIUS * 0.7, 0.0), board_center + Vector2(board_size.x * 0.35, board_size.y * 0.4), arm_col, 2.0)

	# LED inner box
	var inner_box := Rect2(board_rect.position + Vector2(2.0, 2.0), board_size - Vector2(4.0, 4.0))
	draw_rect(inner_box, Color(0.03, 0.03, 0.02, _board_alpha * 0.85), true)

	var font: Font = ThemeDB.fallback_font
	var font_size: int = int(14.0 * _board_scale)

	# Amber/Orange Stoppage Time Numeral (e.g. "+3")
	var stop_str: String = "+%d" % _stoppage_minutes
	var stop_size: Vector2 = font.get_string_size(stop_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var stop_pos: Vector2 = inner_box.get_center() + Vector2(-stop_size.x * 0.5, stop_size.y * 0.35)
	var amber_col: Color = Color(COLOR_LED_AMBER.r, COLOR_LED_AMBER.g, COLOR_LED_AMBER.b, _board_alpha)
	draw_string(font, stop_pos, stop_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, amber_col)
