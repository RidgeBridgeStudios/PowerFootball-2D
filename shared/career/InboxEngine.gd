##
## InboxEngine
##
## Builds the manager's inbox and applies the consequences of answering it.
##
## Every meaningful thing the career layer does produces an inbox item, and
## every item with options is a real decision with real deltas — morale, trust,
## board confidence, press standing. resolve() is the ONLY place those deltas
## are applied, so an option can be previewed in the UI before it is chosen and
## the effects cannot drift apart from the description shown to the player.
##
## Ignoring a decision is itself a choice: expire() applies the item's
## escalation branch, which is always worse than any answer available.
##
## Depends on: InboxItem, WorldEvent, CareerSaveData, PlayerData,
##             PlayerCareerState, ManagerCareerProfile, BoardState, TeamData,
##             CareerDate, PressOffice, ManagerData.
## Exposes: build_* generators, resolve(), expire_overdue(), sorted_inbox().
##

class_name InboxEngine
extends RefCounted

## Default window a decision stays open before escalating.
const DEFAULT_DEADLINE_DAYS: int = 7


## --- Generators -----------------------------------------------------------------

## Welcome message when a career starts or a new job is taken.
static func build_job_welcome(
	club: TeamData,
	board: BoardState,
	profile: ManagerCareerProfile,
	today: CareerDate
) -> InboxItem:
	var body: String = "Welcome to %s.\n\nThe board's expectation for the season is: %s.\n\nYou have a transfer budget of %s and a wage budget of %s per week. We look forward to working with you." % [
		club.team_name,
		board.expectation_label(),
		TransferMarket.format_fee(club.transfer_budget),
		TransferMarket.format_fee(club.wage_budget_weekly),
	]
	var item: InboxItem = InboxItem.make(
		"Welcome to %s" % club.team_name, body, InboxItem.Category.BOARD, today
	)
	item.priority = 0.9
	return item


## Pre-match press conference. Options trade squad morale against press
## standing and board confidence — there is no free answer.
static func build_press_conference(
	opponent_name: String,
	is_big_game: bool,
	today: CareerDate
) -> InboxItem:
	var body: String = "The press want a word before we face %s. What line are you taking?" % opponent_name
	if is_big_game:
		body += "\n\nThe room is busier than usual — this one matters."
	var item: InboxItem = InboxItem.make(
		"Press Conference: %s" % opponent_name, body, InboxItem.Category.MEDIA, today
	)
	item.priority = 0.55
	item.add_option(
		"Back the players publicly",
		"Squad morale up. The board expect you to deliver on it.",
		&"press_back_players", 0.035, 0.0, -0.01, 0.02
	)
	item.add_option(
		"Play down expectations",
		"Takes pressure off the squad, but reads as defeatism upstairs.",
		&"press_downplay", 0.010, 0.0, -0.03, 0.01
	)
	item.add_option(
		"Talk up your own side's quality",
		"Press like the confidence. The squad have to live up to it.",
		&"press_confident", -0.010, 0.0, 0.02, 0.04
	)
	item.add_option(
		"Refuse to be drawn",
		"Nothing gained, nothing lost. The press find it dull.",
		&"press_deflect", 0.0, 0.0, 0.0, -0.02
	)
	item.with_deadline(today.advanced_by(2), 3)
	return item


