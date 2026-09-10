##
## ContractNegotiationModal
##
## Interactive FM24-style contract negotiation haggle modal.
## Features:
##   - Agent patience meter (walkout limit).
##   - Live wage, contract length, squad status, signing bonus, and release clause haggling.
##   - Real-time agent counter-proposals and demand evaluation.
##   - Finalize & sign agreement flow.
##
## Depends on: CareerTheme, TransferMarket, ContractData, PlayerData, PlayerCareerState.
##

class_name ContractNegotiationModal
extends Control

signal negotiation_finished(success: bool, contract: ContractData)

var player_data: PlayerData = null
var player_state: PlayerCareerState = null
var selling_club: TeamData = null
var is_free_agent: bool = false
var transfer_offer: TransferOffer = null

var _attempts_made: int = 0
var _patience_max: int = 4
var _is_deal_agreed: bool = false
var _is_walkout: bool = false

# UI references
var _patience_label: Label = null
var _feedback_label: Label = null
var _demand_label: Label = null
var _wage_spin: SpinBox = null
var _years_option: OptionButton = null
var _status_option: OptionButton = null
var _bonus_spin: SpinBox = null
var _clause_spin: SpinBox = null
var _submit_btn: Button = null
var _sign_btn: Button = null

var _demanded_wage: int = 5000
var _demanded_years: int = 3
var _demanded_status: ContractData.Status = ContractData.Status.REGULAR_STARTER
var _demanded_bonus: int = 15000


static func open_modal(
	parent: Control,
	p_data: PlayerData,
	p_state: PlayerCareerState,
	p_selling_club: TeamData,
	p_is_free_agent: bool = false,
	p_offer: TransferOffer = null
) -> ContractNegotiationModal:
	var modal := ContractNegotiationModal.new()
	modal.player_data = p_data
	modal.player_state = p_state
	modal.selling_club = p_selling_club
	modal.is_free_agent = p_is_free_agent
	modal.transfer_offer = p_offer
	parent.add_child(modal)
	return modal


func _ready() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	_calc_initial_demands()
	_build_ui()


func _calc_initial_demands() -> void:
	var buying_team: TeamData = CareerManager.user_team()
	var today: CareerDate = CareerManager.career.today if CareerManager.career != null else null
	_demanded_wage = TransferMarket.wage_demand(player_data, player_state, buying_team, today)
	_demanded_years = 3
	_demanded_status = ContractData.Status.REGULAR_STARTER
	if player_data != null and player_data.calculate_overall_rating() >= 75:
		_demanded_status = ContractData.Status.STAR_PLAYER
	elif player_data != null and player_data.calculate_overall_rating() <= 62:
		_demanded_status = ContractData.Status.SQUAD_PLAYER
	_demanded_bonus = maxi(_demanded_wage * 3, 5000)


