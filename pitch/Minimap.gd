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
##             PitchBoundary (for pitch_size).
## Exposes: bind(players, boundary)
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

var _players: Node2D = null
var _pitch_size: Vector2 = Vector2(1600.0, 900.0)


## Called once by PitchScene after players are spawned. boundary may be null
## (falls back to the default pitch size) if a caller ever binds early.
func bind(players: Node2D, boundary: PitchBoundary) -> void:
	_players = players
	if boundary != null:
		_pitch_size = boundary.pitch_size


func _process(_delta: float) -> void:
	if _players != null:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BG_COLOR, true)
	draw_rect(rect, BORDER_COLOR, false, BORDER_WIDTH)

	if _players == null:
		return

	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player == null or not is_instance_valid(player):
			continue
		_draw_player_dot(player)


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
