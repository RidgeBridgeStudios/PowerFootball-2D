##
## FixturesPanel
##
## Every fixture the club has, played and upcoming, across all competitions.
##
## Depends on: CareerPanel, CareerTheme, FixtureData.
##

class_name FixturesPanel
extends CareerPanel


func title() -> String:
	return "Fixtures"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var fixtures: Array[FixtureData] = []
	for comp: CompetitionData in career.competitions:
		for f: FixtureData in comp.fixtures:
			if f.involves(career.user_team_index):
				fixtures.append(f)
	if fixtures.is_empty():
		empty_state(host, "No fixtures scheduled.")
		return

	fixtures.sort_custom(func(a: FixtureData, b: FixtureData) -> bool:
		if a.date == null or b.date == null:
			return false
		return a.date.is_before(b.date)
	)

	var played: int = 0
	var won: int = 0
	var drawn: int = 0
	var lost: int = 0
	for f: FixtureData in fixtures:
		if not f.played:
			continue
		played += 1
		match f.result_char_for(career.user_team_index):
			"W":
				won += 1
			"D":
				drawn += 1
			_:
				lost += 1

	var summary: HBoxContainer = CareerTheme.row(14)
	host.add_child(summary)
	summary.add_child(CareerTheme.secondary("Played %d" % played))
	summary.add_child(CareerTheme.label("W %d" % won, p.result_win))
	summary.add_child(CareerTheme.label("D %d" % drawn, p.result_draw))
	summary.add_child(CareerTheme.label("L %d" % lost, p.result_loss))

	var body: VBoxContainer = CareerTheme.card("All Competitions")
	host.add_child(CareerTheme.card_root(body))

	var header: HBoxContainer = CareerTheme.header_row()
	body.add_child(CareerTheme.data_row_root(header))
	header.add_child(CareerTheme.cell("Date", 116, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Comp", 44, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Round", 110, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("H/A", 34, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Opponent", 168, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Result", 60, p.text_muted, HORIZONTAL_ALIGNMENT_CENTER, p.font_size_small))
	header.add_child(CareerTheme.cell("Att.", 60, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))

	var next_fixture: FixtureData = career.next_user_fixture()
	for i: int in range(fixtures.size()):
		var f: FixtureData = fixtures[i]
		var is_next: bool = f == next_fixture
		var line: HBoxContainer = CareerTheme.data_row(i, is_next)
		var opponent: TeamData = DataLoader.get_team(f.opponent_of(career.user_team_index))
		var tint: Color = p.text_secondary if f.played else p.text_primary

		line.add_child(CareerTheme.cell(
			f.date.to_display() if f.date != null else "", 116, p.text_muted,
			HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
		))
		line.add_child(CareerTheme.cell(f.competition_short(), 44, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
		line.add_child(CareerTheme.cell(f.round_display(), 110, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
		line.add_child(CareerTheme.cell(
			"H" if f.is_home_for(career.user_team_index) else "A", 34, p.text_secondary
		))
		line.add_child(CareerTheme.cell(
			opponent.team_name if opponent != null else "?", 168,
			p.accent if is_next else tint
		))

		if f.played:
			var result: String = f.result_char_for(career.user_team_index)
			line.add_child(CareerTheme.cell(
				"%s %d-%d" % [result, f.goals_for(career.user_team_index), f.goals_against(career.user_team_index)],
				60, CareerTheme.result_color(result), HORIZONTAL_ALIGNMENT_CENTER
			))
			line.add_child(CareerTheme.cell(
				str(f.attendance) if f.attendance > 0 else "—", 60, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT
			))
		else:
			line.add_child(CareerTheme.cell(
				"Next" if is_next else "—", 60,
				p.accent if is_next else p.text_muted, HORIZONTAL_ALIGNMENT_CENTER
			))
			line.add_child(CareerTheme.cell("", 60))
		body.add_child(CareerTheme.data_row_root(line))