func _build_ui() -> void:
	var p: CareerThemePalette = CareerTheme.palette()

	# Scrim
	var scrim := ColorRect.new()
	scrim.color = Color(0.04, 0.06, 0.10, 0.85)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	# Center card
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card_panel: PanelContainer = PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(620, 540)
	card_panel.add_theme_stylebox_override("panel", CareerTheme.style_box(p.panel, 8, p.divider, 1))
	center.add_child(card_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	card_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	# Title & header
	var top := HBoxContainer.new()
	var pname: String = player_data.player_name if player_data != null else "Player"
	var pos: String = player_data.position_role if player_data != null else "MF"
	var club_name: String = "Free Agent" if is_free_agent else (selling_club.team_name if selling_club != null else "Club")

	var p_age: int = 24
	if player_data != null:
		if CareerManager.career != null and CareerManager.career.today != null:
			p_age = player_data.get_age(CareerManager.career.today.year, CareerManager.career.today.month, CareerManager.career.today.day)
		else:
			p_age = player_data.get_age()

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_child(CareerTheme.heading("Contract Negotiations: %s" % pname))
	title_col.add_child(CareerTheme.muted("%s | %s | Age %d | Stature: %s" % [
		club_name, pos, p_age,
		player_data.squad_status if player_data != null else "Regular"
	]))
	top.add_child(title_col)

	var close_btn: Button = CareerTheme.button("✕")
	close_btn.pressed.connect(_on_cancel)
	top.add_child(close_btn)
	box.add_child(top)

	# Patience bar
	_patience_label = CareerTheme.label(_get_patience_text(), p.positive, p.font_size_body)
	box.add_child(_patience_label)

	# Demands banner
	var demand_box: PanelContainer = PanelContainer.new()
	demand_box.add_theme_stylebox_override("panel", CareerTheme.style_box(p.header, 4))
	var d_margin := MarginContainer.new()
	d_margin.add_theme_constant_override("margin_left", 12)
	d_margin.add_theme_constant_override("margin_top", 8)
	d_margin.add_theme_constant_override("margin_right", 12)
	d_margin.add_theme_constant_override("margin_bottom", 8)
	demand_box.add_child(d_margin)

	_demand_label = CareerTheme.label(
		"Agent Demand: %s/wk | %d Years | %s | %s Signing Bonus" % [
			CareerTheme.money(_demanded_wage),
			_demanded_years,
			ContractData.STATUS_NAMES[clampi(int(_demanded_status), 0, ContractData.STATUS_NAMES.size() - 1)],
			CareerTheme.money(_demanded_bonus)
		],
		p.accent
	)
	d_margin.add_child(_demand_label)
	box.add_child(demand_box)

	# Negotiation form
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 16)
	form.add_theme_constant_override("v_separation", 10)
	box.add_child(form)

	# 1. Weekly wage
	form.add_child(CareerTheme.label("Weekly Wage:"))
	_wage_spin = SpinBox.new()
	_wage_spin.min_value = 500
	_wage_spin.max_value = 250000
	_wage_spin.step = 250
	_wage_spin.value = float(_demanded_wage)
	_wage_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_wage_spin)

	# 2. Contract length
	form.add_child(CareerTheme.label("Contract Duration:"))
	_years_option = OptionButton.new()
	for y: int in range(1, 6):
		_years_option.add_item("%d Year%s" % [y, "s" if y > 1 else ""], y)
	_years_option.select(clampi(_demanded_years, 1, 5) - 1)
	_years_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_years_option)

	# 3. Squad status
	form.add_child(CareerTheme.label("Promised Role:"))
	_status_option = OptionButton.new()
	for s_idx: int in range(ContractData.STATUS_NAMES.size()):
		_status_option.add_item(ContractData.STATUS_NAMES[s_idx], s_idx)
	_status_option.select(clampi(int(_demanded_status), 0, ContractData.STATUS_NAMES.size() - 1))
	_status_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_status_option)

	# 4. Signing bonus
	form.add_child(CareerTheme.label("Signing Bonus:"))
	_bonus_spin = SpinBox.new()
	_bonus_spin.min_value = 0
	_bonus_spin.max_value = 500000
	_bonus_spin.step = 2500
	_bonus_spin.value = float(_demanded_bonus)
	_bonus_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_bonus_spin)

	# 5. Release clause
	form.add_child(CareerTheme.label("Release Clause (0 = None):"))
	_clause_spin = SpinBox.new()
	_clause_spin.min_value = 0
	_clause_spin.max_value = 100000000
	_clause_spin.step = 500000
	_clause_spin.value = 0
	_clause_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_clause_spin)

	# Feedback speech bubble
	_feedback_label = CareerTheme.paragraph("The player's representative awaits your contract proposal.")
	_feedback_label.custom_minimum_size = Vector2(0, 42)
	box.add_child(_feedback_label)

	# Actions
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)

	var cancel_btn: Button = CareerTheme.button("Walk Away")
	cancel_btn.pressed.connect(_on_cancel)
	actions.add_child(cancel_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)

	_submit_btn = CareerTheme.button("Submit Proposal", true)
	_submit_btn.pressed.connect(_on_submit_proposal)
	actions.add_child(_submit_btn)

	_sign_btn = CareerTheme.button("Finalize & Sign Deal", true)
	_sign_btn.visible = false
	_sign_btn.pressed.connect(_on_finalize_deal)
	actions.add_child(_sign_btn)

	box.add_child(actions)


func _get_patience_text() -> String:
	var left: int = maxi(_patience_max - _attempts_made, 0)
	var dots: String = ""
	for i: int in range(left):
		dots += "● "
	for i: int in range(_patience_max - left):
		dots += "○ "
	return "Agent Patience: %s (%d round%s remaining)" % [dots.strip_edges(), left, "s" if left != 1 else ""]


