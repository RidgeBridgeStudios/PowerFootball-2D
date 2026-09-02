##
## SquadPanel
##
## The squad list and the player deep-dive. Data-dense rows in the FM idiom:
## number, name, position, age, overall, condition, sharpness, morale, form,
## contract, value, wage, availability — sortable, with the selected player's
## full profile expanded beneath.
##
## Depends on: CareerPanel, CareerTheme, PlayerCareerState, MoraleEngine,
##             PlayerDevelopmentEngine, TransferMarket, WorldEventLog.
##

class_name SquadPanel
extends CareerPanel

enum Sort { NUMBER = 0, NAME = 1, POSITION = 2, AGE = 3, OVERALL = 4, MORALE = 5, VALUE = 6, CONTRACT = 7 }
enum SquadFilter { ALL = 0, SENIOR = 1, U23 = 2 }

const SORT_LABELS: Array[String] = [
	"#", "Name", "Pos", "Age", "OVR", "Morale", "Value", "Contract"
]

var _sort: Sort = Sort.OVERALL
var _descending: bool = true
var _selected_squad_index: int = -1
var _show_unhappy_only: bool = false
var _squad_filter: SquadFilter = SquadFilter.ALL


func title() -> String:
	return "Squad"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var team: TeamData = club(career)
	if team == null or team.squad.is_empty():
		empty_state(host, "No squad loaded.")
		return

	# --- Toolbar ---
	var toolbar: HBoxContainer = CareerTheme.row()
	host.add_child(toolbar)
	toolbar.add_child(CareerTheme.secondary("%d players" % team.squad.size()))
	var payroll: int = team.get_weekly_payroll()
	toolbar.add_child(CareerTheme.secondary("Payroll %s/wk" % CareerTheme.money(payroll)))

	var filter_all: Button = CareerTheme.button("All", _squad_filter == SquadFilter.ALL)
	filter_all.pressed.connect(func() -> void:
		_squad_filter = SquadFilter.ALL
		refresh()
	)
	toolbar.add_child(filter_all)

	var filter_senior: Button = CareerTheme.button("First Team", _squad_filter == SquadFilter.SENIOR)
	filter_senior.pressed.connect(func() -> void:
		_squad_filter = SquadFilter.SENIOR
		refresh()
	)
	toolbar.add_child(filter_senior)

	var filter_u23: Button = CareerTheme.button("Under-23s", _squad_filter == SquadFilter.U23)
	filter_u23.pressed.connect(func() -> void:
		_squad_filter = SquadFilter.U23
		refresh()
	)
	toolbar.add_child(filter_u23)

	var filter: Button = CareerTheme.button(
		"Showing: Unhappy only" if _show_unhappy_only else "Unhappy only"
	)
	filter.pressed.connect(func() -> void:
		_show_unhappy_only = not _show_unhappy_only
		refresh()
	)
	toolbar.add_child(filter)

	# --- Header (click a column to sort) ---
	var header: HBoxContainer = CareerTheme.header_row()
	host.add_child(CareerTheme.data_row_root(header))
	_sort_header(header, Sort.NUMBER, 30)
	_sort_header(header, Sort.NAME, 150)
	_sort_header(header, Sort.POSITION, 44)
	_sort_header(header, Sort.AGE, 36)
	_sort_header(header, Sort.OVERALL, 40)
	header.add_child(CareerTheme.cell("Cond", 54, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Sharp", 54, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	_sort_header(header, Sort.MORALE, 76)
	header.add_child(CareerTheme.cell("Form", 40, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	_sort_header(header, Sort.VALUE, 62)
	header.add_child(CareerTheme.cell("Wage", 62, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	_sort_header(header, Sort.CONTRACT, 62)
	header.add_child(CareerTheme.cell("Status", 118, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))

	# --- Rows ---
	var order: Array[int] = _sorted_indices(team, career)
	var shown: int = 0
	for squad_index: int in order:
		var data: PlayerData = team.squad[squad_index]
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if _show_unhappy_only and data.morale >= 0.40:
			continue
		if _squad_filter == SquadFilter.SENIOR and state != null and state.in_u23_squad:
			continue
		if _squad_filter == SquadFilter.U23 and (state == null or not state.in_u23_squad):
			continue
		host.add_child(_player_row(data, state, squad_index, shown, career, p, team))
		shown += 1
		if squad_index == _selected_squad_index:
			host.add_child(CareerTheme.card_root(
				_player_profile(data, state, career, p, team)
			))

	if shown == 0:
		empty_state(host, "No players match this filter.")


func _sort_header(header: HBoxContainer, sort: Sort, width: int) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var active: bool = _sort == sort
	var text: String = SORT_LABELS[int(sort)]
	if active:
		text += " ▼" if _descending else " ▲"
	var b: Button = CareerTheme.button(text)
	b.custom_minimum_size = Vector2(float(width), 0.0)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", p.font_size_small)
	b.add_theme_color_override("font_color", p.accent if active else p.text_muted)
	var flat: StyleBoxFlat = CareerTheme.style_box(Color(0, 0, 0, 0), 0)
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("focus", flat)
	b.pressed.connect(func() -> void:
		if _sort == sort:
			_descending = not _descending
		else:
			_sort = sort
			_descending = true
		refresh()
	)
	header.add_child(b)


func _sorted_indices(team: TeamData, career: CareerSaveData) -> Array[int]:
	var indices: Array[int] = []
	for i: int in range(team.squad.size()):
		indices.append(i)

	var sort_mode: Sort = _sort
	var descending: bool = _descending
	var user_index: int = career.user_team_index
	indices.sort_custom(func(a: int, b: int) -> bool:
		var pa: PlayerData = team.squad[a]
		var pb: PlayerData = team.squad[b]
		var va: float = 0.0
		var vb: float = 0.0
		match sort_mode:
			Sort.NUMBER:
				va = float(pa.shirt_number)
				vb = float(pb.shirt_number)
			Sort.AGE:
				va = float(pa.get_age())
				vb = float(pb.get_age())
			Sort.OVERALL:
				va = float(pa.calculate_overall_rating())
				vb = float(pb.calculate_overall_rating())
			Sort.MORALE:
				va = pa.morale
				vb = pb.morale
			Sort.VALUE:
				va = float(pa.market_value)
				vb = float(pb.market_value)
			Sort.CONTRACT:
				var sa: PlayerCareerState = career.state_for_squad(user_index, a)
				var sb: PlayerCareerState = career.state_for_squad(user_index, b)
				va = float(sa.contract.days_remaining(career.today)) if sa != null and sa.contract != null else 0.0
				vb = float(sb.contract.days_remaining(career.today)) if sb != null and sb.contract != null else 0.0
			Sort.NAME:
				return pa.player_name < pb.player_name if descending else pa.player_name > pb.player_name
			Sort.POSITION:
				return pa.position_role < pb.position_role if descending else pa.position_role > pb.position_role
			_:
				va = float(a)
				vb = float(b)
		return va > vb if descending else va < vb
	)
	return indices


func _player_row(
	data: PlayerData,
	state: PlayerCareerState,
	squad_index: int,
	display_index: int,
	career: CareerSaveData,
	p: CareerThemePalette,
	team: TeamData
) -> Control:
	var selected: bool = squad_index == _selected_squad_index
	var line: HBoxContainer = CareerTheme.data_row(display_index, selected)
	var in_xi: bool = team.lineup_indices.has(squad_index)
	var name_tint: Color = p.accent if selected else (p.text_primary if in_xi else p.text_secondary)

	line.add_child(CareerTheme.cell(str(data.shirt_number), 30, p.text_muted))

	var name_button: Button = CareerTheme.button(data.player_name)
	name_button.custom_minimum_size = Vector2(150.0, 0.0)
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.add_theme_color_override("font_color", name_tint)
	var flat: StyleBoxFlat = CareerTheme.style_box(Color(0, 0, 0, 0), 0)
	name_button.add_theme_stylebox_override("normal", flat)
	name_button.add_theme_stylebox_override("focus", flat)
	name_button.pressed.connect(func() -> void:
		_selected_squad_index = -1 if selected else squad_index
		refresh()
	)
	line.add_child(name_button)

	line.add_child(CareerTheme.cell(data.position_role, 44, p.text_secondary))
	line.add_child(CareerTheme.cell(str(data.get_age(career.today.year, career.today.month, career.today.day)), 36, p.text_secondary))

	var overall: int = data.calculate_overall_rating()
	line.add_child(CareerTheme.cell(
		str(overall), 40, CareerTheme.tint_for_rating(float(overall - 45) / 54.0)
	))

	if state != null:
		line.add_child(CareerTheme.bar(state.condition, 50))
		line.add_child(CareerTheme.bar(state.sharpness, 50))
	else:
		line.add_child(CareerTheme.cell("—", 54, p.text_muted))
		line.add_child(CareerTheme.cell("—", 54, p.text_muted))

	line.add_child(CareerTheme.cell(
		MoraleEngine.morale_label(data.morale), 76, MoraleEngine.morale_color(data.morale),
		HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
	))
	line.add_child(CareerTheme.cell(
		"%.1f" % data.form, 40, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
	))
	line.add_child(CareerTheme.cell(
		CareerTheme.money(TransferMarket.market_value(data, state, career.today)),
		62, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
	))
	line.add_child(CareerTheme.cell(
		CareerTheme.money(data.wage_weekly), 62, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
	))

	var contract_text: String = "—"
	var contract_tint: Color = p.text_secondary
	if state != null and state.contract != null:
		var years: float = state.contract.years_remaining(career.today)
		contract_text = "%.1f yr" % years
		if state.contract.is_in_final_six_months(career.today):
			contract_tint = p.danger
		elif years < 1.5:
			contract_tint = p.warning
	line.add_child(CareerTheme.cell(contract_text, 62, contract_tint, HORIZONTAL_ALIGNMENT_RIGHT))

	var status: String = "Available"
	var status_tint: Color = p.text_muted
	if state != null and not state.is_available():
		status = state.availability_label()
		status_tint = p.danger
	elif state != null and state.transfer_listed:
		status = "Transfer listed"
		status_tint = p.warning
	elif in_xi:
		status = "Starting XI"
		status_tint = p.positive
	line.add_child(CareerTheme.cell(status, 118, status_tint, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))

	return CareerTheme.data_row_root(line)


func _player_profile(
	data: PlayerData,
	state: PlayerCareerState,
	career: CareerSaveData,
	p: CareerThemePalette,
	team: TeamData
) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("%s  ·  #%d  ·  %s" % [
		data.player_name, data.shirt_number, data.position_role
	])

	var columns: HBoxContainer = CareerTheme.row(16)
	body.add_child(columns)

	# --- Personal + contract ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	columns.add_child(left)
	left.add_child(CareerTheme.muted("PERSONAL"))
	left.add_child(_kv("Age", data.get_age_detail_string(career.today.year, career.today.month, career.today.day), p))
	left.add_child(_kv("Nationality", data.nationality, p))
	left.add_child(_kv("Personality", data.get_personality_archetype(), p))
	left.add_child(_kv("Reputation", "%d%%" % int(data.player_reputation * 100.0), p))
	left.add_child(CareerTheme.spacer(4))
	left.add_child(CareerTheme.muted("CONTRACT"))
	if state != null and state.contract != null:
		left.add_child(_kv("Wage", "%s/wk" % CareerTheme.money(state.contract.wage_weekly), p))
		left.add_child(_kv("Expires", state.contract.expiry.to_display() if state.contract.expiry != null else "—", p))
		left.add_child(_kv("Promised", state.contract.status_name(), p))
		if state.contract.release_clause > 0:
			left.add_child(_kv("Release clause", CareerTheme.money(state.contract.release_clause), p))
	left.add_child(_kv("Value", CareerTheme.money(TransferMarket.market_value(data, state, career.today)), p))

	# --- Attributes ---
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	columns.add_child(mid)
	mid.add_child(CareerTheme.muted("ATTRIBUTES"))
	mid.add_child(_attr_bar("Pace", (data.top_speed - 160.0) / 100.0, p))
	mid.add_child(_attr_bar("Acceleration", 1.0 - (data.acceleration_time - 0.11) / 0.29, p))
	mid.add_child(_attr_bar("Stamina", (data.stamina_max - 60.0) / 80.0, p))
	mid.add_child(_attr_bar("Technique", data.close_control, p))
	mid.add_child(_attr_bar("Vision", data.vision, p))
	mid.add_child(_attr_bar("Composure", data.composure, p))
	mid.add_child(_attr_bar("Aggression", data.aggression, p))
	mid.add_child(_attr_bar("Work Rate", data.work_rate, p))
	mid.add_child(_attr_bar("Determination", data.determination, p))
	mid.add_child(_attr_bar("Leadership", data.leadership, p))
	if data.position_role == "GK":
		mid.add_child(_attr_bar("Reflexes", data.reflexes, p))

	# --- Season, development, relationships ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 2)
	columns.add_child(right)
	right.add_child(CareerTheme.muted("THIS SEASON"))
	if state != null:
		right.add_child(_kv("Appearances", str(state.appearances), p))
		right.add_child(_kv("Minutes", str(state.minutes_played), p))
		right.add_child(_kv("Goals / Assists", "%d / %d" % [state.goals_this_season, state.assists_this_season], p))
		right.add_child(_kv("Average rating", "%.2f" % state.average_rating, p))
		right.add_child(CareerTheme.spacer(4))
		right.add_child(CareerTheme.muted("DEVELOPMENT"))
		var age: int = data.get_age(career.today.year, career.today.month, career.today.day)
		right.add_child(_kv("Trajectory", PlayerDevelopmentEngine.development_label(data, state, age), p))
		right.add_child(_kv("Condition", state.condition_label(), p))
		right.add_child(_kv("Injury risk", "%d%%" % int(state.injury_proneness * 100.0), p))
		right.add_child(CareerTheme.spacer(4))
		right.add_child(CareerTheme.muted("RELATIONSHIPS"))
		right.add_child(_kv("Manager trust", "%d%%" % int(state.manager_trust * 100.0), p))
		var notable: int = 0
		for other_key: int in state.relationships:
			if notable >= 4:
				break
			var rel: RelationshipData = state.relationships[other_key] as RelationshipData
			if rel == null:
				continue
			if rel.trust >= 0.75 or rel.trust <= 0.30 or rel.rivalry_score >= 0.3:
				var other_state: PlayerCareerState = career.state_for(other_key)
				var other_name: String = other_state.display_name if other_state != null else "Teammate"
				right.add_child(_kv(other_name, rel.relation_label(), p))
				notable += 1
		if notable == 0:
			right.add_child(CareerTheme.muted("Nothing notable."))

	# --- Career history from the world event log ---
	var events: Array[WorldEvent] = WorldEventLog.for_player(
		state.player_key if state != null else -1, 5
	)
	if not events.is_empty():
		body.add_child(CareerTheme.divider())
		body.add_child(CareerTheme.muted("HISTORY"))
		for e: WorldEvent in events:
			body.add_child(CareerTheme.label(
				"%s — %s" % [e.date.to_display() if e.date != null else "", e.narrative_context],
				p.text_secondary, p.font_size_small
			))

	# --- Actions ---
	body.add_child(CareerTheme.divider())
	var actions: HBoxContainer = CareerTheme.row()
	body.add_child(actions)
	if state != null:
		var list_button: Button = CareerTheme.button(
			"Remove from transfer list" if state.transfer_listed else "Add to transfer list"
		)
		list_button.pressed.connect(func() -> void:
			state.transfer_listed = not state.transfer_listed
			CareerManager.save_career()
			refresh()
		)
		actions.add_child(list_button)

		var loan_button: Button = CareerTheme.button(
			"Remove from loan list" if state.loan_listed else "Add to loan list"
		)
		loan_button.pressed.connect(func() -> void:
			state.loan_listed = not state.loan_listed
			CareerManager.save_career()
			refresh()
		)
		actions.add_child(loan_button)

		var u23_button: Button = CareerTheme.button(
			"Promote to First Team" if state.in_u23_squad else "Move to Under-23s"
		)
		u23_button.pressed.connect(func() -> void:
			state.in_u23_squad = not state.in_u23_squad
			CareerManager.save_career()
			refresh()
		)
		actions.add_child(u23_button)

		var contract_button: Button = CareerTheme.button("Offer New Contract", true)
		contract_button.pressed.connect(func() -> void:
			var modal: ContractNegotiationModal = ContractNegotiationModal.open_modal(
				self, data, state, team, false
			)
			modal.negotiation_finished.connect(func(_succ: bool, _c: ContractData) -> void:
				CareerManager.save_career()
				refresh()
			)
		)
		actions.add_child(contract_button)

	var captain_button: Button = CareerTheme.button("Make captain")
	captain_button.disabled = data.is_captain
	captain_button.pressed.connect(func() -> void:
		for other: PlayerData in team.squad:
			other.is_captain = false
		data.is_captain = true
		team.captain_index = _selected_squad_index
		CareerManager.save_career()
		refresh()
	)
	actions.add_child(captain_button)
	return body


func _kv(key: String, value: String, p: CareerThemePalette) -> HBoxContainer:
	var line: HBoxContainer = CareerTheme.row(6)
	line.add_child(CareerTheme.cell(key, 108, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	line.add_child(CareerTheme.label(value, p.text_primary, p.font_size_small))
	return line


func _attr_bar(label_text: String, value: float, p: CareerThemePalette) -> HBoxContainer:
	var line: HBoxContainer = CareerTheme.row(6)
	line.add_child(CareerTheme.cell(label_text, 100, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	line.add_child(CareerTheme.bar(clampf(value, 0.0, 1.0), 100))
	line.add_child(CareerTheme.label(
		"%d" % int(round(clampf(value, 0.0, 1.0) * 20.0)), p.text_secondary, p.font_size_small
	))
	return line
