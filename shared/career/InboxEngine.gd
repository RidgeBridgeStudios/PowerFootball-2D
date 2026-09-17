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


## Pre/post-match incident press conference questionnaire citing player names,
## incident tags, and sentiment, directly connecting WorldEventLog unhandled incidents.
static func build_incident_press_conference(
	event: WorldEvent,
	is_post_match: bool,
	today: CareerDate,
	opponent_name: String = ""
) -> InboxItem:
	var player_name: String = event.primary_player_name if event.primary_player_name != "" else "the squad"
	var question: String = PressOffice.generate_incident_question(
		event.event_tag, player_name, event.sentiment, is_post_match, opponent_name
	)
	var title_prefix: String = "Post-Match Press: " if is_post_match else "Press Conference: "
	var item: InboxItem = InboxItem.make(
		title_prefix + event.category_name() + " Incident",
		question,
		InboxItem.Category.MEDIA,
		today
	)
	item.with_subject_player(event.primary_player_key, player_name)
	item.priority = clampf(event.significance + 0.15, 0.5, 0.95)
	item.payload = {
		"kind": "incident_press_conference",
		"event_tag": String(event.event_tag),
		"sentiment": event.sentiment,
		"significance": event.significance,
		"is_post_match": is_post_match,
		"opponent_name": opponent_name,
	}

	# 1. Defend player publicly
	# High player trust delta (+0.08) & squad morale boost (+0.02), slight board risk (-0.02) if negative incident
	var defend_board_conf: float = -0.02 if event.sentiment < 0.0 else 0.01
	item.add_option(
		"Defend the player and keep matters internal",
		"Builds strong player loyalty and squad solidarity. The board question lax discipline.",
		&"press_incident_defend",
		0.02, 0.0, defend_board_conf, -0.01
	)

	# 2. Demand accountability / discipline
	# Reassures board (+0.04) and press (+0.02), hits player trust (-0.12) and slight squad tension (-0.01)
	item.add_option(
		"Demand accountability and affirm high standards",
		"Demonstrates authority. Board and press approve; the player feels hung out to dry.",
		&"press_incident_discipline",
		-0.01, 0.0, 0.04, 0.02
	)

	# 3. Dismiss the story / deflect
	# Neutral impact on board and player, slight press irritation (-0.02)
	item.add_option(
		"Dismiss the media speculation entirely",
		"Focuses attention strictly on football. Neutral impact; press remain unsatisfied.",
		&"press_incident_dismiss",
		0.0, 0.0, 0.0, -0.02
	)

	# Escalation: dismiss/deflect by default
	item.with_deadline(today.advanced_by(2), 2)
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


static func build_training_incident_item(
	data: PlayerData,
	state: PlayerCareerState,
	teammate: PlayerData,
	today: CareerDate
) -> InboxItem:
	var teammate_name: String = teammate.player_name if teammate != null else "a teammate"
	var body: String = "%s was involved in a heated training-ground clash with %s after a dangerous tackle.\n\nThe coaching staff intervened before blows were exchanged, but tension remains high." % [
		data.player_name, teammate_name
	]
	var item: InboxItem = InboxItem.make(
		"Training incident: %s & %s" % [data.player_name, teammate_name],
		body, InboxItem.Category.TRAINING, today
	)
	item.with_subject_player(state.player_key, data.player_name)
	item.priority = 0.65
	item.payload = {
		"kind": "training_incident",
		"teammate_name": teammate_name
	}
	item.add_option(
		"Demand formal apologies and issue warnings",
		"Sets firm boundaries. Both players will be disciplined.",
		&"training_discipline_both", 0.02, -0.05, 0.01, 0.01
	)
	item.add_option(
		"Send the instigator to train with reserves for 3 days",
		"Protects squad harmony immediately at the cost of the player's morale.",
		&"training_banish_instigator", 0.03, -0.15, 0.02, 0.0
	)
	item.add_option(
		"Let the players settle it man-to-man",
		"Avoids heavy-handed managerial intervention.",
		&"training_let_settle", -0.02, 0.03, -0.01, -0.01
	)
	item.with_deadline(today.advanced_by(2), 0)
	return item


