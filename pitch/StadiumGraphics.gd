##
## StadiumGraphics
##
## Architectural stadium environment and pitch surroundings for the match engine.
## Renders the complete venue infrastructure surrounding the playing pitch:
##   1. Pitch Apron & Run-off Zone (manicured grass verge, technical tarmac surround,
##      perimeter drainage channel).
##   2. Perimeter LED Advertising Hoardings (dynamic multi-panel electronic boards
##      with scrolling sponsor slogans and glowing LED bevels).
##   3. Team Technical Boxes (official IFAB white dashed boundary boxes on the
##      touchline with team-tinted floor fill and team branding).
##   4. Player Benches / Covered Dugouts (modern aerodynamic curved glass canopies,
##      Recaro-style luxury team bucket seats, seated substitute players in training
##      bibs, and coaching staff with clipboards/medical kits).
##   5. Player Tunnel Entrance (stadium tunnel canopy at halfway line between dugouts).
##   6. Tiered Spectator Grandstands (concrete tier risers, access vomitories, and
##      densely populated crowd rows in team home/away colors).
##   7. Corner Flags (flexible flagpoles with fluttering cloth flags at all four corners).
##   8. Pitch-side Media Photographers (seated photographers on low stools behind goal lines).
##   9. Visible Managers (orchestrates ManagerVisualA and ManagerVisualB in technical boxes).
##
## Purely a visual Node2D presentation layer -- zero physical collision interference.
##
## Depends on: PitchBoundary, TeamData, ManagerData, ManagerVisual.
## Exposes: bind(boundary, team_a_data, team_b_data, manager_a, manager_b),
##          get_technical_box(team), get_dugout_rect(team)
##

class_name StadiumGraphics
extends Node2D

## Node references for the two managers
@onready var manager_visual_a: ManagerVisual = $ManagerVisualA
@onready var manager_visual_b: ManagerVisual = $ManagerVisualB

var _boundary: PitchBoundary = null
var _team_a_data: TeamData = null
var _team_b_data: TeamData = null
var _manager_a_data: ManagerData = null
var _manager_b_data: ManagerData = null

var _pitch_size: Vector2 = Vector2(1600.0, 900.0)
var _half_pitch: Vector2 = Vector2(800.0, 450.0)

## Technical Box Dimensions (Top Touchline, y = -450)
const TECH_BOX_WIDTH: float = 170.0
const TECH_BOX_HEIGHT: float = 42.0
const TECH_BOX_A_X: float = -145.0 ## Center X of Team A box (left of halfway line)
const TECH_BOX_B_X: float = 145.0  ## Center X of Team B box (right of halfway line)
const TECH_BOX_OFFSET_Y: float = -474.0 ## Center Y of technical box

## Dugout Dimensions (Directly behind technical box)
const DUGOUT_WIDTH: float = 170.0
const DUGOUT_HEIGHT: float = 44.0
const DUGOUT_OFFSET_Y: float = -526.0 ## Center Y of dugout

## Colors
const COLOR_APRON_GRASS: Color = Color(0.18, 0.42, 0.16, 1.0)
const COLOR_SURROUND_TARMAC: Color = Color(0.14, 0.15, 0.16, 1.0)
const COLOR_DRAIN_CHANNEL: Color = Color(0.10, 0.10, 0.12, 0.85)
const COLOR_MARKING_WHITE: Color = Color(1.0, 1.0, 1.0, 0.88)
const COLOR_STAND_CONCRETE: Color = Color(0.20, 0.21, 0.24, 1.0)
const COLOR_STAND_STEP: Color = Color(0.15, 0.16, 0.18, 1.0)
const COLOR_VOMITORY_DARK: Color = Color(0.06, 0.06, 0.08, 0.95)
const COLOR_DUGOUT_FLOOR: Color = Color(0.16, 0.17, 0.19, 1.0)
const COLOR_DUGOUT_ROOF: Color = Color(0.40, 0.55, 0.70, 0.35)
const COLOR_DUGOUT_FRAME: Color = Color(0.75, 0.78, 0.82, 0.95)
const COLOR_LED_BORDER: Color = Color(0.25, 0.25, 0.30, 1.0)
const COLOR_LED_BG: Color = Color(0.06, 0.06, 0.08, 0.95)
const COLOR_FLAG_YELLOW: Color = Color(0.98, 0.88, 0.10, 1.0)
const COLOR_FLAG_RED: Color = Color(0.90, 0.15, 0.15, 1.0)

