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
	var secondary_color: Color = mgmt.team.secondary_color
	var gk_color: Color = mgmt.team.gk_color

	for slot in range(positions.size()):
		var norm: Vector2 = positions[slot]
		var px: Vector2 = Vector2(norm.x * r.size.x, norm.y * r.size.y)

		var p: PlayerData = null
		if slot < mgmt.lineup.size():
			var squad_idx: int = mgmt.lineup[slot]
			if squad_idx >= 0 and squad_idx < mgmt.team.squad.size():
				p = mgmt.team.squad[squad_idx]

		var is_gk: bool = (slot == 0) or (p != null and p.position_role == "GK")
		var is_cap: bool = (p != null and p.is_captain)

		var base_col: Color = gk_color if is_gk else team_color

		# Drop shadow
		draw_circle(px + Vector2(1.0, 1.0), DOT_RADIUS, Color(0.0, 0.0, 0.0, 0.35))

		# Outer border / Captain golden ring
		if is_cap:
			draw_circle(px, DOT_RADIUS + 1.2, Color(1.0, 0.82, 0.10, 1.0))
		else:
			draw_circle(px, DOT_RADIUS + 0.8, Color(0.10, 0.10, 0.12, 0.90))

		# Dot body
		draw_circle(px, DOT_RADIUS, base_col)

		if p == null:
			continue

		var number_text: String = str(p.shirt_number)
		var text_size: Vector2 = ThemeDB.fallback_font.get_string_size(
			number_text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
		var baseline: Vector2 = px + Vector2(-text_size.x * 0.5, text_size.y * 0.35)

		var lum: float = base_col.r * 0.299 + base_col.g * 0.587 + base_col.b * 0.114
		var num_col: Color = Color.WHITE if lum < 0.65 else Color(0.10, 0.10, 0.12, 1.0)
		var out_col: Color = Color(0.08, 0.08, 0.10, 0.95) if lum < 0.65 else Color(1.0, 1.0, 1.0, 0.95)

		draw_string_outline(
			ThemeDB.fallback_font, baseline, number_text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, 2, out_col)
		draw_string(
			ThemeDB.fallback_font, baseline, number_text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, num_col)

		# Captain 'C' badge
		if is_cap:
			var badge_pos: Vector2 = px + Vector2(6.0, -6.0)
			draw_circle(badge_pos, 3.2, Color(1.0, 0.82, 0.10, 1.0))
			draw_circle(badge_pos, 3.2, Color(0.10, 0.10, 0.12, 1.0), false, 0.8)
			var c_size: Vector2 = ThemeDB.fallback_font.get_string_size("C", HORIZONTAL_ALIGNMENT_CENTER, -1, 5)
			draw_string(ThemeDB.fallback_font, badge_pos + Vector2(-c_size.x * 0.5, c_size.y * 0.35), "C", HORIZONTAL_ALIGNMENT_CENTER, -1, 5, Color(0.1, 0.1, 0.12))
