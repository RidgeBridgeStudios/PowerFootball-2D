##
## StaffPanel
##
## The backroom team: who is employed, what they are good at, what they cost,
## and which coaching families the club is currently thin in.
##
## Depends on: CareerPanel, CareerTheme, StaffData, TrainingSchedule.
##

class_name StaffPanel
extends CareerPanel


enum View { CURRENT = 0, RECRUIT = 1 }
var _view: View = View.CURRENT


func title() -> String:
	return "Staff"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var team: TeamData = club(career)
	if team == null:
		empty_state(host, "No club loaded.")
		return

	var tabs: HBoxContainer = CareerTheme.row(4)
	host.add_child(tabs)

	var btn_current: Button = CareerTheme.button("Backroom Staff", _view == View.CURRENT)
	btn_current.pressed.connect(func() -> void:
		_view = View.CURRENT
		refresh()
	)
	tabs.add_child(btn_current)

	var btn_recruit: Button = CareerTheme.button("Recruitment Market", _view == View.RECRUIT)
	btn_recruit.pressed.connect(func() -> void:
		_view = View.RECRUIT
		refresh()
	)
	tabs.add_child(btn_recruit)

	if _view == View.CURRENT:
		host.add_child(CareerTheme.card_root(_manager_card(career, p)))
		host.add_child(CareerTheme.card_root(_staff_card(team, p)))
		host.add_child(CareerTheme.card_root(_coverage_card(team, p)))
	else:
		host.add_child(CareerTheme.card_root(_recruitment_card(team, p)))