## LED Board cycling texts
const LED_SLOGANS: Array[String] = [
	"POWERFOOTBALL",
	"FAIR PLAY",
	"RESPECT",
	"BEAUTIFUL GAME",
	"PRECISION FOOTBALL"
]

## Persistent cached member RNG for crowd generation
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Pre-computed crowd dots for zero-allocation rendering
var _crowd_positions: PackedVector2Array = PackedVector2Array()
var _crowd_colors: PackedColorArray = PackedColorArray()

## Animation clocks
var _anim_timer: float = 0.0
var _led_scroll_offset: float = 0.0
var _font: Font = null


func _ready() -> void:
	z_index = -8
	_font = ThemeDB.fallback_font
	_ensure_child_nodes()
	_init_crowd_data()
	queue_redraw()


func _ensure_child_nodes() -> void:
	if manager_visual_a == null:
		manager_visual_a = ManagerVisual.new()
		manager_visual_a.name = "ManagerVisualA"
		add_child(manager_visual_a)

	if manager_visual_b == null:
		manager_visual_b = ManagerVisual.new()
		manager_visual_b.name = "ManagerVisualB"
		add_child(manager_visual_b)


func bind(boundary: PitchBoundary, team_a: TeamData, team_b: TeamData, mgr_a: ManagerData, mgr_b: ManagerData) -> void:
	_boundary = boundary
	_team_a_data = team_a
	_team_b_data = team_b
	_manager_a_data = mgr_a
	_manager_b_data = mgr_b

	if _boundary != null:
		_pitch_size = _boundary.pitch_size
		_half_pitch = _pitch_size * 0.5

	_ensure_child_nodes()
	_init_crowd_data()

	var box_a: Rect2 = get_technical_box(0)
	var box_b: Rect2 = get_technical_box(1)
	manager_visual_a.bind(_boundary, 0, _manager_a_data, _team_a_data, box_a)
	manager_visual_b.bind(_boundary, 1, _manager_b_data, _team_b_data, box_b)

	queue_redraw()


func get_technical_box(team: int) -> Rect2:
	var cx: float = TECH_BOX_A_X if team == 0 else TECH_BOX_B_X
	var half_w: float = TECH_BOX_WIDTH * 0.5
	var half_h: float = TECH_BOX_HEIGHT * 0.5
	return Rect2(cx - half_w, TECH_BOX_OFFSET_Y - half_h, TECH_BOX_WIDTH, TECH_BOX_HEIGHT)


func get_dugout_rect(team: int) -> Rect2:
	var cx: float = TECH_BOX_A_X if team == 0 else TECH_BOX_B_X
	var half_w: float = DUGOUT_WIDTH * 0.5
	var half_h: float = DUGOUT_HEIGHT * 0.5
	return Rect2(cx - half_w, DUGOUT_OFFSET_Y - half_h, DUGOUT_WIDTH, DUGOUT_HEIGHT)


