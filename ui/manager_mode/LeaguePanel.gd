##
## LeaguePanel
##
## The full league table plus every other competition's state — cup bracket
## progress and the club's own run in it.
##
## Depends on: CareerPanel, CareerTheme, CompetitionData, LeagueTableRow.
##

class_name LeaguePanel
extends CareerPanel

const TeamProfileViewScript: Resource = preload("res://ui/TeamProfileView.gd")

var _selected_comp_idx: int = 0
var _selected_team_index: int = -1


func title() -> String:
	return "League"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	if career.competitions.is_empty():
		empty_state(host, "No competitions in progress.")
		return

	var tabs: HBoxContainer = CareerTheme.row(4)
	host.add_child(tabs)
	for idx: int in range(career.competitions.size()):
		var c_data: CompetitionData = career.competitions[idx]
		var btn: Button = CareerTheme.button(c_data.competition_name, idx == _selected_comp_idx)
		btn.pressed.connect(func() -> void:
			_selected_comp_idx = idx
			_selected_team_index = -1
			refresh()
		)
		tabs.add_child(btn)

	if _selected_comp_idx >= career.competitions.size():
		_selected_comp_idx = 0

	var comp: CompetitionData = career.competitions[_selected_comp_idx]
	if comp.kind == CompetitionData.Kind.LEAGUE:
		host.add_child(CareerTheme.card_root(_league_table(comp, career, p)))
	else:
		host.add_child(CareerTheme.card_root(_cup_progress(comp, career, p)))


