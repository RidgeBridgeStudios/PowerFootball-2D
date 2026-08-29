##
## FormationDiagram
##
## Draws a miniature top-down pitch and overlays coloured dots at the 11
## formation positions from FormationRegistry. Dots are labelled with the
## player's shirt number. Shared between PreGameScreen and PauseMenu.
##
## Depends on: FormationRegistry, TeamManagementData, PlayerData.
## Exposes: nothing — callers set_meta(&"positions", ...) and set_meta(&"mgmt", ...)
##          then call queue_redraw().
##

class_name FormationDiagram
extends Control

const PITCH_COLOR: Color = Color(0.22, 0.50, 0.22, 1.0)
const LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
const DOT_RADIUS: float = 8.0
const FONT_SIZE: int = 10


func _draw() -> void:
	var positions: Array = get_meta(&"positions", [])
	var mgmt: TeamManagementData = get_meta(&"mgmt", null)
	if positions.is_empty() or mgmt == null:
		return

	var r := Rect2(Vector2.ZERO, size)

	draw_rect(r, PITCH_COLOR)
	draw_line(Vector2(r.size.x * 0.5, 0.0), Vector2(r.size.x * 0.5, r.size.y), LINE_COLOR, 1.0)
	draw_arc(r.size * 0.5, r.size.y * 0.15, 0.0, TAU, 32, LINE_COLOR, 1.0)

	var team_color: Color = mgmt.team.team_color
	for slot in range(positions.size()):
		var norm: Vector2 = positions[slot]
		var px: Vector2 = Vector2(norm.x * r.size.x, norm.y * r.size.y)

		draw_circle(px, DOT_RADIUS, team_color)
		draw_arc(px, DOT_RADIUS, 0.0, TAU, 16, Color.WHITE, 1.0)

		if slot >= mgmt.lineup.size():
			continue
		var squad_idx: int = mgmt.lineup[slot]
		if squad_idx < 0 or squad_idx >= mgmt.team.squad.size():
			continue
		var p: PlayerData = mgmt.team.squad[squad_idx]
		draw_string(
			ThemeDB.fallback_font,
			px - Vector2(5.0, -4.0),
			str(p.shirt_number),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, FONT_SIZE, Color.WHITE
		)