## A player unhappy about playing time asks for a meeting.
static func build_playing_time_complaint(
	data: PlayerData,
	state: PlayerCareerState,
	today: CareerDate
) -> InboxItem:
	var promised: String = state.contract.status_name() if state.contract != null else "Regular Starter"
	var body: String = "%s has asked to speak with you.\n\n\"I was told I'd be a %s here. I'm not playing anywhere near enough, and I want to know where I stand.\"" % [
		data.player_name, promised.to_lower()
	]
	var item: InboxItem = InboxItem.make(
		"%s wants to discuss his role" % data.player_name,
		body, InboxItem.Category.PLAYER, today
	)
	item.with_subject_player(state.player_key, data.player_name)
	item.priority = 0.75
	item.add_option(
		"Promise more game time",
		"He settles down — but you have committed to playing him.",
		&"promise_playing_time", 0.0, 0.22, 0.0, 0.0
	)
	item.add_option(
		"Tell him to earn his place in training",
		"Honest. A determined player responds; a fragile one sulks.",
		&"challenge_player", 0.0, -0.05, 0.01, 0.0
	)
	item.add_option(
		"Agree he can look for a move",
		"He is transfer-listed and stops agitating.",
		&"agree_to_sale", -0.02, 0.05, 0.0, 0.0
	)
	item.add_option(
		"Dismiss the complaint",
		"He is furious, and the dressing room notices.",
		&"dismiss_player", -0.03, -0.20, 0.0, 0.0
	)
	# Escalation (index 3) is the dismissal — ignoring him reads as contempt.
	item.with_deadline(today.advanced_by(DEFAULT_DEADLINE_DAYS), 3)
	return item


## A player at a club whose contract is running down.
static func build_contract_expiry_warning(
	data: PlayerData,
	state: PlayerCareerState,
	today: CareerDate
) -> InboxItem:
	var days: int = state.contract.days_remaining(today) if state.contract != null else 0
	var body: String = "%s has %d days left on his contract.\n\nIf we do not agree new terms he will be free to negotiate with other clubs, and we will lose him for nothing." % [
		data.player_name, days
	]
	var item: InboxItem = InboxItem.make(
		"Contract expiring: %s" % data.player_name,
		body, InboxItem.Category.CONTRACT, today
	)
	item.with_subject_player(state.player_key, data.player_name)
	item.priority = 0.8
	item.add_option(
		"Open contract talks",
		"Offer improved terms. Costs wage budget.",
		&"open_contract_talks", 0.0, 0.10, 0.0, 0.0
	)
	item.add_option(
		"Let the contract run down",
		"Saves money now. He will likely leave for free.",
		&"let_contract_expire", -0.015, -0.12, -0.02, 0.0
	)
	item.add_option(
		"List him for transfer",
		"Recoup something while he still has value.",
		&"list_for_transfer", -0.01, -0.08, 0.01, 0.0
	)
	item.with_deadline(today.advanced_by(14), 1)
	return item


## Board reaction to a run of results.
static func build_board_warning(
	board: BoardState,
	club_name: String,
	position: int,
	today: CareerDate
) -> InboxItem:
	var body: String = "The board have reviewed our position.\n\nWe sit %s in the table against an expectation to %s. Results must improve.\n\nBoard confidence: %s." % [
		_ordinal(position), board.expectation_label().to_lower(), board.confidence_label()
	]
	var item: InboxItem = InboxItem.make(
		"Board concerns over results", body, InboxItem.Category.BOARD, today
	)
	item.priority = 0.95
	item.add_option(
		"Accept responsibility",
		"The board respect the honesty. No change to the squad.",
		&"board_accept", 0.0, 0.0, 0.03, -0.01
	)
	item.add_option(
		"Point to injuries and fixtures",
		"Buys a little patience if it is actually true.",
		&"board_deflect", 0.0, 0.0, 0.01, 0.0
	)
	item.add_option(
		"Demand backing in the transfer market",
		"Bold. Works if they rate you, backfires badly if not.",
		&"board_demand", 0.0, 0.0, -0.04, 0.03
	)
	item.with_deadline(today.advanced_by(5), 1)
	return item


static func build_injury_notice(
	data: PlayerData,
	state: PlayerCareerState,
	today: CareerDate
) -> InboxItem:
	var body: String = "The physio has assessed %s.\n\nDiagnosis: %s. Expected to be unavailable for approximately %d days, returning around %s." % [
		data.player_name,
		state.injury_name(),
		state.injury_days_remaining,
		state.injury_return_date.to_display() if state.injury_return_date != null else "unknown",
	]
	var item: InboxItem = InboxItem.make(
		"Injury: %s" % data.player_name, body, InboxItem.Category.PLAYER, today
	)
	item.with_subject_player(state.player_key, data.player_name)
	item.priority = 0.7 if state.injury_days_remaining > 21 else 0.45
	return item


