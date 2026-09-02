##
## FinancesPanel
##
## Club balance, both budgets, the income/expense ledger, the weekly wage
## breakdown, and outstanding transfer instalments.
##
## Depends on: CareerPanel, CareerTheme, ClubFinances, ContractData.
##

class_name FinancesPanel
extends CareerPanel


func title() -> String:
	return "Finances"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var team: TeamData = club(career)
	var finances: ClubFinances = career.user_finances()
	if team == null or finances == null:
		empty_state(host, "No financial data.")
		return

	var contracts: Dictionary = {}
	for squad_index: int in range(team.squad.size()):
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if state != null and state.contract != null:
			contracts[squad_index] = state.contract

	host.add_child(CareerTheme.card_root(_summary_card(career, team, finances, contracts, p)))
	var split: HBoxContainer = CareerTheme.row(10)
	host.add_child(split)
	split.add_child(CareerTheme.card_root(_ledger_card(finances, p)))
	split.add_child(CareerTheme.card_root(_wages_card(career, team, p)))
	host.add_child(CareerTheme.card_root(_instalments_card(finances, p)))


func _summary_card(
	career: CareerSaveData,
	team: TeamData,
	finances: ClubFinances,
	contracts: Dictionary,
	p: CareerThemePalette
) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Summary")
	var wages: int = finances.weekly_wage_bill(team, contracts)
	var staff_wages: int = finances.weekly_staff_bill(team)
	var projected: int = finances.project_end_of_season(team, contracts, team.reputation, career.today)

	var stats: HBoxContainer = CareerTheme.row(24)
	body.add_child(stats)
	stats.add_child(_stat("Balance", CareerTheme.money(finances.balance),
		p.positive if finances.balance >= 0 else p.danger, p))
	stats.add_child(_stat("Transfer budget", CareerTheme.money(finances.transfer_budget), p.text_primary, p))
	stats.add_child(_stat("Wage budget", "%s/wk" % CareerTheme.money(finances.wage_budget_weekly), p.text_primary, p))
	stats.add_child(_stat("Wage bill", "%s/wk" % CareerTheme.money(wages + staff_wages),
		p.danger if (wages + staff_wages) > finances.wage_budget_weekly else p.text_primary, p))
	stats.add_child(_stat("Projected (30 Jun)", CareerTheme.money(projected),
		p.positive if projected >= 0 else p.danger, p))

	var headroom: float = 0.0
	if finances.wage_budget_weekly > 0:
		headroom = clampf(float(wages + staff_wages) / float(finances.wage_budget_weekly), 0.0, 1.0)
	var usage: HBoxContainer = CareerTheme.row()
	body.add_child(usage)
	usage.add_child(CareerTheme.cell("Wage budget used", 140, p.text_muted))
	usage.add_child(CareerTheme.bar(1.0 - headroom, 180))
	usage.add_child(CareerTheme.label("%d%%" % int(headroom * 100.0), p.text_secondary))

	if finances.spending_frozen:
		body.add_child(CareerTheme.label(
			"The board have frozen transfer spending until the balance recovers.", p.danger
		))

	body.add_child(CareerTheme.divider())
	body.add_child(CareerTheme.muted(
		"Reallocating between budgets needs board approval. Converting transfer cash into wage headroom costs roughly one season of that wage."
	))
	var actions: HBoxContainer = CareerTheme.row()
	body.add_child(actions)
	var to_wages: Button = CareerTheme.button("Move 1M to wages")
	to_wages.disabled = finances.transfer_budget < 1_000_000
	to_wages.pressed.connect(func() -> void:
		if finances.reallocate(-1_000_000):
			CareerManager.save_career()
		refresh()
	)
	actions.add_child(to_wages)
	var to_transfers: Button = CareerTheme.button("Move wages to transfers")
	to_transfers.disabled = finances.wage_budget_weekly < 20_000
	to_transfers.pressed.connect(func() -> void:
		if finances.reallocate(1_000_000):
			CareerManager.save_career()
		refresh()
	)
	actions.add_child(to_transfers)
	return body