static func build_dressing_room_confrontation_item(
	data: PlayerData,
	state: PlayerCareerState,
	teammate: PlayerData,
	today: CareerDate
) -> InboxItem:
	var teammate_name: String = teammate.player_name if teammate != null else "the squad"
	var body: String = "%s confronted %s in the dressing room after training, questioning leadership and playing time distribution.\n\nSeveral senior squad members looked on intently." % [
		data.player_name, teammate_name
	]
	var item: InboxItem = InboxItem.make(
		"Dressing room row: %s" % data.player_name,
		body, InboxItem.Category.PLAYER, today
	)
	item.with_subject_player(state.player_key, data.player_name)
	item.priority = 0.7
	item.payload = {
		"kind": "confrontation",
		"teammate_name": teammate_name
	}
	item.add_option(
		"Hold an open team meeting to clear the air",
		"Risky but can build long-term collective trust if handled well.",
		&"confrontation_team_meeting", 0.04, -0.02, 0.02, 0.01
	)
	item.add_option(
		"Back the squad leadership firmly",
		"Reaffirms club hierarchy, marginalizing the disruptive player.",
		&"confrontation_back_hierarchy", 0.02, -0.12, 0.01, 0.0
	)
	item.add_option(
		"Call the player into your office privately",
		"Address grievances one-on-one away from the group.",
		&"confrontation_private_talk", 0.01, 0.05, 0.0, 0.01
	)
	item.with_deadline(today.advanced_by(2), 0)
	return item


static func build_media_controversy_item(
	data: PlayerData,
	state: PlayerCareerState,
	today: CareerDate
) -> InboxItem:
	var body: String = "%s made controversial remarks to journalists regarding recent tactical selections and dressing room morale.\n\nThe comments have gained heavy traction across sports press." % data.player_name
	var item: InboxItem = InboxItem.make(
		"Media controversy: %s" % data.player_name,
		body, InboxItem.Category.MEDIA, today
	)
	item.with_subject_player(state.player_key, data.player_name)
	item.priority = 0.65
	item.payload = {"kind": "media_controversy"}
	item.add_option(
		"Publicly reprimand the player and issue a fine",
		"Strong show of authority. The media and board will approve; the player will not.",
		&"media_public_reprimand", 0.01, -0.15, 0.03, 0.02
	)
	item.add_option(
		"Defend the player in the next press briefing",
		"Protects the player from outside heat, earning their loyalty.",
		&"media_defend_player", 0.01, 0.10, -0.01, -0.02
	)
	item.add_option(
		"Refuse to comment and handle it internally",
		"Declines to fuel the press cycle.",
		&"media_no_comment", 0.0, 0.0, 0.0, -0.01
	)
	item.with_deadline(today.advanced_by(2), 0)
	return item


## A captain or squad leader with CaptainMaterial (64) approaches the manager
## as a sounding board regarding dressing room morale and squad confidence.
## docs/SOCIAL_SIMULATION_ARCHITECTURE.md §1.2, §2.3.
static func build_captain_sounding_board(
	data: PlayerData,
	state: PlayerCareerState,
	team: TeamData,
	today: CareerDate
) -> InboxItem:
	var club_name: String = team.team_name if team != null else "the squad"
	var body: String = "%s has requested a private meeting as team captain to discuss dressing room morale and squad harmony at %s.\n\n\"The lads appreciate having an open door, gaffer. A few players have concerns about the current run and expectations, but we're ready to back you if you keep us in the loop.\"" % [
		data.player_name, club_name
	]
	var item: InboxItem = InboxItem.make(
		"Captain's Consultation: %s" % data.player_name,
		body, InboxItem.Category.PLAYER, today
	)
	item.with_subject_player(state.player_key, data.player_name)
	item.priority = 0.70
	item.payload = {"kind": "sounding_board"}
	item.add_option(
		"Back the captain to rally the squad in private",
		"Empowers squad leadership. Squad morale and captain trust improve.",
		&"sounding_board_rally_squad", 0.03, 0.10, 0.0, 0.01
	)
	item.add_option(
		"Conduct an open tactical briefing to address player doubts",
		"Addresses tactical concerns directly. Board and players appreciate clarity.",
		&"sounding_board_tactical_review", 0.02, 0.06, 0.01, 0.01
	)
	item.add_option(
		"Reassure the captain and stay the course",
		"Steady reassurance. Maintains stability without changing routine.",
		&"sounding_board_reassure", 0.0, 0.02, 0.0, 0.0
	)
	item.add_option(
		"Dismiss concerns and demand complete focus on performance",
		"A cold response. Captain feels unheard, and dressing room tension rises.",
		&"sounding_board_dismiss", -0.03, -0.12, -0.01, -0.01
	)
	item.with_deadline(today.advanced_by(3), 3)
	return item