func _init_crowd_data() -> void:
	_crowd_positions.clear()
	_crowd_colors.clear()

	var col_a: Color = _team_a_data.team_color if _team_a_data != null else Color(0.25, 0.55, 1.0)
	var col_b: Color = _team_b_data.team_color if _team_b_data != null else Color(1.0, 0.35, 0.25)
	var civilian_colors: Array[Color] = [
		Color(0.85, 0.85, 0.88),
		Color(0.22, 0.25, 0.30),
		Color(0.15, 0.15, 0.18),
		Color(0.72, 0.28, 0.24),
		Color(0.25, 0.48, 0.35),
		Color(0.80, 0.65, 0.20),
	]

	# Deterministic seed for bit-drift zero replay guarantee
	_rng.seed = 20260902

	var y_pos: float = 0.0
	var x_pos: float = 0.0
	var dot_pos: Vector2 = Vector2.ZERO

	# 1. North Stand (Top, behind dugouts: y = -675 to -580)
	for row: int in range(4):
		y_pos = -585.0 - float(row) * 22.0
		for col_idx: int in range(46):
			x_pos = -1050.0 + float(col_idx) * 46.0 + (float(row % 2) * 12.0)
			# Leave walkway gap near halfway line tunnel
			if absf(x_pos) < 36.0:
				continue
			dot_pos = Vector2(x_pos + _rng.randf_range(-3.0, 3.0), y_pos + _rng.randf_range(-2.0, 2.0))
			_crowd_positions.append(dot_pos)
			_crowd_colors.append(_pick_spectator_color(x_pos, col_a, col_b, civilian_colors))

	# 2. South Stand (Bottom: y = 525 to 680)
	for row: int in range(5):
		y_pos = 525.0 + float(row) * 24.0
		for col_idx: int in range(48):
			x_pos = -1080.0 + float(col_idx) * 45.0 + (float(row % 2) * 10.0)
			dot_pos = Vector2(x_pos + _rng.randf_range(-3.0, 3.0), y_pos + _rng.randf_range(-2.0, 2.0))
			_crowd_positions.append(dot_pos)
			_crowd_colors.append(_pick_spectator_color(x_pos, col_a, col_b, civilian_colors))

	# 3. West Stand (Left, behind Team A goal: x = -1150 to -900)
	for col_idx: int in range(4):
		x_pos = -910.0 - float(col_idx) * 32.0
		for row: int in range(24):
			y_pos = -420.0 + float(row) * 36.0
			dot_pos = Vector2(x_pos + _rng.randf_range(-2.0, 2.0), y_pos + _rng.randf_range(-3.0, 3.0))
			_crowd_positions.append(dot_pos)
			_crowd_colors.append(_pick_spectator_color(-800.0, col_a, col_b, civilian_colors))

	# 4. East Stand (Right, behind Team B goal: x = 900 to 1150)
	for col_idx: int in range(4):
		x_pos = 910.0 + float(col_idx) * 32.0
		for row: int in range(24):
			y_pos = -420.0 + float(row) * 36.0
			dot_pos = Vector2(x_pos + _rng.randf_range(-2.0, 2.0), y_pos + _rng.randf_range(-3.0, 3.0))
			_crowd_positions.append(dot_pos)
			_crowd_colors.append(_pick_spectator_color(800.0, col_a, col_b, civilian_colors))


func _pick_spectator_color(x: float, col_a: Color, col_b: Color, civ: Array[Color]) -> Color:
	var roll: float = _rng.randf()
	if x < -50.0:
		# Home dominant side
		if roll < 0.55:
			return col_a
		elif roll < 0.65:
			return col_b
		else:
			return civ[_rng.randi() % civ.size()]
	elif x > 50.0:
		# Away dominant side
		if roll < 0.50:
			return col_b
		elif roll < 0.60:
			return col_a
		else:
			return civ[_rng.randi() % civ.size()]
	else:
		return civ[_rng.randi() % civ.size()]


func _process(delta: float) -> void:
	_anim_timer += delta
	_led_scroll_offset += delta * 35.0
	if _led_scroll_offset > 800.0:
		_led_scroll_offset -= 800.0
	queue_redraw()


func _draw() -> void:
	# 1. Pitch Surround Apron & Run-off Surface
	_draw_pitch_surround()

	# 2. Grandstands & Spectator Terraces
	_draw_grandstands()

	# 3. Perimeter LED Advertising Hoardings
	_draw_perimeter_led_boards()

	# 4. Corner Flags & Pitch-Side Media
	_draw_corner_flags()
	_draw_pitch_side_media()

	# 5. Team Technical Boxes
	_draw_technical_boxes()

	# 6. Player Benches / Dugouts & Tunnel
	_draw_player_benches()
	_draw_tunnel_entrance()


