##
## OverviewPanel
##
## The Manager Mode home screen — the state the manager returns to. Mirrors
## FM's overview: next fixture, recent results, form, league snapshot, squad
## morale, injuries, board confidence, and the media ticker.
##
## Every widget reads live career state; nothing is cached between builds.
##
## Depends on: CareerPanel, CareerTheme, CareerSaveData, WorldEventLog.
##

class_name OverviewPanel
extends CareerPanel


func title() -> String:
	return "Overview"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var team: TeamData = club(career)
	if team == null:
		empty_state(host, "No club loaded.")
		return

	var top: HBoxContainer = CareerTheme.row(10)
	host.add_child(top)
	top.add_child(CareerTheme.card_root(_next_fixture_card(career, team)))
	top.add_child(CareerTheme.card_root(_form_card(career, p)))

	var mid: HBoxContainer = CareerTheme.row(10)
	host.add_child(mid)
	mid.add_child(CareerTheme.card_root(_league_card(career, p)))
	mid.add_child(CareerTheme.card_root(_squad_health_card(career, team, p)))

	host.add_child(CareerTheme.card_root(_media_card(career, p)))
	host.add_child(CareerTheme.card_root(_history_card(team, p)))


func _next_fixture_card(career: CareerSaveData, team: TeamData) -> VBoxContainer:
	var p: CareerThemePalette = CareerTheme.palette()
	var body: VBoxContainer = CareerTheme.card("Next Fixture")
	var fixture: FixtureData = career.next_user_fixture()
	if fixture == null:
		body.add_child(CareerTheme.muted("No fixtures remaining this season."))
		return body

	var opponent: TeamData = DataLoader.get_team(fixture.opponent_of(career.user_team_index))
	var is_home: bool = fixture.is_home_for(career.user_team_index)
	var home_club: Variant = team if is_home else opponent
	var away_club: Variant = opponent if is_home else team
	var fix_hdr: HBoxContainer = CareerTheme.row(8)
	body.add_child(fix_hdr)
	fix_hdr.add_child(CareerTheme.team_link(home_club, 0, p.text_primary))
	fix_hdr.add_child(CareerTheme.label("vs", p.text_muted))
	fix_hdr.add_child(CareerTheme.team_link(away_club, 0, p.text_primary))

	body.add_child(CareerTheme.secondary("%s · %s · %s" % [
		fixture.competition_name(), fixture.round_display(),
		"Home" if is_home else "Away"
	]))

	var days: int = career.days_until_next_fixture()
	var when: String = "Today" if days <= 0 else ("Tomorrow" if days == 1 else "%s (%d days)" % [
		fixture.date.to_display() if fixture.date != null else "", days
	])
	body.add_child(CareerTheme.label(when, p.accent if days <= 1 else p.text_secondary))

	if opponent != null:
		var league: CompetitionData = career.league_competition()
		var opp_row: LeagueTableRow = league.row_for(fixture.opponent_of(career.user_team_index)) if league != null else null
		var opp_mgr: ManagerData = ManagerLoader.get_or_assign_manager(opponent.team_name)
		body.add_child(CareerTheme.divider())
		body.add_child(CareerTheme.muted("Opposition"))
		var analyst: float = 0.5
		for s: StaffData in club(career).staff:
			if s.role.to_lower().contains("analyst"):
				analyst = maxf(analyst, s.tactical_knowledge)
		var dossier: Dictionary = ScoutingNetwork.opposition_report(
			opponent, opp_mgr, opp_row, analyst
		)
		if opp_mgr != null:
			var mgr_line: HBoxContainer = CareerTheme.row(6)
			mgr_line.add_child(CareerTheme.secondary("Manager:"))
			mgr_line.add_child(CareerTheme.staff_link(opp_mgr))
			body.add_child(mgr_line)
		body.add_child(CareerTheme.secondary("Shape: %s" % String(dossier.get("formation", "?"))))
		body.add_child(CareerTheme.paragraph(String(dossier.get("style", ""))))
		var keys: Array = dossier.get("key_players", [])
		if not keys.is_empty():
			var danger_line: HBoxContainer = CareerTheme.row(6)
			danger_line.add_child(CareerTheme.muted("Danger:"))
			for k_name: Variant in keys:
				danger_line.add_child(CareerTheme.player_link(str(k_name)))
			body.add_child(danger_line)
	return body