static func build_transfer_response(offer: TransferOffer, today: CareerDate) -> InboxItem:
	var item: InboxItem = InboxItem.make(
		"%s: %s" % [offer.player_name, offer.state_name()],
		offer.response_message, InboxItem.Category.TRANSFER, today
	)
	item.priority = 0.85 if offer.is_awaiting_user() else 0.5
	item.payload = {
		"offer_player_key": offer.player_key(),
		"offer_state": int(offer.state),
	}
	return item


static func build_scout_report_ready(report: ScoutReport, today: CareerDate) -> InboxItem:
	var body: String = "%s\n\nCurrent ability: %s\nPotential: %s\nClub: %s\nPosition: %s" % [
		report.verdict,
		report.display_value(),
		report.display_potential(),
		report.target_club,
		report.target_position,
	]
	var item: InboxItem = InboxItem.make(
		"Scout report: %s" % report.target_name, body, InboxItem.Category.SCOUTING, today
	)
	item.priority = 0.5
	item.payload = {"report_key": report.target_key()}
	return item


## A StreetBaller (128) player has been caught out past curfew. One of three
## FIFA-Manager-style off-pitch dilemmas: come down hard, a proportionate
## private word, or let it go — each trades subject trust for squad-wide
## discipline optics differently, same pattern as build_playing_time_complaint.
static func build_nightlife_incident(
	data: PlayerData,
	state: PlayerCareerState,
	today: CareerDate
) -> InboxItem:
	var body: String = "%s was photographed out at a nightclub in the early hours, two days before a matchday.\n\nIt is already doing the rounds on social media. The squad are watching how you handle it." % data.player_name
	var item: InboxItem = InboxItem.make(
		"Nightlife incident: %s" % data.player_name,
		body, InboxItem.Category.PLAYER, today
	)
	item.with_subject_player(state.player_key, data.player_name)
	item.priority = 0.6
	# Distinguishes this from build_playing_time_complaint on reload — both
	# use Category.PLAYER, and CareerManager._rehydrate_inbox() needs to tell
	# them apart to rebuild the right options for an item still awaiting a
	# decision after a save/load.
	item.payload = {"kind": "nightlife"}
	item.add_option(
		"Fine him and drop him for the next match",
		"Sends a message to the whole squad. He will not thank you for it.",
		&"nightlife_fine", 0.015, -0.14, 0.02, 0.01
	)
	item.add_option(
		"A private word, no further action",
		"Proportionate. He respects that you did not make a show of it.",
		&"nightlife_private_word", 0.0, 0.02, 0.0, 0.0
	)
	item.add_option(
		"Let it go publicly",
		"Costs you no relationship — but the dressing room notices there was no consequence.",
		&"nightlife_ignore", -0.02, 0.05, -0.02, -0.01
	)
	# Escalation (index 0) — ignoring a story already in the press is read as
	# tacit approval and costs the most.
	item.with_deadline(today.advanced_by(3), 0)
	return item


static func build_youth_intake(club_name: String, summary: String, today: CareerDate) -> InboxItem:
	var item: InboxItem = InboxItem.make(
		"Youth intake: %s" % club_name, summary, InboxItem.Category.YOUTH, today
	)
	item.priority = 0.7
	return item


static func build_simple(
	subject: String,
	body: String,
	category: InboxItem.Category,
	priority: float,
	today: CareerDate
) -> InboxItem:
	var item: InboxItem = InboxItem.make(subject, body, category, today)
	item.priority = clampf(priority, 0.0, 1.0)
	return item


## --- Resolution -------------------------------------------------------------------

