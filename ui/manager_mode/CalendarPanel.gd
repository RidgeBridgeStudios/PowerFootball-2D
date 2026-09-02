##
## CalendarPanel
##
## A month view of the career calendar: matches, training sessions, transfer
## window state and season phase, so the manager can see what is coming rather
## than only what is next.
##
## Depends on: CareerPanel, CareerTheme, CareerDate, TrainingSchedule.
##

class_name CalendarPanel
extends CareerPanel

## Months offset from today the user is currently viewing.
var _month_offset: int = 0


func title() -> String:
	return "Calendar"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var anchor: CareerDate = _viewed_month(career)

	var toolbar: HBoxContainer = CareerTheme.row()
	host.add_child(toolbar)
	var previous: Button = CareerTheme.button("< Previous")
	previous.pressed.connect(func() -> void:
		_month_offset -= 1
		refresh()
	)
	toolbar.add_child(previous)
	toolbar.add_child(CareerTheme.label(
		"%s %d" % [anchor.month_name(), anchor.year], p.text_primary, p.font_size_heading
	))
	var next_button: Button = CareerTheme.button("Next >")
	next_button.pressed.connect(func() -> void:
		_month_offset += 1
		refresh()
	)
	toolbar.add_child(next_button)
	var today_button: Button = CareerTheme.button("Today")
	today_button.pressed.connect(func() -> void:
		_month_offset = 0
		refresh()
	)
	toolbar.add_child(today_button)

	var status: HBoxContainer = CareerTheme.row(14)
	host.add_child(status)
	status.add_child(CareerTheme.secondary("Phase: %s" % career.phase_name()))
	status.add_child(CareerTheme.label(
		"Transfer window OPEN" if career.transfer_window_open else "Transfer window closed",
		p.positive if career.transfer_window_open else p.text_muted
	))

	var body: VBoxContainer = CareerTheme.card("")
	host.add_child(CareerTheme.card_root(body))

	# Weekday header.
	var week_header: HBoxContainer = CareerTheme.header_row()
	body.add_child(CareerTheme.data_row_root(week_header))
	for day_name: String in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]:
		var h: Label = CareerTheme.cell(day_name, 96, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		week_header.add_child(h)

	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)

	# Leading blanks so the 1st lands on its real weekday.
	var first: CareerDate = CareerDate.make(anchor.year, anchor.month, 1)
	for _blank: int in range(first.day_of_week()):
		grid.add_child(_empty_cell())

	var days: int = CareerDate.days_in_month(anchor.year, anchor.month)
	for day: int in range(1, days + 1):
		var date: CareerDate = CareerDate.make(anchor.year, anchor.month, day)
		grid.add_child(_day_cell(date, career, p))


func _viewed_month(career: CareerSaveData) -> CareerDate:
	var month: int = career.today.month + _month_offset
	var year: int = career.today.year
	while month > 12:
		month -= 12
		year += 1
	while month < 1:
		month += 12
		year -= 1
	return CareerDate.make(year, month, 1)


func _empty_cell() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, 58.0)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _day_cell(date: CareerDate, career: CareerSaveData, p: CareerThemePalette) -> Control:
	var is_today: bool = date.equals(career.today)
	var fixtures: Array[FixtureData] = career.fixtures_on(date)
	var user_fixture: FixtureData = null
	for f: FixtureData in fixtures:
		if f.involves(career.user_team_index):
			user_fixture = f
			break

	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(0.0, 58.0)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg: Color = p.panel
	if is_today:
		bg = p.accent_dim
	elif user_fixture != null:
		bg = p.header
	cell.add_theme_stylebox_override("panel", CareerTheme.style_box(bg, p.corner_radius))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	cell.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	margin.add_child(column)
	column.add_child(CareerTheme.label(
		str(date.day), p.accent if is_today else p.text_muted, p.font_size_small
	))

	if user_fixture != null:
		var opponent: TeamData = DataLoader.get_team(user_fixture.opponent_of(career.user_team_index))
		var prefix: String = "v " if user_fixture.is_home_for(career.user_team_index) else "@ "
		var name_label: Label = CareerTheme.label(
			prefix + (opponent.team_name if opponent != null else "?"),
			p.text_primary, p.font_size_small
		)
		name_label.clip_text = true
		column.add_child(name_label)
		if user_fixture.played:
			var result: String = user_fixture.result_char_for(career.user_team_index)
			column.add_child(CareerTheme.label(
				"%s %d-%d" % [
					result,
					user_fixture.goals_for(career.user_team_index),
					user_fixture.goals_against(career.user_team_index)
				],
				CareerTheme.result_color(result), p.font_size_small
			))
		else:
			column.add_child(CareerTheme.label(
				user_fixture.competition_short(), p.text_muted, p.font_size_small
			))
	elif career.training != null:
		var session: TrainingSchedule.Session = career.training.session_for_day(date.day_of_week())
		column.add_child(CareerTheme.label(
			TrainingSchedule.session_name(session), p.text_muted, p.font_size_small
		))
	return cell