func _league_table(comp: CompetitionData, career: CareerSaveData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card(comp.competition_name)
	var ordered: Array[LeagueTableRow] = comp.sorted_table()

	var header: HBoxContainer = CareerTheme.header_row()
	body.add_child(CareerTheme.data_row_root(header))
	header.add_child(CareerTheme.cell("#", 28, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Club", 168, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	for column: String in ["P", "W", "D", "L"]:
		header.add_child(CareerTheme.cell(column, 28, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("GF", 32, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("GA", 32, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("GD", 36, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("Pts", 34, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("Form", 90, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))

	var is_tier_1: bool = (comp.tier == 1)
	var is_tier_2: bool = (comp.tier == 2)
	var continental_places: int = 4 if is_tier_1 else 0
	var promo_places: int = 2 if is_tier_2 else 0
	var relegation_from: int = 7 if is_tier_1 else 999

	for i: int in range(ordered.size()):
		var r: LeagueTableRow = ordered[i]
		var position: int = i + 1
		var is_user: bool = r.team_index == career.user_team_index
		var line: HBoxContainer = CareerTheme.data_row(i, is_user)

		var position_tint: Color = p.text_muted
		if is_tier_1 and position <= continental_places:
			position_tint = p.positive
		elif is_tier_2 and position <= promo_places:
			position_tint = p.positive
		elif is_tier_1 and position >= relegation_from:
			position_tint = p.danger
		var name_tint: Color = p.accent if is_user else p.text_primary

		line.add_child(CareerTheme.cell(str(position), 28, position_tint))
		var team_btn: Button = CareerTheme.button(r.team_name)
		team_btn.custom_minimum_size = Vector2(168.0, 0.0)
		team_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		team_btn.clip_text = true
		team_btn.add_theme_font_size_override("font_size", p.font_size_body)
		team_btn.add_theme_color_override("font_color", name_tint)
		var flat: StyleBoxFlat = CareerTheme.style_box(Color(0, 0, 0, 0), 0)
		team_btn.add_theme_stylebox_override("normal", flat)
		var t_idx: int = r.team_index
		var host_panel: LeaguePanel = self
		team_btn.pressed.connect(func() -> void:
			if host_panel.get(&"_selected_team_index") == t_idx:
				host_panel.set(&"_selected_team_index", -1)
			else:
				host_panel.set(&"_selected_team_index", t_idx)
			host_panel.refresh()
		)
		line.add_child(team_btn)
		line.add_child(CareerTheme.cell(str(r.played), 28, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(CareerTheme.cell(str(r.won), 28, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(CareerTheme.cell(str(r.drawn), 28, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(CareerTheme.cell(str(r.lost), 28, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(CareerTheme.cell(str(r.goals_for), 32, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(CareerTheme.cell(str(r.goals_against), 32, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
		var gd: int = r.goal_difference()
		line.add_child(CareerTheme.cell(
			"+%d" % gd if gd > 0 else str(gd), 36,
			p.positive if gd > 0 else (p.danger if gd < 0 else p.text_secondary),
			HORIZONTAL_ALIGNMENT_RIGHT
		))
		line.add_child(CareerTheme.cell(str(r.points), 34, name_tint, HORIZONTAL_ALIGNMENT_RIGHT))
		var form_holder := HBoxContainer.new()
		form_holder.custom_minimum_size = Vector2(90.0, 0.0)
		form_holder.add_child(CareerTheme.form_strip(r.form_string(5)))
		line.add_child(form_holder)
		body.add_child(CareerTheme.data_row_root(line))

		if _selected_team_index == r.team_index:
			var inspected_team: TeamData = DataLoader.get_team(r.team_index)
			if inspected_team != null:
				var profile_view: Node = TeamProfileViewScript.new()
				profile_view.call(&"populate_team", inspected_team)
				body.add_child(CareerTheme.spacer(4))
				body.add_child(profile_view as Control)
				body.add_child(CareerTheme.spacer(4))

	body.add_child(CareerTheme.spacer(4))
	var key: HBoxContainer = CareerTheme.row(14)
	if is_tier_1:
		key.add_child(CareerTheme.label("Champions Cup (Top 4)", p.positive, p.font_size_small))
		key.add_child(CareerTheme.label("Relegation (Bottom 2)", p.danger, p.font_size_small))
	elif is_tier_2:
		key.add_child(CareerTheme.label("Promotion (Top 2)", p.positive, p.font_size_small))
	body.add_child(key)
	return body


func _cup_progress(comp: CompetitionData, career: CareerSaveData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card(comp.competition_name)

	if comp.winner_index >= 0:
		var winner: TeamData = DataLoader.get_team(comp.winner_index)
		body.add_child(CareerTheme.label(
			"Winner: %s" % (winner.team_name if winner != null else "?"),
			p.accent, p.font_size_heading
		))
		return body

	if comp.stage == CompetitionData.Stage.GROUP_STAGE and not comp.group_tables.is_empty():
		body.add_child(CareerTheme.label("Group Stage", p.text_primary, p.font_size_heading))
		for g_idx: int in range(comp.group_tables.size()):
			body.add_child(CareerTheme.spacer(4))
			body.add_child(CareerTheme.label("Group %s" % String.chr(65 + g_idx), p.accent))
			var g_header: HBoxContainer = CareerTheme.header_row()
			body.add_child(CareerTheme.data_row_root(g_header))
			g_header.add_child(CareerTheme.cell("#", 28, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
			g_header.add_child(CareerTheme.cell("Club", 168, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
			for col: String in ["P", "W", "D", "L"]:
				g_header.add_child(CareerTheme.cell(col, 28, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
			g_header.add_child(CareerTheme.cell("GF", 32, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
			g_header.add_child(CareerTheme.cell("GA", 32, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
			g_header.add_child(CareerTheme.cell("GD", 36, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
			g_header.add_child(CareerTheme.cell("Pts", 34, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))

			var sorted_rows: Array[LeagueTableRow] = comp.sorted_group_table(g_idx)
			for r_i: int in range(sorted_rows.size()):
				var r: LeagueTableRow = sorted_rows[r_i]
				var pos: int = r_i + 1
				var is_u: bool = r.team_index == career.user_team_index
				var g_line: HBoxContainer = CareerTheme.data_row(r_i, is_u)
				var pos_tint: Color = p.positive if pos <= 2 else p.text_muted
				var name_tint: Color = p.accent if is_u else p.text_primary

				g_line.add_child(CareerTheme.cell(str(pos), 28, pos_tint))
				g_line.add_child(CareerTheme.cell(r.team_name, 168, name_tint))
				g_line.add_child(CareerTheme.cell(str(r.played), 28, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
				g_line.add_child(CareerTheme.cell(str(r.won), 28, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
				g_line.add_child(CareerTheme.cell(str(r.drawn), 28, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
				g_line.add_child(CareerTheme.cell(str(r.lost), 28, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
				g_line.add_child(CareerTheme.cell(str(r.goals_for), 32, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
				g_line.add_child(CareerTheme.cell(str(r.goals_against), 32, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
				var gd: int = r.goal_difference()
				g_line.add_child(CareerTheme.cell(
					"+%d" % gd if gd > 0 else str(gd), 36,
					p.positive if gd > 0 else (p.danger if gd < 0 else p.text_secondary),
					HORIZONTAL_ALIGNMENT_RIGHT
				))
				g_line.add_child(CareerTheme.cell(str(r.points), 34, name_tint, HORIZONTAL_ALIGNMENT_RIGHT))
				body.add_child(CareerTheme.data_row_root(g_line))

		return body

	var still_in: bool = comp.remaining_indices.has(career.user_team_index)
	body.add_child(CareerTheme.label(
		"Round %d · %d clubs remaining" % [comp.current_round, comp.remaining_indices.size()],
		p.text_primary
	))
	body.add_child(CareerTheme.label(
		"You are still in this competition." if still_in else "You have been eliminated.",
		p.positive if still_in else p.danger
	))

	# This round's ties.
	var any: bool = false
	for f: FixtureData in comp.fixtures:
		if f.round_number != comp.current_round:
			continue
		any = true
		var home: TeamData = DataLoader.get_team(f.home_team_index)
		var away: TeamData = DataLoader.get_team(f.away_team_index)
		var involves_user: bool = f.involves(career.user_team_index)
		var line: HBoxContainer = CareerTheme.data_row(0, involves_user)
		line.add_child(CareerTheme.cell(
			home.team_name if home != null else "?", 160,
			p.accent if involves_user else p.text_primary
		))
		line.add_child(CareerTheme.cell(f.score_line(), 50, p.text_primary, HORIZONTAL_ALIGNMENT_CENTER))
		line.add_child(CareerTheme.cell(
			away.team_name if away != null else "?", 160,
			p.accent if involves_user else p.text_primary
		))
		body.add_child(CareerTheme.data_row_root(line))
	if not any:
		body.add_child(CareerTheme.muted("The next round has not been drawn yet."))
	return body