## Applies one chosen option. Returns a WorldEvent describing what happened, or
## null when the item was a plain notification.
##
## This is the single choke point for inbox consequences — nothing else in the
## career layer applies an inbox option's deltas.
static func resolve(
	career: CareerSaveData,
	item: InboxItem,
	option_index: int,
	club: TeamData,
	today: CareerDate
) -> WorldEvent:
	if item == null or item.is_resolved:
		return null
	var option: InboxItem.Option = item.get_option(option_index)
	if option == null:
		item.is_read = true
		return null

	item.is_resolved = true
	item.is_read = true
	item.chosen_option = option_index

	var ordinal: int = today.to_ordinal() if today != null else 0

	# 1. Squad-wide morale.
	if option.squad_morale_delta != 0.0 and club != null:
		for p: PlayerData in club.squad:
			p.morale = clampf(p.morale + option.squad_morale_delta, 0.0, 1.0)

	# 2. The subject player specifically.
	var subject_data: PlayerData = null
	var subject_state: PlayerCareerState = career.state_for(item.subject_player_key)
	if subject_state != null and club != null \
			and subject_state.squad_index >= 0 and subject_state.squad_index < club.squad.size():
		subject_data = club.squad[subject_state.squad_index]

	if subject_data != null and option.subject_morale_delta != 0.0:
		subject_data.morale = clampf(subject_data.morale + option.subject_morale_delta, 0.0, 1.0)
	if subject_state != null and option.subject_trust_delta != 0.0:
		subject_state.manager_trust = clampf(
			subject_state.manager_trust + option.subject_trust_delta, 0.0, 1.0
		)

	# 3. Board and press.
	if career.board != null and option.board_confidence_delta != 0.0:
		career.board.confidence = clampf(
			career.board.confidence + option.board_confidence_delta, 0.0, 1.0
		)
	if career.profile != null:
		if option.press_standing_delta != 0.0:
			career.profile.press_standing = clampf(
				career.profile.press_standing + option.press_standing_delta, 0.0, 1.0
			)
		if option.manager_reputation_delta != 0.0:
			career.profile.reputation = clampf(
				career.profile.reputation + option.manager_reputation_delta, 0.05, 0.99
			)

	# 4. Structural effects that are more than a number.
	_apply_action_tag(career, option.action_tag, subject_data, subject_state, today, ordinal)

	# 5. Log it.
	var narrative: String = option.narrative
	if narrative == "":
		narrative = "%s — chose \"%s\"." % [item.subject, option.label]
	var event: WorldEvent = WorldEvent.make(
		option.action_tag if option.action_tag != &"" else &"inbox_decision",
		_category_to_event_category(item.category),
		today,
		narrative,
		option.squad_morale_delta + option.subject_morale_delta,
		item.priority
	)
	event.resolved = true
	event.resolution_choice = option_index
	if subject_state != null:
		event.with_player(subject_state.player_key, item.subject_player_name)
	if club != null:
		event.with_club(club.team_name)
	return event