func _draw_pitch_surround() -> void:
	var apron_margin: float = 38.0
	var outer_w: float = _pitch_size.x + apron_margin * 2.0
	var outer_h: float = _pitch_size.y + apron_margin * 2.0
	var apron_rect := Rect2(-outer_w * 0.5, -outer_h * 0.5, outer_w, outer_h)

	# Manicured grass verge surrounding the pitch lines
	draw_rect(apron_rect, COLOR_APRON_GRASS, true)

	# Drainage channel line separating grass verge from outer tarmac
	draw_rect(apron_rect, COLOR_DRAIN_CHANNEL, false, 2.5)

	# Perimeter tarmac / technical apron (behind apron_rect up to the boards)
	var tarmac_rect_top := Rect2(-outer_w * 0.5 - 40.0, -_half_pitch.y - 120.0, outer_w + 80.0, 82.0)
	var tarmac_rect_bot := Rect2(-outer_w * 0.5 - 40.0, _half_pitch.y + apron_margin, outer_w + 80.0, 60.0)
	var tarmac_rect_left := Rect2(-_half_pitch.x - 95.0, -_half_pitch.y - 120.0, 57.0, _pitch_size.y + 240.0)
	var tarmac_rect_right := Rect2(_half_pitch.x + apron_margin, -_half_pitch.y - 120.0, 57.0, _pitch_size.y + 240.0)

	draw_rect(tarmac_rect_top, COLOR_SURROUND_TARMAC, true)
	draw_rect(tarmac_rect_bot, COLOR_SURROUND_TARMAC, true)
	draw_rect(tarmac_rect_left, COLOR_SURROUND_TARMAC, true)
	draw_rect(tarmac_rect_right, COLOR_SURROUND_TARMAC, true)


func _draw_grandstands() -> void:
	# Concrete terraces (North, South, West, East)
	var north_stand := Rect2(-1180.0, -690.0, 2360.0, 130.0)
	var south_stand := Rect2(-1180.0, 510.0, 2360.0, 180.0)
	var west_stand := Rect2(-1180.0, -560.0, 305.0, 1070.0)
	var east_stand := Rect2(875.0, -560.0, 305.0, 1070.0)

	draw_rect(north_stand, COLOR_STAND_CONCRETE, true)
	draw_rect(south_stand, COLOR_STAND_CONCRETE, true)
	draw_rect(west_stand, COLOR_STAND_CONCRETE, true)
	draw_rect(east_stand, COLOR_STAND_CONCRETE, true)

	# Tier step lines
	for i: int in range(5):
		var y_n: float = -670.0 + float(i) * 24.0
		draw_line(Vector2(-1180.0, y_n), Vector2(1180.0, y_n), COLOR_STAND_STEP, 1.5)

		var y_s: float = 525.0 + float(i) * 32.0
		draw_line(Vector2(-1180.0, y_s), Vector2(1180.0, y_s), COLOR_STAND_STEP, 1.5)

	for i: int in range(6):
		var x_w: float = -1160.0 + float(i) * 45.0
		draw_line(Vector2(x_w, -560.0), Vector2(x_w, 510.0), COLOR_STAND_STEP, 1.5)

		var x_e: float = 895.0 + float(i) * 45.0
		draw_line(Vector2(x_e, -560.0), Vector2(x_e, 510.0), COLOR_STAND_STEP, 1.5)

	# Stadium vomitory / tunnel openings in stands
	draw_rect(Rect2(-600.0, -685.0, 48.0, 40.0), COLOR_VOMITORY_DARK, true)
	draw_rect(Rect2(552.0, -685.0, 48.0, 40.0), COLOR_VOMITORY_DARK, true)
	draw_rect(Rect2(-600.0, 630.0, 48.0, 45.0), COLOR_VOMITORY_DARK, true)
	draw_rect(Rect2(552.0, 630.0, 48.0, 45.0), COLOR_VOMITORY_DARK, true)

	# Render cached spectator crowd dots
	for i: int in range(_crowd_positions.size()):
		var pos: Vector2 = _crowd_positions[i]
		var col: Color = _crowd_colors[i]
		draw_circle(pos, 3.8, col)
		draw_circle(pos - Vector2(0.0, 1.0), 2.2, col.lightened(0.2))


