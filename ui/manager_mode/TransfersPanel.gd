##
## TransfersPanel
##
## Transfer search, the shortlist, live negotiations, and the bid flow.
##
## Search results show what the club KNOWS, not the truth: a player with no
## scouting shows a wide band and a "?" overall. That is the whole point of the
## scouting layer, so the transfer screen must not leak exact values.
##
## Depends on: CareerPanel, CareerTheme, TransferMarket, ScoutReport,
##             TransferOffer, CareerManager.
##

class_name TransfersPanel
extends CareerPanel

enum View { SEARCH = 0, SHORTLIST = 1, NEGOTIATIONS = 2 }

const VIEW_LABELS: Array[String] = ["Search", "Shortlist", "Negotiations"]
const POSITION_FILTERS: Array[String] = ["All", "GK", "DEF", "MID", "ATT"]

var _view: View = View.SEARCH
var _position_filter: int = 0
var _max_age: int = 40
var _selected_key: int = -1


func title() -> String:
	return "Transfers"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var team: TeamData = club(career)
	var finances: ClubFinances = career.user_finances()
	if team == null:
		empty_state(host, "No club loaded.")
		return

	var status: HBoxContainer = CareerTheme.row(16)
	host.add_child(status)
	status.add_child(CareerTheme.label(
		"Window OPEN" if career.transfer_window_open else "Window CLOSED",
		p.positive if career.transfer_window_open else p.danger
	))
	if finances != null:
		status.add_child(CareerTheme.secondary("Budget %s" % CareerTheme.money(finances.transfer_budget)))
		status.add_child(CareerTheme.secondary(
			"Wage room %s/wk" % CareerTheme.money(maxi(
				finances.wage_budget_weekly - team.get_weekly_payroll(), 0
			))
		))

	var tabs: HBoxContainer = CareerTheme.row(4)
	host.add_child(tabs)
	for i: int in range(VIEW_LABELS.size()):
		var view: View = i as View
		var b: Button = CareerTheme.button(VIEW_LABELS[i], view == _view)
		b.pressed.connect(func() -> void:
			_view = view
			refresh()
		)
		tabs.add_child(b)

	match _view:
		View.SEARCH:
			_build_search(host, career, team, finances, p)
		View.SHORTLIST:
			_build_shortlist(host, career, p)
		_:
			_build_negotiations(host, career, p)