static func _apply_action_tag(
	career: CareerSaveData,
	tag: StringName,
	subject_data: PlayerData,
	subject_state: PlayerCareerState,
	today: CareerDate,
	ordinal: int
) -> void:
	match tag:
		&"promise_playing_time":
			if subject_state != null:
				# A promise is a commitment with a review date. If minutes have
				# not materialised by then, the fallout is worse than the
				# original complaint — see CareerManager._review_promises().
				subject_state.promised_status = int(ContractData.Status.REGULAR_STARTER)
				subject_state.promise_review_date = today.advanced_by(42)
				subject_state.grievances.erase(&"playing_time")
				subject_state.manager_trust = clampf(subject_state.manager_trust + 0.10, 0.0, 1.0)
		&"challenge_player":
			if subject_state != null and subject_data != null:
				# Determined players respond to a challenge; fragile ones fold.
				var swing: float = (subject_data.determination - 0.5) * 0.30
				subject_data.morale = clampf(subject_data.morale + swing, 0.0, 1.0)
				subject_state.manager_trust = clampf(
					subject_state.manager_trust + swing * 0.5, 0.0, 1.0
				)
		&"agree_to_sale", &"list_for_transfer":
			if subject_state != null:
				subject_state.transfer_listed = true
				subject_state.grievances.erase(&"playing_time")
		&"dismiss_player":
			if subject_state != null:
				subject_state.manager_trust = clampf(subject_state.manager_trust - 0.22, 0.0, 1.0)
				if not subject_state.grievances.has(&"playing_time"):
					subject_state.grievances.append(&"playing_time")
		&"open_contract_talks":
			if subject_state != null:
				subject_state.wants_new_contract = true
		&"let_contract_expire":
			if subject_state != null:
				subject_state.wants_new_contract = false
				subject_state.manager_trust = clampf(subject_state.manager_trust - 0.12, 0.0, 1.0)
		&"board_demand":
			# A demand that lands gets money; one that does not costs standing.
			if career.board != null and career.board.confidence >= 0.55:
				var fin: ClubFinances = career.user_finances()
				if fin != null:
					fin.transfer_budget += int(round(float(fin.transfer_budget) * 0.20)) + 500000
		&"press_back_players":
			# Backing the squad publicly is remembered by every player in it.
			for key: int in career.player_states:
				var st: PlayerCareerState = career.player_states[key] as PlayerCareerState
				if st != null and st.team_index == career.user_team_index:
					st.manager_trust = clampf(st.manager_trust + 0.02, 0.0, 1.0)
					st.relationship_with(-1, ordinal)
		_:
			pass


## Applies the escalation branch of anything left unanswered past its deadline.
## Returns the events generated.
static func expire_overdue(
	career: CareerSaveData,
	club: TeamData,
	today: CareerDate
) -> Array[WorldEvent]:
	var events: Array[WorldEvent] = []
	for item: InboxItem in career.inbox:
		if item.is_resolved or not item.requires_decision():
			continue
		if not item.is_expired(today):
			continue
		if item.escalation_option < 0 or item.escalation_option >= item.option_count():
			item.is_resolved = true
			continue
		var event: WorldEvent = resolve(career, item, item.escalation_option, club, today)
		if event != null:
			event.narrative_context = "%s — ignored, and it was taken badly." % item.subject
			events.append(event)
	return events


## Inbox ordering: unresolved decisions first, then by priority, then newest.
static func sorted_inbox(career: CareerSaveData) -> Array[InboxItem]:
	var items: Array[InboxItem] = career.inbox.duplicate()
	items.sort_custom(func(a: InboxItem, b: InboxItem) -> bool:
		var a_decision: bool = a.requires_decision()
		var b_decision: bool = b.requires_decision()
		if a_decision != b_decision:
			return a_decision
		if not is_equal_approx(a.priority, b.priority):
			return a.priority > b.priority
		var a_ord: int = a.received.to_ordinal() if a.received != null else 0
		var b_ord: int = b.received.to_ordinal() if b.received != null else 0
		return a_ord > b_ord
	)
	return items


static func _category_to_event_category(c: InboxItem.Category) -> WorldEvent.Category:
	match c:
		InboxItem.Category.BOARD:
			return WorldEvent.Category.BOARD
		InboxItem.Category.MEDIA:
			return WorldEvent.Category.MEDIA
		InboxItem.Category.PLAYER:
			return WorldEvent.Category.DRESSING_ROOM
		InboxItem.Category.TRANSFER:
			return WorldEvent.Category.TRANSFER
		InboxItem.Category.CONTRACT:
			return WorldEvent.Category.CONTRACT
		InboxItem.Category.TRAINING:
			return WorldEvent.Category.TRAINING
		InboxItem.Category.YOUTH:
			return WorldEvent.Category.YOUTH
		InboxItem.Category.STAFF:
			return WorldEvent.Category.STAFF
		_:
			return WorldEvent.Category.MATCH


static func _ordinal(n: int) -> String:
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