func _draw_perimeter_led_boards() -> void:
	var board_height: float = 14.0
	var pulse: float = 0.5 + 0.5 * sin(_anim_timer * 3.0)

	# 1. Top Touchline Boards (Left & Right of technical areas)
	var top_left_board := Rect2(-840.0, -498.0, 595.0, board_height)
	var top_right_board := Rect2(245.0, -498.0, 595.0, board_height)
	_draw_led_strip(top_left_board, pulse, 0)
	_draw_led_strip(top_right_board, pulse, 1)

	# Backboard behind dugouts
	var dugout_backboard_a := Rect2(-240.0, -554.0, 190.0, 8.0)
	var dugout_backboard_b := Rect2(50.0, -554.0, 190.0, 8.0)
	_draw_led_strip(dugout_backboard_a, pulse * 0.7, 2)
	_draw_led_strip(dugout_backboard_b, pulse * 0.7, 3)

	# 2. Bottom Touchline Boards (Continuous)
	var bot_board := Rect2(-840.0, 484.0, 1680.0, board_height)
	_draw_led_strip(bot_board, pulse, 4)

	# 3. End Line Boards (Behind Goal Nets)
	var end_left_board := Rect2(-854.0, -484.0, board_height, 968.0)
	var end_right_board := Rect2(840.0, -484.0, board_height, 968.0)
	_draw_vertical_led_strip(end_left_board, pulse)
	_draw_vertical_led_strip(end_right_board, pulse)


