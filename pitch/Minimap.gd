##
## Minimap
##
## Small always-on-screen overview of the pitch: a bordered box in the top
## right corner showing every player as a team-coloured dot with their shirt
## number drawn inside it. Lives on the Control child of a CanvasLayer so it
## stays fixed on screen regardless of camera position or shake.
##
## Positions come straight from each HeavyPlayerController's global_position
## (world space, pitch centred on the origin — see PitchMarkings), rescaled
## into this control's local rect. Redrawn every frame since 22 players is
## cheap to iterate and there is no cheaper "did anything move" check worth
## doing.
##
## Depends on: HeavyPlayerController, PlayerData (via player_data meta),
##             PitchBoundary (for pitch_size), MatchOfficialCrew.
## Exposes: bind(players, boundary, officials)
##

class_name Minimap
extends Control

const DOT_RADIUS: float = 8.0
const NUMBER_FONT_SIZE: int = 8
const BG_COLOR: Color = Color(0.04, 0.04, 0.04, 0.6)
const BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.7)
const BORDER_WIDTH: float = 2.0
const NUMBER_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

## Colour per team. Index 0 = TEAM_A, index 1 = TEAM_B — matches FacingArrow.
const TEAM_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0, 1.0),
	Color(1.0, 0.35, 0.25, 1.0),
]

## Referee colors on minimap
const COLOR_REF_DOT: Color = Color(0.88, 0.98, 0.15, 1.0)
const COLOR_LINESMAN_DOT: Color = Color(1.0, 0.75, 0.10, 0.9)
const COLOR_FOURTH_DOT: Color = Color(0.65, 0.65, 0.75, 0.9)

var _players: Node2D = null
var _pitch_size: Vector2 = Vector2(1600.0, 900.0)
var _officials: MatchOfficialCrew = null


## Called once by PitchScene after players and officials are spawned. boundary and officials
## may be null (falls back to the default pitch size) if a caller ever binds early.
func bind(players: Node2D, boundary: PitchBoundary, officials: MatchOfficialCrew = null) -> void:
	_players = players
	_officials = officials
	if boundary != null:
		_pitch_size = boundary.pitch_size


func _process(_delta: float) -> void:
	if _players != null or _officials != null:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BG_COLOR, true)
	draw_rect(rect, BORDER_COLOR, false, BORDER_WIDTH)

	if _officials != null and is_instance_valid(_officials):
		_draw_officials()

	if _players == null:
		return

	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player == null or not is_instance_valid(player):
			continue
		_draw_player_dot(player)


func _draw_officials() -> void:
	var center_ref: CenterRefereeVisual = _officials.get_center_ref()
	if center_ref != null and is_instance_valid(center_ref):
		var ref_pos: Vector2 = _world_to_map(center_ref.global_position)
		draw_circle(ref_pos, 5.5, Color(0.08, 0.08, 0.10, 0.95))
		draw_circle(ref_pos, 4.0, COLOR_REF_DOT)
		var font: Font = ThemeDB.fallback_font
		draw_string(font, ref_pos + Vector2(-2.5, 3.0), "R", HORIZONTAL_ALIGNMENT_CENTER, -1, 7, Color(0.1, 0.1, 0.1))

	var linesmen: Array[AssistantRefereeVisual] = _officials.get_linesmen()
	for linesman: AssistantRefereeVisual in linesmen:
		if linesman != null and is_instance_valid(linesman):
			var lm_pos: Vector2 = _world_to_map(linesman.global_position)
			draw_rect(Rect2(lm_pos - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), COLOR_LINESMAN_DOT, true)

	var fourth: FourthOfficialVisual = _officials.get_fourth_official()
	if fourth != null and is_instance_valid(fourth):
		var fourth_pos: Vector2 = _world_to_map(fourth.global_position)
		draw_circle(fourth_pos, 3.5, COLOR_FOURTH_DOT)


func _draw_player_dot(player: HeavyPlayerController) -> void:
	var dot_pos: Vector2 = _world_to_map(player.global_position)
	var team_idx: int = clampi(player.team, 0, TEAM_COLORS.size() - 1)
	draw_circle(dot_pos, DOT_RADIUS, TEAM_COLORS[team_idx])

	var data: PlayerData = player.get_meta(&"player_data", null) as PlayerData
	if data == null:
		return

	var number_text: String = str(data.shirt_number)
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(
		number_text, HORIZONTAL_ALIGNMENT_CENTER, -1, NUMBER_FONT_SIZE)
	var baseline: Vector2 = dot_pos + Vector2(-text_size.x * 0.5, text_size.y * 0.35)
	draw_string(
		font, baseline, number_text, HORIZONTAL_ALIGNMENT_CENTER, -1,
		NUMBER_FONT_SIZE, NUMBER_COLOR)


## Pitch is centred on the world origin, so shift by half the pitch size
## before normalising into this control's local rect. Clamped in case a
## player is mid-tackle out near (or past) the touchline.
func _world_to_map(world_pos: Vector2) -> Vector2:
	var half: Vector2 = _pitch_size * 0.5
	var normalized: Vector2 = (world_pos + half) / _pitch_size
	normalized.x = clampf(normalized.x, 0.0, 1.0)
	normalized.y = clampf(normalized.y, 0.0, 1.0)
	return normalized * size