func _on_submit_proposal() -> void:
	if _is_walkout or _is_deal_agreed:
		return

	_attempts_made += 1
	var offered_wage: int = int(_wage_spin.value)
	var offered_years: int = _years_option.get_selected_id()
	var offered_status: ContractData.Status = _status_option.get_selected_id() as ContractData.Status
	var offered_bonus: int = int(_bonus_spin.value)
	var offered_clause: int = int(_clause_spin.value)

	var user_club: TeamData = CareerManager.user_team()
	var today: CareerDate = CareerManager.career.today if CareerManager.career != null else null

	var result: Dictionary = TransferMarket.evaluate_contract_proposal(
		player_data, player_state, user_club,
		offered_wage, offered_years, offered_status,
		offered_bonus, offered_clause, today, _attempts_made
	)

	var outcome: String = str(result.get("outcome", "walkout"))
	var msg: String = str(result.get("message", ""))
	var p: CareerThemePalette = CareerTheme.palette()

	_patience_label.text = _get_patience_text()
	if _attempts_made >= 3:
		_patience_label.add_theme_color_override("font_color", p.danger)
	elif _attempts_made >= 2:
		_patience_label.add_theme_color_override("font_color", p.warning)

	if outcome == "accepted":
		_is_deal_agreed = true
		_feedback_label.text = msg
		_feedback_label.add_theme_color_override("font_color", p.positive)
		_submit_btn.visible = false
		_sign_btn.visible = true
	elif outcome == "counter":
		_demanded_wage = int(result.get("demanded_wage", _demanded_wage))
		_demanded_years = int(result.get("demanded_years", _demanded_years))
		_demanded_bonus = int(result.get("demanded_bonus", _demanded_bonus))
		_demanded_status = clampi(int(result.get("demanded_status", _demanded_status)), 0, ContractData.STATUS_NAMES.size() - 1) as ContractData.Status

		_demand_label.text = "Counter Demand: %s/wk | %d Years | %s | %s Signing Bonus" % [
			CareerTheme.money(_demanded_wage),
			_demanded_years,
			ContractData.STATUS_NAMES[int(_demanded_status)],
			CareerTheme.money(_demanded_bonus)
		]
		_feedback_label.text = msg
		_feedback_label.add_theme_color_override("font_color", p.warning)

		# Sync inputs to counter proposal to allow easy acceptance:
		_wage_spin.value = float(_demanded_wage)
		_bonus_spin.value = float(_demanded_bonus)
		_years_option.select(clampi(_demanded_years, 1, 5) - 1)
		_status_option.select(clampi(int(_demanded_status), 0, ContractData.STATUS_NAMES.size() - 1))
	else:
		_is_walkout = true
		_feedback_label.text = msg
		_feedback_label.add_theme_color_override("font_color", p.danger)
		_submit_btn.disabled = true


func _on_finalize_deal() -> void:
	if not _is_deal_agreed:
		return

	var agreed_wage: int = int(_wage_spin.value)
	var agreed_years: int = _years_option.get_selected_id()
	var agreed_status: ContractData.Status = _status_option.get_selected_id() as ContractData.Status
	var agreed_bonus: int = int(_bonus_spin.value)
	var agreed_clause: int = int(_clause_spin.value)

	var club_name: String = CareerManager.user_team().team_name if CareerManager.user_team() != null else ""
	var today: CareerDate = CareerManager.career.today if CareerManager.career != null else null

	var contract := ContractData.make_default(club_name, agreed_wage, agreed_years, today)
	contract.promised_status = agreed_status
	contract.signing_bonus = agreed_bonus
	contract.release_clause = agreed_clause

	if is_free_agent:
		CareerManager.sign_free_agent(player_data, contract)
	elif transfer_offer != null:
		transfer_offer.wage_offered = agreed_wage
		transfer_offer.contract_years_offered = agreed_years
		transfer_offer.promised_status = agreed_status
		transfer_offer.signing_bonus_offered = agreed_bonus
		transfer_offer.release_clause_offered = agreed_clause
		transfer_offer.advance_to(TransferOffer.State.COMPLETED, today, "Personal terms agreed.")
		CareerManager._execute_transfer(transfer_offer)
	elif player_state != null:
		player_state.contract = contract
		player_state.wants_new_contract = false
		player_state.manager_trust = clampf(player_state.manager_trust + 0.20, 0.0, 1.0)
		if player_data != null:
			player_data.wage_weekly = agreed_wage
			player_data.contract_years = agreed_years
			player_data.morale = clampf(player_data.morale + 0.20, 0.0, 1.0)

	negotiation_finished.emit(true, contract)
	queue_free()


func _on_cancel() -> void:
	negotiation_finished.emit(false, null)
	queue_free()
