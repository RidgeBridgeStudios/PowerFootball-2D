##
## TrainingPanel
##
## The weekly training schedule (first team and youth), the workload gauge,
## individual player focus assignment, and facility/coach quality readouts.
##
## Editing a day cycles through the session list, which is enough interaction
## for a keyboard/mouse UI without a drag-and-drop layer.
##
## Depends on: CareerPanel, CareerTheme, TrainingSchedule, CareerManager.
##

class_name TrainingPanel
extends CareerPanel

const DAY_NAMES: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


func title() -> String:
	return "Training"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var team: TeamData = club(career)
	if team == null or career.training == null:
		empty_state(host, "No training schedule.")
		return

	host.add_child(CareerTheme.card_root(_workload_card(career, team, p)))
	host.add_child(CareerTheme.card_root(_week_card(career, p, false)))
	host.add_child(CareerTheme.card_root(_week_card(career, p, true)))
	host.add_child(CareerTheme.card_root(_individual_card(career, team, p)))


func _workload_card(career: CareerSaveData, team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Workload")
	var intensity: float = career.training.weekly_intensity()

	var gauge: HBoxContainer = CareerTheme.row()
	gauge.add_child(CareerTheme.cell("Weekly intensity", 130, p.text_muted))
	gauge.add_child(CareerTheme.bar(intensity, 160))
	gauge.add_child(CareerTheme.label(
		career.training.weekly_intensity_label(),
		p.danger if intensity >= 0.70 else (p.warning if intensity >= 0.55 else p.positive)
	))
	body.add_child(gauge)
	body.add_child(CareerTheme.muted(
		"Heavy weeks build ability and sharpness but drain condition and raise injury risk. Light weeks protect legs and slow development."
	))

	body.add_child(CareerTheme.divider())
	if career.board != null:
		var facilities: int = career.board.training_facilities
		var facility_row: HBoxContainer = CareerTheme.row()
		facility_row.add_child(CareerTheme.cell("Training facilities", 130, p.text_muted))
		facility_row.add_child(CareerTheme.bar(float(facilities) / 5.0, 110))
		facility_row.add_child(CareerTheme.label(
			"Level %d of 5  (x%.2f)" % [facilities, career.board.facility_multiplier(facilities)],
			p.text_secondary
		))
		body.add_child(facility_row)

	# Coach quality per training family, so a manager can see where they are thin.
	for family: StringName in [&"physical", &"technical", &"mental", &"set_piece"]:
		var quality: float = TrainingSchedule.coach_bonus(team.staff, family)
		var line: HBoxContainer = CareerTheme.row()
		line.add_child(CareerTheme.cell(String(family).capitalize() + " coaching", 130, p.text_muted))
		line.add_child(CareerTheme.bar(quality, 110))
		line.add_child(CareerTheme.label("%d%%" % int(quality * 100.0), p.text_secondary))
		body.add_child(line)

	# Average squad condition — the number the workload is actually costing.
	var total_condition: float = 0.0
	var counted: int = 0
	for squad_index: int in range(team.squad.size()):
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if state != null:
			total_condition += state.condition
			counted += 1
	if counted > 0:
		var average: float = total_condition / float(counted)
		var condition_row: HBoxContainer = CareerTheme.row()
		condition_row.add_child(CareerTheme.cell("Squad condition", 130, p.text_muted))
		condition_row.add_child(CareerTheme.bar(average, 110))
		condition_row.add_child(CareerTheme.label("%d%%" % int(average * 100.0), CareerTheme.tint_for_rating(average)))
		body.add_child(condition_row)
	return body


func _week_card(career: CareerSaveData, p: CareerThemePalette, youth: bool) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Youth Schedule" if youth else "First Team Schedule")
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)

	for day: int in range(7):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 3)
		column.add_child(CareerTheme.label(DAY_NAMES[day], p.text_muted, p.font_size_small))

		var session: TrainingSchedule.Session = career.training.youth_session_for_day(day) \
			if youth else career.training.session_for_day(day)
		var b: Button = CareerTheme.button(TrainingSchedule.session_name(session))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			var next_session: int = (int(session) + 1) % TrainingSchedule.SESSION_NAMES.size()
			if youth:
				career.training.set_youth_day(day, next_session as TrainingSchedule.Session)
			else:
				career.training.set_day(day, next_session as TrainingSchedule.Session)
			CareerManager.save_career()
			refresh()
		)
		column.add_child(b)
		column.add_child(CareerTheme.bar(TrainingSchedule.intensity_of(session), 70))
		grid.add_child(column)

	body.add_child(CareerTheme.muted("Click a day to cycle its session."))
	return body


func _individual_card(career: CareerSaveData, team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Individual Focus")

	var header: HBoxContainer = CareerTheme.header_row()
	body.add_child(CareerTheme.data_row_root(header))
	header.add_child(CareerTheme.cell("Player", 160, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Pos", 40, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Age", 34, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Condition", 70, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Trajectory", 120, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Focus", 150, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))

	for squad_index: int in range(team.squad.size()):
		var data: PlayerData = team.squad[squad_index]
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if state == null:
			continue
		var line: HBoxContainer = CareerTheme.data_row(squad_index)
		var age: int = data.get_age(career.today.year, career.today.month, career.today.day)

		line.add_child(CareerTheme.cell(data.player_name, 160, p.text_primary))
		line.add_child(CareerTheme.cell(data.position_role, 40, p.text_secondary))
		line.add_child(CareerTheme.cell(str(age), 34, p.text_secondary))
		if state.is_injured():
			line.add_child(CareerTheme.cell(state.injury_name(), 70, p.danger, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
		else:
			line.add_child(CareerTheme.bar(state.condition, 66))
		line.add_child(CareerTheme.cell(
			PlayerDevelopmentEngine.development_label(data, state, age), 120,
			p.text_secondary, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
		))

		var focus: TrainingSchedule.Focus = career.training.focus_for_player(squad_index)
		var focus_button: Button = CareerTheme.button(TrainingSchedule.focus_name(focus))
		focus_button.custom_minimum_size = Vector2(150.0, 0.0)
		focus_button.pressed.connect(func() -> void:
			var next_focus: int = (int(focus) + 1) % TrainingSchedule.FOCUS_NAMES.size()
			career.training.set_focus(squad_index, next_focus as TrainingSchedule.Focus)
			CareerManager.save_career()
			refresh()
		)
		line.add_child(focus_button)
		body.add_child(CareerTheme.data_row_root(line))
	return body