static func build_mutiny_warning(team: TeamData, today: CareerDate) -> InboxItem:
	var club_name: String = team.team_name if team != null else "the club"
	var item: InboxItem = InboxItem.make(
		"CRISIS: Dressing Room Mutiny Warning",
		"Widespread dissatisfaction in the dressing room at %s has reached boiling point. Senior squad leaders warn that players have lost faith in your management and are on the brink of open revolt. An immediate managerial response is required." % club_name,
		InboxItem.Category.PLAYER,
		today
	)
	item.priority = 0.95
	item.payload = {"kind": "mutiny_warning"}
	item.add_option(
		"Call emergency squad meeting: Address grievances and promise changes",
		"Calms the dressing room. Senior leaders feel heard (+0.12 leader trust, +0.08 squad morale). Board notes the unrest (-0.05 confidence).",
		&"mutiny_concede", 0.08, 0.0, -0.05, -0.05
	)
	item.add_option(
		"Assert managerial authority: Demand discipline and respect",
		"High-risk confrontation. Further alienates leaders (-0.15 leader trust, -0.05 squad morale), but shows resolve to the board (+0.05 confidence).",
		&"mutiny_assert_authority", -0.05, 0.0, 0.05, 0.05
	)
	item.add_option(
		"Meet privately with squad leaders: Negotiate a truce",
		"Constructive compromise. Stabilizes dressing room (+0.08 leader trust, +0.03 squad morale).",
		&"mutiny_negotiate", 0.03, 0.0, 0.0, 0.0
	)
	item.with_deadline(today.advanced_by(3), 1)
	return item