func _draw_led_strip(rect: Rect2, pulse: float, seed_offset: int) -> void:
	# Outer casing
	draw_rect(rect, COLOR_LED_BG, true)
	draw_rect(rect, COLOR_LED_BORDER, false, 1.5)

	# Subtle electronic LED grid styling
	var inner := Rect2(rect.position + Vector2(2.0, 2.0), rect.size - Vector2(4.0, 4.0))
	var led_color: Color = Color(0.15, 0.45, 0.85, 0.75 + pulse * 0.2)
	draw_rect(inner, Color(0.04, 0.06, 0.10, 0.95), true)

	if _font != null:
		var slogan: String = LED_SLOGANS[seed_offset % LED_SLOGANS.size()]
		var font_size: int = 9
		var str_size: Vector2 = _font.get_string_size(slogan, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

		# Repeating sponsor text along the strip
		var span: float = str_size.x + 40.0
		var count: int = int(ceil(inner.size.x / span)) + 1
		for i: int in range(count):
			var x_offset: float = inner.position.x + float(i) * span - fmod(_led_scroll_offset, span)
			if x_offset + str_size.x > inner.position.x and x_offset < inner.end.x:
				var text_pos := Vector2(x_offset, inner.position.y + inner.size.y * 0.75)
				draw_string(_font, text_pos, slogan, HORIZONTAL_ALIGNMENT_LEFT, int(inner.end.x - x_offset), font_size, led_color)


func _draw_vertical_led_strip(rect: Rect2, pulse: float) -> void:
	draw_rect(rect, COLOR_LED_BG, true)
	draw_rect(rect, COLOR_LED_BORDER, false, 1.5)
	var led_accent := Color(0.18, 0.65, 0.35, 0.65 + pulse * 0.25)
	var inner := Rect2(rect.position + Vector2(2.0, 2.0), rect.size - Vector2(4.0, 4.0))
	draw_rect(inner, led_accent, true)


func _draw_corner_flags() -> void:
	var corners: Array[Vector2] = [
		Vector2(-_half_pitch.x, -_half_pitch.y),
		Vector2(_half_pitch.x, -_half_pitch.y),
		Vector2(-_half_pitch.x, _half_pitch.y),
		Vector2(_half_pitch.x, _half_pitch.y)
	]

	var wave: float = sin(_anim_timer * 4.5) * 2.2
	for i: int in range(corners.size()):
		var c_pos: Vector2 = corners[i]
		# Pole base spring
		draw_circle(c_pos, 2.8, Color(0.12, 0.12, 0.15, 0.9))

		# Pole
		var pole_tip: Vector2 = c_pos + Vector2(0.0, -14.0)
		draw_line(c_pos, pole_tip, Color(0.95, 0.95, 0.95, 0.95), 1.6)

		# Waving flag cloth (triangular pennant pointing toward pitch center)
		var sign_x: float = 1.0 if c_pos.x < 0.0 else -1.0
		var flag_tip: Vector2 = pole_tip + Vector2(sign_x * (9.0 + wave), 3.0)
		var flag_bot: Vector2 = pole_tip + Vector2(0.0, 7.0)
		var flag_poly := PackedVector2Array([pole_tip, flag_tip, flag_bot])
		var flag_col: Color = COLOR_FLAG_YELLOW if (i % 2 == 0) else COLOR_FLAG_RED
		draw_colored_polygon(flag_poly, flag_col)


func _draw_pitch_side_media() -> void:
	# Photographers stationed behind goal lines
	var photo_y_spots: Array[float] = [-220.0, -120.0, 120.0, 220.0]

	for y_offset: float in photo_y_spots:
		# Left side photographers (behind Left Goal)
		var p_pos_left := Vector2(-838.0, y_offset)
		_draw_photographer(p_pos_left, Vector2(1.0, 0.0))

		# Right side photographers (behind Right Goal)
		var p_pos_right := Vector2(838.0, y_offset)
		_draw_photographer(p_pos_right, Vector2(-1.0, 0.0))


func _draw_photographer(pos: Vector2, aim_dir: Vector2) -> void:
	# Stool & Shadow
	draw_circle(pos + Vector2(0.0, 3.0), 4.5, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(pos, 4.0, Color(0.15, 0.15, 0.18, 1.0))

	# Media High-Vis Bib (Neon green/orange)
	draw_circle(pos, 3.5, Color(0.20, 0.88, 0.35, 1.0))

	# Head
	draw_circle(pos - aim_dir * 1.5, 2.2, Color(0.85, 0.68, 0.52, 1.0))

	# Telephoto Camera Rig on Monopod
	var cam_pos: Vector2 = pos + aim_dir * 6.5
	draw_line(pos, cam_pos, Color(0.10, 0.10, 0.12, 1.0), 2.2)
	draw_rect(Rect2(cam_pos - Vector2(1.8, 1.8), Vector2(3.6, 3.6)), Color(0.08, 0.08, 0.10, 1.0), true)
	draw_line(cam_pos, cam_pos + aim_dir * 5.0, Color(0.25, 0.25, 0.28, 1.0), 3.0)


func _draw_technical_boxes() -> void:
	var box_a: Rect2 = get_technical_box(0)
	var box_b: Rect2 = get_technical_box(1)

	_draw_single_technical_box(box_a, _team_a_data, "HOME")
	_draw_single_technical_box(box_b, _team_b_data, "AWAY")


func _draw_single_technical_box(box: Rect2, t_data: TeamData, label_text: String) -> void:
	# 1. Subtle team-tinted floor fill
	var team_col: Color = t_data.team_color if t_data != null else Color(0.25, 0.55, 1.0)
	var fill_col: Color = Color(team_col.r, team_col.g, team_col.b, 0.14)
	draw_rect(box, fill_col, true)

	# 2. Diagonal tactical grid texture
	var step: float = 14.0
	var x_cursor: float = box.position.x
	while x_cursor < box.end.x + box.size.y:
		var start_pt := Vector2(x_cursor, box.position.y)
		var end_pt := Vector2(x_cursor - box.size.y * 0.8, box.end.y)
		if start_pt.x > box.end.x:
			start_pt.y += (start_pt.x - box.end.x)
			start_pt.x = box.end.x
		if end_pt.x < box.position.x:
			end_pt.y -= (box.position.x - end_pt.x)
			end_pt.x = box.position.x
		draw_line(start_pt, end_pt, Color(1.0, 1.0, 1.0, 0.08), 1.0)
		x_cursor += step

	# 3. IFAB Regulatory Dashed Boundary Lines
	_draw_dashed_rect(box, COLOR_MARKING_WHITE, 1.8, 6.0, 4.0)

	# 4. Box Label / Team Name on Floor
	if _font != null:
		var display_name: String = t_data.team_name if t_data != null and not t_data.team_name.is_empty() else label_text
		var font_size: int = 8
		var str_size: Vector2 = _font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos: Vector2 = Vector2(box.get_center().x - str_size.x * 0.5, box.position.y + 12.0)
		draw_string(_font, text_pos, display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1.0, 1.0, 1.0, 0.45))


func _draw_dashed_rect(rect: Rect2, color: Color, width: float, dash_len: float, gap_len: float) -> void:
	# Top line
	_draw_dashed_line(rect.position, Vector2(rect.end.x, rect.position.y), color, width, dash_len, gap_len)
	# Bottom line (along touchline apron)
	_draw_dashed_line(Vector2(rect.position.x, rect.end.y), rect.end, color, width, dash_len, gap_len)
	# Left line
	_draw_dashed_line(rect.position, Vector2(rect.position.x, rect.end.y), color, width, dash_len, gap_len)
	# Right line
	_draw_dashed_line(Vector2(rect.end.x, rect.position.y), rect.end, color, width, dash_len, gap_len)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var dir: Vector2 = (to - from).normalized()
	var total_len: float = from.distance_to(to)
	var cursor: float = 0.0

	while cursor < total_len:
		var seg_len: float = minf(dash, total_len - cursor)
		var seg_start: Vector2 = from + dir * cursor
		var seg_end: Vector2 = seg_start + dir * seg_len
		draw_line(seg_start, seg_end, color, width)
		cursor += dash + gap


func _draw_player_benches() -> void:
	var dugout_a: Rect2 = get_dugout_rect(0)
	var dugout_b: Rect2 = get_dugout_rect(1)

	_draw_single_dugout(dugout_a, _team_a_data, true)
	_draw_single_dugout(dugout_b, _team_b_data, false)


func _draw_single_dugout(rect: Rect2, t_data: TeamData, is_home: bool) -> void:
	var team_col: Color = t_data.team_color if t_data != null else Color(0.25, 0.55, 1.0)
	var sec_col: Color = t_data.secondary_color if t_data != null else Color(1.0, 1.0, 1.0)

	# 1. Raised Concrete & Rubber Platform
	draw_rect(rect.grow(1.5), Color(0.08, 0.08, 0.10, 0.95), true)
	draw_rect(rect, COLOR_DUGOUT_FLOOR, true)
	# Yellow/white platform safety edge
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, Color(0.95, 0.85, 0.15, 0.85), 1.5)

	# 2. Luxury Recaro-Style Bucket Seats (7 seats along the bench)
	var seat_count: int = 7
	var seat_w: float = 16.0
	var seat_h: float = 18.0
	var seat_spacing: float = rect.size.x / float(seat_count)
	var seat_y: float = rect.position.y + 12.0

	for s: int in range(seat_count):
		var seat_x: float = rect.position.x + float(s) * seat_spacing + (seat_spacing - seat_w) * 0.5
		var seat_rect := Rect2(seat_x, seat_y, seat_w, seat_h)

		# Seat base cushion & headrest
		draw_rect(seat_rect, team_col.darkened(0.25), true)
		draw_rect(seat_rect, team_col.lightened(0.15), false, 1.0)
		var headrest_rect := Rect2(seat_x + 3.0, seat_y + 1.0, seat_w - 6.0, 5.0)
		draw_rect(headrest_rect, team_col, true)

		# Seated Personnel on bench:
		# Seats 1..5: Substitute players wearing bibs
		# Seats 0, 6: Coaching staff / physio
		var person_center := Vector2(seat_x + seat_w * 0.5, seat_y + seat_h * 0.55)
		if s == 0 or s == 6:
			# Staff member in dark tracksuit
			draw_circle(person_center, 4.5, Color(0.12, 0.14, 0.18, 1.0))
			draw_circle(person_center - Vector2(0.0, 2.0), 3.0, Color(0.85, 0.68, 0.55, 1.0)) # Head
			# Clipboard / medical kit
			draw_rect(Rect2(person_center + Vector2(2.5, 0.0), Vector2(3.5, 3.0)), Color(0.92, 0.92, 0.95, 1.0), true)
		else:
			# Substitute player in training bib (secondary color or vibrant bib)
			var bib_col: Color = sec_col if sec_col.a > 0.1 else Color(1.0, 0.85, 0.15)
			draw_circle(person_center, 4.8, bib_col)
			draw_circle(person_center, 3.2, team_col)
			draw_circle(person_center - Vector2(0.0, 2.2), 3.0, Color(0.88, 0.72, 0.58, 1.0)) # Head

	# 3. Aerodynamic Curved Glass Canopy & Steel Frame
	# Translucent polycarbonate canopy
	draw_rect(rect, COLOR_DUGOUT_ROOF, true)

	# Steel arched structural stanchions
	for stanchion_idx: int in range(4):
		var stan_x: float = rect.position.x + float(stanchion_idx) * (rect.size.x / 3.0)
		draw_line(Vector2(stan_x, rect.position.y), Vector2(stan_x, rect.end.y), COLOR_DUGOUT_FRAME, 1.6)

	# Curved glass roof edge highlight
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(1.0, 1.0, 1.0, 0.85), 2.0)
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, Color(0.8, 0.85, 0.95, 0.65), 1.2)
	draw_line(rect.position, Vector2(rect.position.x, rect.end.y), COLOR_DUGOUT_FRAME, 1.6)
	draw_line(Vector2(rect.end.x, rect.position.y), rect.end, COLOR_DUGOUT_FRAME, 1.6)

	# Glass reflection diagonal highlight
	draw_line(
		rect.position + Vector2(10.0, 2.0),
		rect.position + Vector2(45.0, rect.size.y - 2.0),
		Color(1.0, 1.0, 1.0, 0.35),
		2.5
	)

	# Dugout Fascia Badge / Nameplate
	var fascia_rect := Rect2(rect.position + Vector2(rect.size.x * 0.25, -5.0), Vector2(rect.size.x * 0.5, 7.0))
	draw_rect(fascia_rect, team_col, true)
	draw_rect(fascia_rect, Color(1.0, 1.0, 1.0, 0.8), false, 1.0)
	if _font != null:
		var dugout_title: String = t_data.team_name if t_data != null and not t_data.team_name.is_empty() else ("HOME" if is_home else "AWAY")
		var font_size: int = 7
		var title_size: Vector2 = _font.get_string_size(dugout_title, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var title_pos := Vector2(fascia_rect.get_center().x - title_size.x * 0.5, fascia_rect.position.y + 5.5)
		draw_string(_font, title_pos, dugout_title, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)


func _draw_tunnel_entrance() -> void:
	# Central Player Tunnel between the two dugouts at x = [-38, 38]
	var tunnel_rect := Rect2(-38.0, -554.0, 76.0, 48.0)

	# Tunnel depth shadow (interior darkness)
	draw_rect(tunnel_rect, Color(0.04, 0.04, 0.06, 0.98), true)

	# Arched tunnel canopy / accordion tunnel extension
	for ring: int in range(4):
		var y_ring: float = tunnel_rect.position.y + float(ring) * 11.0
		var arch_col: Color = Color(0.85, 0.88, 0.92, 0.90) if (ring % 2 == 0) else Color(0.20, 0.22, 0.26, 0.90)
		draw_line(Vector2(tunnel_rect.position.x, y_ring), Vector2(tunnel_rect.end.x, y_ring), arch_col, 2.0)

	# Tunnel safety handrails
	draw_line(tunnel_rect.position, Vector2(tunnel_rect.position.x, tunnel_rect.end.y), Color(0.9, 0.85, 0.15, 0.9), 1.8)
	draw_line(Vector2(tunnel_rect.end.x, tunnel_rect.position.y), tunnel_rect.end, Color(0.9, 0.85, 0.15, 0.9), 1.8)

	# Red carpet / rubber tunnel walkway
	var walkway_rect := Rect2(-22.0, tunnel_rect.position.y, 44.0, tunnel_rect.size.y + 12.0)
	draw_rect(walkway_rect, Color(0.65, 0.12, 0.16, 0.80), true)