func _build_search(
	host: VBoxContainer,
	career: CareerSaveData,
	team: TeamData,
	finances: ClubFinances,
	p: CareerThemePalette
) -> void:
	var filters: HBoxContainer = CareerTheme.row(6)
	host.add_child(filters)
	filters.add_child(CareerTheme.cell("Position", 60, p.text_muted))
	for i: int in range(POSITION_FILTERS.size()):
		var b: Button = CareerTheme.button(POSITION_FILTERS[i], i == _position_filter)
		b.pressed.connect(func() -> void:
			_position_filter = i
			refresh()
		)
		filters.add_child(b)
	var age_button: Button = CareerTheme.button("Max age: %s" % ("Any" if _max_age >= 40 else str(_max_age)))
	age_button.pressed.connect(func() -> void:
		_max_age = 21 if _max_age >= 40 else (_max_age + 4 if _max_age < 33 else 40)
		refresh()
	)
	filters.add_child(age_button)

	var body: VBoxContainer = CareerTheme.card("Available Players")
	host.add_child(CareerTheme.card_root(body))

	var header: HBoxContainer = CareerTheme.header_row()
	body.add_child(CareerTheme.data_row_root(header))
	header.add_child(CareerTheme.cell("Player", 150, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Club", 140, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Pos", 44, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Age", 36, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Ability", 70, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Potential", 70, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Asking", 76, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("Wage", 70, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("Scouted", 70, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))

	if DataLoader.league == null:
		return

	var shown: int = 0
	for team_index: int in range(DataLoader.league.teams.size()):
		if team_index == career.user_team_index:
			continue
		var other: TeamData = DataLoader.league.teams[team_index]
		for squad_index: int in range(other.squad.size()):
			if shown >= 60:
				break
			var data: PlayerData = other.squad[squad_index]
			var age: int = data.get_age(career.today.year, career.today.month, career.today.day)
			if age > _max_age:
				continue
			if _position_filter > 0:
				var family: String = TransferMarket.position_family(data.position_role)
				if POSITION_FILTERS[_position_filter] != family:
					continue

			var key: int = team_index * 1000 + squad_index
			var state: PlayerCareerState = career.state_for(key)
			var report: ScoutReport = career.report_for(key)
			host_row(body, career, other, data, state, report, team_index, squad_index, shown, finances, p)
			shown += 1

	if shown == 0:
		body.add_child(CareerTheme.muted("No players match these filters."))


func host_row(
	body: VBoxContainer,
	career: CareerSaveData,
	other: TeamData,
	data: PlayerData,
	state: PlayerCareerState,
	report: ScoutReport,
	team_index: int,
	squad_index: int,
	display_index: int,
	finances: ClubFinances,
	p: CareerThemePalette
) -> void:
	var key: int = team_index * 1000 + squad_index
	var selected: bool = key == _selected_key
	var line: HBoxContainer = CareerTheme.data_row(display_index, selected)
	var age: int = data.get_age(career.today.year, career.today.month, career.today.day)

	var name_button: Button = CareerTheme.button(data.player_name)
	name_button.custom_minimum_size = Vector2(150.0, 0.0)
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.pressed.connect(func() -> void:
		_selected_key = -1 if selected else key
		refresh()
	)
	line.add_child(name_button)

	line.add_child(CareerTheme.cell(other.team_name, 140, p.text_secondary))
	line.add_child(CareerTheme.cell(data.position_role, 44, p.text_secondary))
	line.add_child(CareerTheme.cell(str(age), 36, p.text_secondary))

	# Unscouted players show a "?" — the club genuinely does not know.
	if report != null:
		line.add_child(CareerTheme.cell(report.display_value(), 70, p.text_primary))
		line.add_child(CareerTheme.cell(report.display_potential(), 70, p.text_secondary))
	else:
		line.add_child(CareerTheme.cell("?", 70, p.text_muted))
		line.add_child(CareerTheme.cell("?", 70, p.text_muted))

	var ask: int = TransferMarket.asking_price(data, state, other, career.today)
	var affordable: bool = finances != null and finances.can_afford_fee(ask)
	line.add_child(CareerTheme.cell(
		CareerTheme.money(ask), 76, p.text_primary if affordable else p.danger,
		HORIZONTAL_ALIGNMENT_RIGHT
	))
	line.add_child(CareerTheme.cell(
		"%s/wk" % CareerTheme.money(TransferMarket.wage_demand(data, state, club(career), career.today)),
		70, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
	))
	line.add_child(CareerTheme.cell(
		"%d%%" % int((report.knowledge if report != null else 0.0) * 100.0), 70,
		p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
	))
	body.add_child(CareerTheme.data_row_root(line))

	if selected:
		body.add_child(CareerTheme.card_root(
			_target_actions(career, other, data, state, report, team_index, squad_index, ask, p)
		))


func _target_actions(
	career: CareerSaveData,
	other: TeamData,
	data: PlayerData,
	state: PlayerCareerState,
	report: ScoutReport,
	team_index: int,
	squad_index: int,
	ask: int,
	p: CareerThemePalette
) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card(data.player_name)
	if report != null and report.verdict != "":
		body.add_child(CareerTheme.paragraph(report.verdict))
	else:
		body.add_child(CareerTheme.muted(
			"This player has not been scouted. Bidding blind means negotiating without knowing what he is worth."
		))

	var key: int = team_index * 1000 + squad_index
	var actions: HBoxContainer = CareerTheme.row()
	body.add_child(actions)

	var shortlisted: bool = career.shortlist_contains(key)
	var shortlist_button: Button = CareerTheme.button(
		"Remove from shortlist" if shortlisted else "Add to shortlist"
	)
	shortlist_button.pressed.connect(func() -> void:
		CareerManager.toggle_shortlist(key)
		refresh()
	)
	actions.add_child(shortlist_button)

	var scout_button: Button = CareerTheme.button("Scout this player")
	scout_button.disabled = report != null and report.assigned_scout_name != ""
	scout_button.pressed.connect(func() -> void:
		CareerManager.scout_player(team_index, squad_index)
		refresh()
	)
	actions.add_child(scout_button)

	var bid_button: Button = CareerTheme.button("Bid %s" % CareerTheme.money(ask), true)
	bid_button.disabled = not career.transfer_window_open
	bid_button.pressed.connect(func() -> void:
		CareerManager.submit_transfer_bid(team_index, squad_index, ask)
		_view = View.NEGOTIATIONS
		refresh()
	)
	actions.add_child(bid_button)

	if not career.transfer_window_open:
		body.add_child(CareerTheme.label("The transfer window is closed.", p.warning))
	return body


func _build_shortlist(host: VBoxContainer, career: CareerSaveData, p: CareerThemePalette) -> void:
	var body: VBoxContainer = CareerTheme.card("Shortlist")
	host.add_child(CareerTheme.card_root(body))
	if career.shortlist_keys.is_empty():
		body.add_child(CareerTheme.muted("Nobody shortlisted yet."))
		return

	for i: int in range(career.shortlist_keys.size()):
		var key: int = career.shortlist_keys[i]
		var team_index: int = key / 1000
		var squad_index: int = key % 1000
		var other: TeamData = DataLoader.get_team(team_index)
		if other == null or squad_index >= other.squad.size():
			continue
		var data: PlayerData = other.squad[squad_index]
		var state: PlayerCareerState = career.state_for(key)
		var report: ScoutReport = career.report_for(key)
		var line: HBoxContainer = CareerTheme.data_row(i)
		line.add_child(CareerTheme.cell(data.player_name, 160, p.text_primary))
		line.add_child(CareerTheme.cell(other.team_name, 140, p.text_secondary))
		line.add_child(CareerTheme.cell(data.position_role, 44, p.text_secondary))
		line.add_child(CareerTheme.cell(
			report.display_value() if report != null else "?", 70, p.text_secondary
		))
		line.add_child(CareerTheme.cell(
			report.stage_name() if report != null else "Identified", 90,
			p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
		))
		line.add_child(CareerTheme.cell(
			CareerTheme.money(TransferMarket.asking_price(data, state, other, career.today)),
			80, p.text_primary, HORIZONTAL_ALIGNMENT_RIGHT
		))
		var remove: Button = CareerTheme.button("Remove")
		remove.pressed.connect(func() -> void:
			CareerManager.toggle_shortlist(key)
			refresh()
		)
		line.add_child(remove)
		body.add_child(CareerTheme.data_row_root(line))


func _build_negotiations(host: VBoxContainer, career: CareerSaveData, p: CareerThemePalette) -> void:
	var body: VBoxContainer = CareerTheme.card("Active Negotiations")
	host.add_child(CareerTheme.card_root(body))
	if career.active_offers.is_empty():
		body.add_child(CareerTheme.muted("No negotiations in progress."))
		return

	for i: int in range(career.active_offers.size()):
		var offer: TransferOffer = career.active_offers[i]
		var line: VBoxContainer = VBoxContainer.new()
		line.add_theme_constant_override("separation", 3)

		var top: HBoxContainer = CareerTheme.row()
		top.add_child(CareerTheme.cell(offer.player_name, 160, p.text_primary))
		top.add_child(CareerTheme.cell(offer.selling_club, 140, p.text_secondary))
		var state_tint: Color = p.text_secondary
		if offer.state == TransferOffer.State.COMPLETED:
			state_tint = p.positive
		elif offer.state == TransferOffer.State.CLUB_REJECTED or offer.state == TransferOffer.State.TERMS_REJECTED:
			state_tint = p.danger
		elif offer.is_awaiting_user():
			state_tint = p.warning
		top.add_child(CareerTheme.cell(offer.state_name(), 120, state_tint))
		top.add_child(CareerTheme.cell(
			CareerTheme.money(offer.fee_offered), 80, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
		))
		line.add_child(top)

		if offer.response_message != "":
			line.add_child(CareerTheme.paragraph(offer.response_message))

		var actions: HBoxContainer = CareerTheme.row()
		if offer.state == TransferOffer.State.CLUB_COUNTERED:
			var accept: Button = CareerTheme.button(
				"Meet their valuation (%s)" % CareerTheme.money(offer.fee_demanded), true
			)
			accept.pressed.connect(func() -> void:
				CareerManager.raise_transfer_bid(offer, offer.fee_demanded)
				refresh()
			)
			actions.add_child(accept)
		elif offer.state == TransferOffer.State.CLUB_ACCEPTED:
			var terms: Button = CareerTheme.button("Open personal terms", true)
			terms.pressed.connect(func() -> void:
				CareerManager.offer_personal_terms(offer)
				refresh()
			)
			actions.add_child(terms)
		elif offer.state == TransferOffer.State.TERMS_COUNTERED:
			var meet: Button = CareerTheme.button(
				"Meet his demands (%s/wk)" % CareerTheme.money(offer.wage_demanded), true
			)
			meet.pressed.connect(func() -> void:
				CareerManager.offer_personal_terms(offer, offer.wage_demanded)
				refresh()
			)
			actions.add_child(meet)

		if not offer.is_terminal():
			var withdraw: Button = CareerTheme.button("Withdraw")
			withdraw.pressed.connect(func() -> void:
				CareerManager.withdraw_offer(offer)
				refresh()
			)
			actions.add_child(withdraw)
		if actions.get_child_count() > 0:
			line.add_child(actions)

		body.add_child(line)
		body.add_child(CareerTheme.divider())