static func build_mutiny_board_ultimatum(team: TeamData, board: BoardState, today: CareerDate) -> InboxItem:
	var club_name: String = team.team_name if team != null else "the club"
	var item: InboxItem = InboxItem.make(
		"BOARD CRISIS: Emergency Intervention on Dressing Room Mutiny",
		"The board of %s has intervened following a full dressing room mutiny. Senior players have formally notified club leadership that they will no longer play under your management. The board requires an immediate turnaround plan." % club_name,
		InboxItem.Category.BOARD,
		today
	)
	item.priority = 1.0
	item.payload = {"kind": "dressing_room_mutiny"}
	item.add_option(
		"Accept board terms: Commit to squad reconciliation and immediate turnaround",
		"Pledges cooperation with the board and rebuilding dressing room relationships (+0.05 board confidence, +0.05 squad morale).",
		&"mutiny_board_accept", 0.05, 0.0, 0.05, 0.0
	)
	item.add_option(
		"Defend your position: Challenge player power and demand total board backing",
		"High stakes. If the board does not back you, your position becomes critical (-0.10 board confidence, +0.05 manager reputation).",
		&"mutiny_board_defend", -0.05, 0.0, -0.10, 0.05
	)
	item.with_deadline(today.advanced_by(2), 1)
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
		subject_state.adjust_manager_trust(
			option.subject_trust_delta,
			"inbox decision: %s" % option.label,
			career.user_team_index,
			ordinal
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
					st.adjust_manager_trust(0.02, "backed players publicly", career.user_team_index, ordinal)
		&"training_discipline_both":
			if subject_state != null:
				subject_state.manager_trust = clampf(subject_state.manager_trust - 0.05, 0.0, 1.0)
		&"training_banish_instigator":
			if subject_state != null and subject_data != null:
				subject_data.morale = clampf(subject_data.morale - 0.15, 0.0, 1.0)
				subject_state.manager_trust = clampf(subject_state.manager_trust - 0.10, 0.0, 1.0)
		&"training_let_settle":
			if subject_state != null and subject_data != null:
				subject_data.morale = clampf(subject_data.morale + 0.03, 0.0, 1.0)
		&"confrontation_team_meeting":
			for meeting_key: int in career.player_states:
				var meeting_st: PlayerCareerState = career.player_states[meeting_key] as PlayerCareerState
				if meeting_st != null and meeting_st.team_index == career.user_team_index:
					meeting_st.manager_trust = clampf(meeting_st.manager_trust + 0.03, 0.0, 1.0)
		&"confrontation_back_hierarchy":
			if subject_state != null:
				subject_state.manager_trust = clampf(subject_state.manager_trust - 0.15, 0.0, 1.0)
		&"confrontation_private_talk":
			if subject_state != null and subject_data != null:
				subject_data.morale = clampf(subject_data.morale + 0.05, 0.0, 1.0)
				subject_state.manager_trust = clampf(subject_state.manager_trust + 0.08, 0.0, 1.0)
		&"media_public_reprimand":
			if subject_state != null and subject_data != null:
				subject_data.morale = clampf(subject_data.morale - 0.15, 0.0, 1.0)
				subject_state.manager_trust = clampf(subject_state.manager_trust - 0.10, 0.0, 1.0)
		&"media_defend_player":
			if subject_state != null and subject_data != null:
				subject_data.morale = clampf(subject_data.morale + 0.10, 0.0, 1.0)
				subject_state.manager_trust = clampf(subject_state.manager_trust + 0.12, 0.0, 1.0)
		&"media_no_comment":
			pass
		&"sounding_board_rally_squad":
			if subject_data != null:
				subject_data.morale = clampf(subject_data.morale + 0.05, 0.0, 1.0)
			if subject_state != null:
				subject_state.adjust_manager_trust(0.10, "captain empowered", career.user_team_index, ordinal)
		&"sounding_board_tactical_review":
			if subject_state != null:
				subject_state.adjust_manager_trust(0.06, "open tactical dialogue", career.user_team_index, ordinal)
		&"sounding_board_reassure":
			if subject_state != null:
				subject_state.adjust_manager_trust(0.02, "manager reassurance", career.user_team_index, ordinal)
		&"sounding_board_dismiss":
			if subject_state != null:
				subject_state.adjust_manager_trust(-0.12, "captain concerns dismissed", career.user_team_index, ordinal)
		&"mutiny_concede":
			_apply_mutiny_leader_trust_delta(career, 0.12, "emergency squad meeting resolved grievances", ordinal)
		&"mutiny_assert_authority":
			_apply_mutiny_leader_trust_delta(career, -0.15, "manager confronted mutiny leaders", ordinal)
		&"mutiny_negotiate":
			_apply_mutiny_leader_trust_delta(career, 0.08, "private meeting with squad leaders", ordinal)
		&"mutiny_board_accept":
			if career.board != null:
				career.board.clear_board_intervention()
				career.board.patience_notes.append("Manager accepted board terms to resolve dressing room mutiny.")
				while career.board.patience_notes.size() > 10:
					career.board.patience_notes.remove_at(0)
		&"mutiny_board_defend":
			if career.board != null:
				career.board.patience_notes.append("Manager challenged board and demanded unconditional backing.")
				while career.board.patience_notes.size() > 10:
					career.board.patience_notes.remove_at(0)
		&"press_incident_defend":
			if subject_state != null:
				subject_state.adjust_manager_trust(0.08, "defended publicly in press conference", career.user_team_index, ordinal)
			if subject_data != null:
				subject_data.morale = clampf(subject_data.morale + 0.05, 0.0, 1.0)
		&"press_incident_discipline":
			if subject_state != null:
				subject_state.adjust_manager_trust(-0.12, "disciplined publicly in press conference", career.user_team_index, ordinal)
			if subject_data != null:
				subject_data.morale = clampf(subject_data.morale - 0.08, 0.0, 1.0)
		&"press_incident_dismiss":
			if subject_state != null:
				subject_state.adjust_manager_trust(0.02, "dismissed press speculation", career.user_team_index, ordinal)
		_:
			pass


static func _apply_mutiny_leader_trust_delta(
	career: CareerSaveData,
	delta: float,
	reason: String,
	ordinal: int
) -> void:
	if career == null:
		return
	var team: TeamData = DataLoader.get_team(career.user_team_index)
	if team == null:
		return
	for squad_idx: int in range(team.squad.size()):
		var p: PlayerData = team.squad[squad_idx]
		var is_leader: bool = (
			p.has_trait(WorldEventGenerator.TRAIT_CAPTAIN_MATERIAL)
			or p.has_trait(WorldEventGenerator.TRAIT_VETERAN_LEADER)
			or p.player_reputation >= 0.70
			or p.is_captain
		)
		if is_leader:
			var st: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_idx)
			if st != null:
				st.adjust_manager_trust(delta, reason, career.user_team_index, ordinal)


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