func _ledger_card(finances: ClubFinances, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Season Ledger")
	for i: int in range(ClubFinances.LINE_NAMES.size()):
		var income: int = finances.season_income[i] if i < finances.season_income.size() else 0
		var expense: int = finances.season_expense[i] if i < finances.season_expense.size() else 0
		if income == 0 and expense == 0:
			continue
		var line: HBoxContainer = CareerTheme.data_row(i)
		line.add_child(CareerTheme.cell(ClubFinances.LINE_NAMES[i], 150, p.text_secondary))
		line.add_child(CareerTheme.cell(
			CareerTheme.money(income) if income > 0 else "—", 90, p.positive, HORIZONTAL_ALIGNMENT_RIGHT
		))
		line.add_child(CareerTheme.cell(
			CareerTheme.money(expense) if expense > 0 else "—", 90, p.danger, HORIZONTAL_ALIGNMENT_RIGHT
		))
		body.add_child(CareerTheme.data_row_root(line))

	body.add_child(CareerTheme.divider())
	var total: HBoxContainer = CareerTheme.row()
	total.add_child(CareerTheme.cell("Net", 150, p.text_primary))
	var net: int = finances.total_income() - finances.total_expense()
	total.add_child(CareerTheme.cell(
		CareerTheme.money(net), 180, p.positive if net >= 0 else p.danger, HORIZONTAL_ALIGNMENT_RIGHT
	))
	body.add_child(total)
	return body


func _wages_card(career: CareerSaveData, team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Wage Breakdown")
	var order: Array[int] = []
	for i: int in range(team.squad.size()):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return team.squad[a].wage_weekly > team.squad[b].wage_weekly
	)

	var shown: int = mini(order.size(), 12)
	for i: int in range(shown):
		var squad_index: int = order[i]
		var data: PlayerData = team.squad[squad_index]
		var line: HBoxContainer = CareerTheme.data_row(i)
		line.add_child(CareerTheme.cell(data.player_name, 150, p.text_primary))
		line.add_child(CareerTheme.cell(data.position_role, 40, p.text_muted))
		line.add_child(CareerTheme.cell(
			"%s/wk" % CareerTheme.money(data.wage_weekly), 84, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
		))
		body.add_child(CareerTheme.data_row_root(line))
	if order.size() > shown:
		body.add_child(CareerTheme.muted("... and %d more" % (order.size() - shown)))

	if not team.staff.is_empty():
		body.add_child(CareerTheme.divider())
		body.add_child(CareerTheme.muted("STAFF"))
		for s: StaffData in team.staff:
			var line2: HBoxContainer = CareerTheme.row()
			line2.add_child(CareerTheme.cell(s.staff_name, 150, p.text_secondary))
			line2.add_child(CareerTheme.cell(s.role, 40, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
			line2.add_child(CareerTheme.cell(
				"%s/wk" % CareerTheme.money(s.salary_weekly), 84, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
			))
			body.add_child(line2)
	return body


func _instalments_card(finances: ClubFinances, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Outstanding Instalments")
	if finances.payables.is_empty() and finances.receivables.is_empty():
		body.add_child(CareerTheme.muted("No instalments outstanding."))
		return body
	for entry: Dictionary in finances.payables:
		var line: HBoxContainer = CareerTheme.row()
		line.add_child(CareerTheme.cell("Owed", 70, p.danger))
		line.add_child(CareerTheme.cell(String(entry.get("note", "")), 180, p.text_secondary))
		line.add_child(CareerTheme.cell(str(entry.get("season_year", 0)), 60, p.text_muted))
		line.add_child(CareerTheme.cell(
			CareerTheme.money(int(entry.get("amount", 0))), 90, p.danger, HORIZONTAL_ALIGNMENT_RIGHT
		))
		body.add_child(line)
	for entry2: Dictionary in finances.receivables:
		var line2: HBoxContainer = CareerTheme.row()
		line2.add_child(CareerTheme.cell("Due in", 70, p.positive))
		line2.add_child(CareerTheme.cell(String(entry2.get("note", "")), 180, p.text_secondary))
		line2.add_child(CareerTheme.cell(str(entry2.get("season_year", 0)), 60, p.text_muted))
		line2.add_child(CareerTheme.cell(
			CareerTheme.money(int(entry2.get("amount", 0))), 90, p.positive, HORIZONTAL_ALIGNMENT_RIGHT
		))
		body.add_child(line2)
	return body


func _stat(caption: String, value: String, tint: Color, p: CareerThemePalette) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(CareerTheme.label(value, tint, p.font_size_heading))
	box.add_child(CareerTheme.label(caption, p.text_muted, p.font_size_small))
	return box
