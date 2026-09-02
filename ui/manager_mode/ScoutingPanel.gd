##
## ScoutingPanel
##
## The scouting network: who is assigned to what, how far each report has
## progressed, and the pipeline stage of every tracked target.
##
## Depends on: CareerPanel, CareerTheme, ScoutingNetwork, ScoutReport.
##

class_name ScoutingPanel
extends CareerPanel


func title() -> String:
	return "Scouting"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var team: TeamData = club(career)
	if team == null:
		empty_state(host, "No club loaded.")
		return

	host.add_child(CareerTheme.card_root(_network_card(career, team, p)))
	host.add_child(CareerTheme.card_root(_reports_card(career, p)))


func _network_card(career: CareerSaveData, team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Scouting Network")
	var scouts: Array[StaffData] = ScoutingNetwork.available_scouts(team)

	if career.board != null:
		var reach: HBoxContainer = CareerTheme.row()
		reach.add_child(CareerTheme.cell("Network reach", 130, p.text_muted))
		reach.add_child(CareerTheme.bar(float(career.board.scouting_range) / 5.0, 140))
		reach.add_child(CareerTheme.label("Level %d of 5" % career.board.scouting_range, p.text_secondary))
		body.add_child(reach)

	if scouts.is_empty():
		body.add_child(CareerTheme.label(
			"You employ no scouts. Reports will not progress and no new targets will be found.",
			p.danger
		))
		return body

	body.add_child(CareerTheme.divider())
	for i: int in range(scouts.size()):
		var scout: StaffData = scouts[i]
		var load: int = ScoutingNetwork.caseload(career, scout.staff_name)
		var line: HBoxContainer = CareerTheme.data_row(i)
		line.add_child(CareerTheme.cell(scout.staff_name, 160, p.text_primary))
		line.add_child(CareerTheme.cell(scout.role, 120, p.text_secondary))
		line.add_child(CareerTheme.cell("Judging", 60, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
		line.add_child(CareerTheme.bar(scout.judging_ability, 90))
		var overloaded: bool = load > ScoutingNetwork.REPORTS_PER_SCOUT
		line.add_child(CareerTheme.cell(
			"%d assignment%s" % [load, "" if load == 1 else "s"], 110,
			p.warning if overloaded else p.text_secondary
		))
		body.add_child(CareerTheme.data_row_root(line))
		if overloaded:
			body.add_child(CareerTheme.muted(
				"Carrying more than %d targets slows every report proportionally." % ScoutingNetwork.REPORTS_PER_SCOUT
			))
	return body


func _reports_card(career: CareerSaveData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Reports")
	if career.scout_reports.is_empty():
		body.add_child(CareerTheme.muted(
			"No reports yet. Assign a scout to a target from the Transfers screen."
		))
		return body

	var header: HBoxContainer = CareerTheme.header_row()
	body.add_child(CareerTheme.data_row_root(header))
	header.add_child(CareerTheme.cell("Player", 150, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Club", 130, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Pos", 44, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Ability", 66, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Potential", 66, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Knowledge", 100, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Stage", 90, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Scout", 130, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))

	# Best-known first, so the useful reports rise to the top.
	var sorted: Array[ScoutReport] = career.scout_reports.duplicate()
	sorted.sort_custom(func(a: ScoutReport, b: ScoutReport) -> bool:
		return a.knowledge > b.knowledge
	)

	for i: int in range(sorted.size()):
		var report: ScoutReport = sorted[i]
		var line: HBoxContainer = CareerTheme.data_row(i)
		line.add_child(CareerTheme.cell(report.target_name, 150, p.text_primary))
		line.add_child(CareerTheme.cell(report.target_club, 130, p.text_secondary))
		line.add_child(CareerTheme.cell(report.target_position, 44, p.text_secondary))
		line.add_child(CareerTheme.cell(report.display_value(), 66, p.text_primary))
		line.add_child(CareerTheme.cell(report.display_potential(), 66, p.text_secondary))
		line.add_child(CareerTheme.bar(report.knowledge, 96))
		line.add_child(CareerTheme.cell(
			report.stage_name(), 90,
			p.positive if report.is_bid_ready() else p.text_muted,
			HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
		))
		line.add_child(CareerTheme.cell(
			report.assigned_scout_name if report.assigned_scout_name != "" else "Unassigned",
			130,
			p.text_secondary if report.assigned_scout_name != "" else p.warning,
			HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
		))
		body.add_child(CareerTheme.data_row_root(line))

		if report.verdict != "":
			body.add_child(CareerTheme.muted(report.verdict))
	return body