func _form_card(career: CareerSaveData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Recent Results")
	var recent: Array[FixtureData] = career.recent_user_results(10)
	if recent.is_empty():
		body.add_child(CareerTheme.muted("No matches played yet."))
		return body

	# Last five as a form strip, newest last.
	var form: String = ""
	var start: int = maxi(recent.size() - 5, 0)
	for i: int in range(start, recent.size()):
		form += recent[i].result_char_for(career.user_team_index)
	body.add_child(CareerTheme.form_strip(form))
	body.add_child(CareerTheme.spacer(4))

	# Newest first in the list beneath.
	for i: int in range(recent.size() - 1, maxi(recent.size() - 6, -1), -1):
		var f: FixtureData = recent[i]
		var opponent: TeamData = DataLoader.get_team(f.opponent_of(career.user_team_index))
		var result: String = f.result_char_for(career.user_team_index)
		var line: HBoxContainer = CareerTheme.data_row(recent.size() - 1 - i)
		line.add_child(CareerTheme.cell(result, 18, CareerTheme.result_color(result)))
		var opp_box := HBoxContainer.new()
		opp_box.custom_minimum_size = Vector2(150.0, 0.0)
		opp_box.add_child(CareerTheme.cell("v" if f.is_home_for(career.user_team_index) else "@", 16, p.text_muted))
		opp_box.add_child(CareerTheme.team_link(opponent if opponent != null else "?", 130))
		line.add_child(opp_box)
		line.add_child(CareerTheme.cell(
			"%d-%d" % [f.goals_for(career.user_team_index), f.goals_against(career.user_team_index)],
			46, p.text_primary, HORIZONTAL_ALIGNMENT_RIGHT
		))
		line.add_child(CareerTheme.cell(f.competition_short(), 40, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT))
		body.add_child(CareerTheme.data_row_root(line))
	return body


func _league_card(career: CareerSaveData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("League Position")
	var league: CompetitionData = career.league_competition()
	if league == null:
		body.add_child(CareerTheme.muted("No league in progress."))
		return body

	var ordered: Array[LeagueTableRow] = league.sorted_table()
	var position: int = league.position_of(career.user_team_index)
	body.add_child(CareerTheme.label(
		"%s of %d" % [_ordinal(position), ordered.size()], p.accent, p.font_size_title
	))
	if career.board != null:
		var target: int = career.board.target_position(ordered.size())
		var meeting: bool = position <= target
		body.add_child(CareerTheme.label(
			"Board expect: %s (%s)" % [career.board.expectation_label(), _ordinal(target)],
			p.positive if meeting else p.warning
		))
	body.add_child(CareerTheme.divider())

	# A window around the user's row, which is what actually matters.
	var first: int = clampi(position - 3, 1, maxi(ordered.size() - 4, 1))
	var last: int = mini(first + 4, ordered.size())
	for i: int in range(first - 1, last):
		var r: LeagueTableRow = ordered[i]
		var is_user: bool = r.team_index == career.user_team_index
		var line: HBoxContainer = CareerTheme.data_row(i, is_user)
		var tint: Color = p.accent if is_user else p.text_primary
		line.add_child(CareerTheme.cell(str(i + 1), 24, tint))
		line.add_child(CareerTheme.team_link(r.team_index, 140, tint))
		line.add_child(CareerTheme.cell(str(r.played), 26, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(CareerTheme.cell(_signed(r.goal_difference()), 34, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(CareerTheme.cell(str(r.points), 30, tint, HORIZONTAL_ALIGNMENT_RIGHT))
		body.add_child(CareerTheme.data_row_root(line))
	return body


func _squad_health_card(career: CareerSaveData, team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Squad")
	var morale: float = career.squad_morale(team)
	var morale_row: HBoxContainer = CareerTheme.row()
	morale_row.add_child(CareerTheme.cell("Team morale", 110, p.text_secondary))
	morale_row.add_child(CareerTheme.bar(morale, 110))
	morale_row.add_child(CareerTheme.label(
		MoraleEngine.morale_label(morale), MoraleEngine.morale_color(morale)
	))
	body.add_child(morale_row)

	if career.board != null:
		var conf_row: HBoxContainer = CareerTheme.row()
		conf_row.add_child(CareerTheme.cell("Board confidence", 110, p.text_secondary))
		conf_row.add_child(CareerTheme.bar(career.board.confidence, 110))
		conf_row.add_child(CareerTheme.label(
			career.board.confidence_label(), CareerTheme.tint_for_rating(career.board.confidence)
		))
		body.add_child(conf_row)

	body.add_child(CareerTheme.divider())

	# Unavailable players — the thing a manager actually checks first.
	var unavailable_players: Array[Array] = []
	var unhappy_players: Array[Array] = []
	for squad_index: int in range(team.squad.size()):
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if state == null:
			continue
		var data: PlayerData = team.squad[squad_index]
		if not state.is_available():
			unavailable_players.append([data, state.availability_label()])
		elif data.morale < 0.35:
			unhappy_players.append([data, MoraleEngine.morale_label(data.morale)])

	body.add_child(CareerTheme.muted("Unavailable (%d)" % unavailable_players.size()))
	if unavailable_players.is_empty():
		body.add_child(CareerTheme.secondary("Full squad available."))
	else:
		for item: Array in unavailable_players:
			var pl_data: PlayerData = item[0] as PlayerData
			var status_str: String = String(item[1])
			var row_box: HBoxContainer = CareerTheme.row(4)
			row_box.add_child(CareerTheme.player_link(pl_data, 0, p.danger))
			row_box.add_child(CareerTheme.label("— " + status_str, p.danger, p.font_size_small))
			body.add_child(row_box)

	if not unhappy_players.is_empty():
		body.add_child(CareerTheme.muted("Unhappy (%d)" % unhappy_players.size()))
		for item2: Array in unhappy_players:
			var pl_data2: PlayerData = item2[0] as PlayerData
			var status_str2: String = String(item2[1])
			var row_box2: HBoxContainer = CareerTheme.row(4)
			row_box2.add_child(CareerTheme.player_link(pl_data2, 0, p.warning))
			row_box2.add_child(CareerTheme.label("— " + status_str2, p.warning, p.font_size_small))
			body.add_child(row_box2)
	return body


func _media_card(career: CareerSaveData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Media & Club News")
	var events: Array[WorldEvent] = WorldEventLog.recent(8)
	if events.is_empty():
		body.add_child(CareerTheme.muted("Nothing has happened yet."))
		return body
	for i: int in range(events.size()):
		var e: WorldEvent = events[i]
		var line: HBoxContainer = CareerTheme.data_row(i)
		var tint: Color = p.text_secondary
		if e.sentiment > 0.2:
			tint = p.positive
		elif e.sentiment < -0.2:
			tint = p.danger
		line.add_child(CareerTheme.cell(
			e.date.to_display() if e.date != null else "", 110, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
		))
		line.add_child(CareerTheme.cell(e.category_name(), 96, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
		var text: Label = CareerTheme.label(e.narrative_context, tint, p.font_size_small)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		line.add_child(text)
		body.add_child(CareerTheme.data_row_root(line))
	return body


func _signed(v: int) -> String:
	return "+%d" % v if v > 0 else str(v)


func _ordinal(n: int) -> String:
	var suffix: String = "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
			_:
				suffix = "th"
	return "%d%s" % [n, suffix]


func _history_card(team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Club Overview & History")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 140.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.scroll_following = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.fit_content = true
	label.add_theme_font_size_override("normal_font_size", p.font_size_body)
	label.add_theme_color_override("default_color", p.text_secondary)

	if team.wikipedia_extract.strip_edges().is_empty():
		label.text = "[color=#888888][i]No historical extract available for this club.[/i][/color]"
	else:
		label.text = team.wikipedia_extract

	scroll.add_child(label)
	body.add_child(scroll)
	return body


## Standalone helper if an inspector or test drives OverviewPanel directly.
const TeamProfileViewScript: Resource = preload("res://ui/TeamProfileView.gd")
var _profile_view: Node = null

var history_label: RichTextLabel:
	get:
		return (_profile_view.get(&"history_label") as RichTextLabel) if _profile_view != null else null

func populate_team(team: TeamData) -> void:
	if _profile_view == null:
		_profile_view = TeamProfileViewScript.new()
	_profile_view.call(&"populate_team", team)