func _manager_card(career: CareerSaveData, p: CareerThemePalette) -> VBoxContainer:
	var profile: ManagerCareerProfile = career.profile
	var body: VBoxContainer = CareerTheme.card("Manager Profile")
	if profile == null:
		body.add_child(CareerTheme.muted("No manager profile."))
		return body

	body.add_child(CareerTheme.label(profile.manager_name, p.text_primary, p.font_size_heading))
	body.add_child(CareerTheme.secondary("%s · %s · %s" % [
		profile.nationality, profile.tier_name(), profile.philosophy_name()
	]))
	body.add_child(CareerTheme.secondary("Background: %s" % profile.background_name()))

	var record: HBoxContainer = CareerTheme.row(18)
	body.add_child(record)
	record.add_child(CareerTheme.secondary("Managed %d" % profile.matches_managed))
	record.add_child(CareerTheme.label("W %d" % profile.wins, p.result_win))
	record.add_child(CareerTheme.label("D %d" % profile.draws, p.result_draw))
	record.add_child(CareerTheme.label("L %d" % profile.losses, p.result_loss))
	record.add_child(CareerTheme.secondary("Win rate %d%%" % int(profile.win_rate() * 100.0)))
	record.add_child(CareerTheme.secondary("Trophies %d" % profile.trophies_won))

	body.add_child(CareerTheme.divider())
	body.add_child(CareerTheme.muted("ATTRIBUTES"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	body.add_child(grid)
	for key: StringName in ManagerCareerProfile.ATTRIBUTE_KEYS:
		var value: float = profile.attribute(key)
		var line: HBoxContainer = CareerTheme.row(6)
		line.add_child(CareerTheme.cell(
			String(ManagerCareerProfile.ATTRIBUTE_LABELS.get(key, String(key))), 150,
			p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
		))
		line.add_child(CareerTheme.bar(value / 20.0, 90))
		line.add_child(CareerTheme.label("%d" % int(round(value)), p.text_secondary, p.font_size_small))
		grid.add_child(line)

	if profile.contract != null:
		body.add_child(CareerTheme.divider())
		body.add_child(CareerTheme.secondary("Your contract: %s/wk, expires %s" % [
			CareerTheme.money(profile.contract.wage_weekly),
			profile.contract.expiry.to_display() if profile.contract.expiry != null else "—"
		]))
	return body


func _staff_card(team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Backroom Staff")
	if team.staff.is_empty():
		body.add_child(CareerTheme.muted("No backroom staff employed."))
		return body

	var header: HBoxContainer = CareerTheme.header_row()
	body.add_child(CareerTheme.data_row_root(header))
	header.add_child(CareerTheme.cell("Name", 160, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Role", 140, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Age", 40, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Coach", 70, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Judging", 70, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Physio", 70, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Tactical", 70, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Wage", 70, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("Action", 80, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))

	for i: int in range(team.staff.size()):
		var s: StaffData = team.staff[i]
		var line: HBoxContainer = CareerTheme.data_row(i)
		line.add_child(CareerTheme.cell(s.staff_name, 160, p.text_primary))
		line.add_child(CareerTheme.cell(s.role, 140, p.text_secondary))
		line.add_child(CareerTheme.cell(str(s.get_age()), 40, p.text_secondary))
		line.add_child(CareerTheme.bar(s.coaching, 66))
		line.add_child(CareerTheme.bar(s.judging_ability, 66))
		line.add_child(CareerTheme.bar(s.physiotherapy, 66))
		line.add_child(CareerTheme.bar(s.tactical_knowledge, 66))
		line.add_child(CareerTheme.cell(
			"%s/wk" % CareerTheme.money(s.salary_weekly), 70, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
		))
		var term_btn: Button = CareerTheme.button("Sack")
		term_btn.pressed.connect(func() -> void:
			CareerManager.sack_staff_member(s)
			refresh()
		)
		line.add_child(term_btn)
		body.add_child(CareerTheme.data_row_root(line))
	return body


func _recruitment_card(team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Staff Recruitment Market")
	body.add_child(CareerTheme.muted(
		"Available backroom personnel seeking positions. Coaches improve player growth, physios accelerate recovery, scouts uncover talent."
	))

	var available: Array[StaffData] = StaffLoader.all_available_staff()
	if available.is_empty():
		body.add_child(CareerTheme.muted("No staff members currently on the market."))
		return body

	var header: HBoxContainer = CareerTheme.header_row()
	body.add_child(CareerTheme.data_row_root(header))
	header.add_child(CareerTheme.cell("Name", 160, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Role", 130, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Age", 40, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Coach", 66, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Judging", 66, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Physio", 66, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Tactical", 66, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Demanded", 80, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("Action", 90, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))

	for i: int in range(available.size()):
		var s: StaffData = available[i]
		var line: HBoxContainer = CareerTheme.data_row(i)
		line.add_child(CareerTheme.cell(s.staff_name, 160, p.text_primary))
		line.add_child(CareerTheme.cell(s.role, 130, p.text_secondary))
		line.add_child(CareerTheme.cell(str(s.get_age()), 40, p.text_secondary))
		line.add_child(CareerTheme.bar(s.coaching, 66))
		line.add_child(CareerTheme.bar(s.judging_ability, 66))
		line.add_child(CareerTheme.bar(s.physiotherapy, 66))
		line.add_child(CareerTheme.bar(s.tactical_knowledge, 66))
		line.add_child(CareerTheme.cell(
			"%s/wk" % CareerTheme.money(s.salary_weekly), 80, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
		))
		var hire_btn: Button = CareerTheme.button("Hire", true)
		hire_btn.pressed.connect(func() -> void:
			CareerManager.hire_staff_member(s, s.salary_weekly, 3)
			refresh()
		)
		line.add_child(hire_btn)
		body.add_child(CareerTheme.data_row_root(line))
	return body


func _coverage_card(team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Coverage")
	body.add_child(CareerTheme.muted(
		"Where the backroom is strong and where it is thin. Coaching quality multiplies every training session; physio quality shortens every lay-off."
	))
	for family: StringName in [&"physical", &"technical", &"mental", &"set_piece"]:
		var quality: float = TrainingSchedule.coach_bonus(team.staff, family)
		var line: HBoxContainer = CareerTheme.row()
		line.add_child(CareerTheme.cell(String(family).capitalize(), 120, p.text_muted))
		line.add_child(CareerTheme.bar(quality, 160))
		line.add_child(CareerTheme.label(
			_quality_label(quality), CareerTheme.tint_for_rating(quality)
		))
		body.add_child(line)

	var has_scout: bool = false
	var has_physio: bool = false
	for s: StaffData in team.staff:
		if s.role.to_lower().contains("scout"):
			has_scout = true
		if s.role.to_lower().contains("physio"):
			has_physio = true
	if not has_scout:
		body.add_child(CareerTheme.label(
			"No scout employed — scout reports will not progress.", p.danger
		))
	if not has_physio:
		body.add_child(CareerTheme.label(
			"No physio employed — injuries will take longer to heal.", p.danger
		))
	return body


func _quality_label(v: float) -> String:
	if v >= 0.85:
		return "Excellent"
	if v >= 0.70:
		return "Good"
	if v >= 0.55:
		return "Adequate"
	if v >= 0.40:
		return "Weak"
	return "Poor"
