##
## WorldEventGenerator
##
## Evaluates between-match social simulation events on each daily tick
## (CareerManager.advance_day()). Generates training incidents, dressing-room
## confrontations, and street/nightlife/media events influenced by player traits
## and squad conditions.
##
## Stateless RefCounted: runs directly over CareerSaveData and DataLoader.
##

class_name WorldEventGenerator
extends RefCounted

## Daily base chance per squad player of triggering an event check.
const BASE_DAILY_EVENT_CHANCE: float = 0.012

## Trait bitmask constants (matching PlayerData.traits)
const TRAIT_HOT_HEADED_TACKLER: int = 8
const TRAIT_LOCKER_ROOM_CANCER: int = 32
const TRAIT_CAPTAIN_MATERIAL: int = 64
const TRAIT_STREET_BALLER: int = 128
const TRAIT_PRIDE_GLORY: int = 256
const TRAIT_VETERAN_LEADER: int = 512
const TRAIT_DEAD_BALL_SPECIALIST: int = 1024
const TRAIT_NIGHT_OWL: int = 2048

## Mutiny thresholds per docs/Social Dynamics Simulation Engine Implementation.md
const MUTINY_SQUAD_MORALE_THRESHOLD: float = 0.35
const MUTINY_MANAGER_TRUST_THRESHOLD: float = 0.30
const MUTINY_CRITICAL_MORALE_THRESHOLD: float = 0.25
const MUTINY_CRITICAL_TRUST_THRESHOLD: float = 0.20

## Manager honeymoon grace period (first 45 days or first 5 competitive matches)
const HONEYMOON_DAYS_THRESHOLD: int = 45
const HONEYMOON_MIN_MATCHES: int = 5

## Team-wide incident cooldown period in days
const INCIDENT_COOLDOWN_DAYS: int = 21

## Minimum days between captain consultations
const CAPTAIN_CONSULTATION_COOLDOWN_DAYS: int = 45


static func is_in_honeymoon_period(career: CareerSaveData) -> bool:
	if career == null or career.today == null:
		return false
	if career.phase == CareerSaveData.Phase.PRE_SEASON:
		return true
	var matches_played: int = career.recent_user_results(100).size()
	if matches_played < HONEYMOON_MIN_MATCHES:
		return true
	if career.profile != null and career.profile.contract != null and career.profile.contract.signed_on != null:
		var days_in_charge: int = career.profile.contract.signed_on.days_until(career.today)
		if days_in_charge < HONEYMOON_DAYS_THRESHOLD:
			return true
	return false


static func has_recent_incident(career: CareerSaveData, days: int = INCIDENT_COOLDOWN_DAYS) -> bool:
	if career == null or career.today == null:
		return false
	var cutoff: CareerDate = career.today.advanced_by(-days)
	for i: int in range(career.world_events.size() - 1, -1, -1):
		var ev: WorldEvent = career.world_events[i]
		if ev == null or ev.date == null:
			continue
		if ev.date.is_before(cutoff):
			break
		var tag: StringName = ev.event_tag
		if (
			tag == &"training_incident"
			or tag == &"dressing_room_confrontation"
			or tag == &"media_controversy"
			or tag == &"nightlife_incident"
			or tag == &"mutiny_warning"
			or tag == &"dressing_room_mutiny"
		):
			return true
	return false


static func has_unresolved_incident_inbox_item(career: CareerSaveData) -> bool:
	if career == null:
		return false
	for item: InboxItem in career.inbox:
		if item.is_resolved:
			continue
		var kind: String = String(item.payload.get("kind", ""))
		if (
			kind == "training_incident"
			or kind == "confrontation"
			or kind == "media_controversy"
			or kind == "nightlife"
			or kind == "incident_press_conference"
		):
			return true
	return false


static func _get_recent_performance(career: CareerSaveData) -> Dictionary:
	var perf: Dictionary = {
		"matches_played": 0,
		"consecutive_losses": 0,
		"winless_streak": 0,
		"last_match_lost": false,
		"last_match_heavy_loss": false,
		"form_factor": 0.5,
	}
	if career == null:
		return perf

	var league: CompetitionData = career.league_competition()
	if league != null:
		var row: LeagueTableRow = league.row_for(career.user_team_index)
		if row != null:
			perf["form_factor"] = row.form_factor()

	var recent: Array[FixtureData] = career.recent_user_results(10)
	perf["matches_played"] = recent.size()
	if recent.is_empty():
		return perf

	var last_fx: FixtureData = recent[recent.size() - 1]
	var user_idx: int = career.user_team_index
	var is_home: bool = last_fx.is_home_for(user_idx)
	var user_score: int = last_fx.home_score if is_home else last_fx.away_score
	var opp_score: int = last_fx.away_score if is_home else last_fx.home_score
	if user_score < opp_score:
		perf["last_match_lost"] = true
		if opp_score - user_score >= 3:
			perf["last_match_heavy_loss"] = true

	var cur_losses: int = 0
	var cur_winless: int = 0
	var checking_losses: bool = true
	for i: int in range(recent.size() - 1, -1, -1):
		var fx: FixtureData = recent[i]
		var fx_home: bool = fx.is_home_for(user_idx)
		var u_sc: int = fx.home_score if fx_home else fx.away_score
		var o_sc: int = fx.away_score if fx_home else fx.home_score

		if u_sc > o_sc:
			break
		else:
			cur_winless += 1
			if checking_losses:
				if u_sc < o_sc:
					cur_losses += 1
				else:
					checking_losses = false

	perf["consecutive_losses"] = cur_losses
	perf["winless_streak"] = cur_winless
	return perf


static func calculate_squad_volatility(career: CareerSaveData, team: TeamData) -> float:
	if career == null or team == null or team.squad.is_empty():
		return 0.0

	var volatility: float = 0.0008
	var perf: Dictionary = _get_recent_performance(career)
	var form: float = float(perf.get("form_factor", 0.5))
	var consecutive_losses: int = int(perf.get("consecutive_losses", 0))
	var winless_streak: int = int(perf.get("winless_streak", 0))

	# Good results squash unrest
	if form >= 0.60:
		volatility *= 0.15
	elif form <= 0.30:
		volatility *= 2.5

	# Consecutive losses ratchet up dressing room tension
	if consecutive_losses >= 3:
		volatility *= 4.0
	elif consecutive_losses == 2:
		volatility *= 2.2
	elif consecutive_losses == 1:
		volatility *= 1.2

	# Winless runs
	if winless_streak >= 5:
		volatility *= 3.0
	elif winless_streak >= 3:
		volatility *= 1.8

	# Heavy defeat shock
	if bool(perf.get("last_match_heavy_loss", false)):
		volatility += 0.004

	# Squad morale and leader trust
	var mean_morale: float = get_mean_squad_morale(team)
	if mean_morale >= 0.68:
		volatility *= 0.20
	elif mean_morale < 0.40:
		volatility *= 3.0
	elif mean_morale < 0.50:
		volatility *= 1.8

	var leader_trust: float = get_mean_leader_trust(team, career)
	if leader_trust < 0.38:
		volatility *= 1.8
	elif leader_trust > 0.65:
		volatility *= 0.5

	return clampf(volatility, 0.0, 0.035)


static func roll_for_day(career: CareerSaveData, rng: RandomNumberGenerator) -> void:
	if career == null or career.today == null:
		return

	var user_team_idx: int = career.user_team_index
	var team: TeamData = DataLoader.get_team(user_team_idx)
	if team == null or team.squad.is_empty():
		return

	# 1. Check New Manager Honeymoon Period
	if is_in_honeymoon_period(career):
		_check_honeymoon_captain_welcome(career, team)
		return

	# 2. Dressing room mutiny check (only evaluated outside honeymoon period)
	if check_mutiny_threshold(team, career):
		_handle_mutiny_crisis(career, team, rng)
		return

	# 3. Incident Cooldown Check: avoid back-to-back incident spam
	var mean_morale: float = get_mean_squad_morale(team)
	var is_critical_crisis: bool = mean_morale < 0.28
	if not is_critical_crisis and has_recent_incident(career, INCIDENT_COOLDOWN_DAYS):
		return

	# 4. Check if manager already has an unresolved controversy decision in inbox
	if has_unresolved_incident_inbox_item(career):
		return

	# 5. Captain Sounding Board Check (prioritized before negative incidents if morale dips)
	if _check_captain_sounding_board_due(career, team):
		_fire_captain_sounding_board(career, team)
		return

	# 6. Evaluate squad volatility based on actual results and outcomes
	var volatility: float = calculate_squad_volatility(career, team)
	if rng.randf() >= volatility:
		return

	# 7. Roll succeeded — fire the most deliberate, contextually justified incident
	_evaluate_deliberate_incident(career, team, rng)


static func _evaluate_deliberate_incident(career: CareerSaveData, team: TeamData, rng: RandomNumberGenerator) -> void:
	var perf: Dictionary = _get_recent_performance(career)
	var matches_played: int = int(perf.get("matches_played", 0))
	var winless_streak: int = int(perf.get("winless_streak", 0))
	var consecutive_losses: int = int(perf.get("consecutive_losses", 0))
	var last_match_lost: bool = bool(perf.get("last_match_lost", false))
	var form_factor: float = float(perf.get("form_factor", 0.5))

	var is_in_slump: bool = consecutive_losses >= 2 or winless_streak >= 2 or form_factor < 0.35 or bool(perf.get("last_match_heavy_loss", false))
	var p_data: PlayerData = null
	var p_state: PlayerCareerState = null

	# Priority A: Media controversy — if in a slump and an aggrieved player exists
	if matches_played >= 3 and is_in_slump:
		var media_candidate_idx: int = _find_media_controversy_candidate(team, career)
		if media_candidate_idx >= 0:
			p_data = team.squad[media_candidate_idx]
			p_state = career.state_for_squad(career.user_team_index, media_candidate_idx)
			_fire_media_or_nightlife(career, team, media_candidate_idx, p_data, p_state, rng)
			return

	# Priority B: Dressing room confrontation — if bad result / slump and rivalry or conflict exists
	if last_match_lost or winless_streak >= 2 or get_mean_squad_morale(team) < 0.48:
		var conf_pair: Array[int] = _find_confrontation_pair(team, career, rng)
		if not conf_pair.is_empty():
			var instigator_idx: int = conf_pair[0]
			p_data = team.squad[instigator_idx]
			p_state = career.state_for_squad(career.user_team_index, instigator_idx)
			var target_idx: int = conf_pair[1]
			_fire_dressing_room_confrontation_with_target(career, team, instigator_idx, p_data, p_state, target_idx)
			return

	# Priority C: Training incident — if hot-headed players or training tension exists
	var train_pair: Array[int] = _find_training_incident_pair(team, career, rng)
	if not train_pair.is_empty():
		var train_instigator_idx: int = train_pair[0]
		p_data = team.squad[train_instigator_idx]
		p_state = career.state_for_squad(career.user_team_index, train_instigator_idx)
		var train_target_idx: int = train_pair[1]
		_fire_training_incident_with_target(career, team, train_instigator_idx, p_data, p_state, train_target_idx)
		return

	# Priority D: Nightlife incident — for night owl / street baller on a rest/quiet day
	var nightlife_idx: int = _find_nightlife_candidate(team, rng)
	if nightlife_idx >= 0:
		p_data = team.squad[nightlife_idx]
		p_state = career.state_for_squad(career.user_team_index, nightlife_idx)
		_fire_media_or_nightlife(career, team, nightlife_idx, p_data, p_state, rng)
		return


static func _find_media_controversy_candidate(team: TeamData, career: CareerSaveData) -> int:
	var user_team_idx: int = career.user_team_index
	var candidates: Array[int] = []
	for squad_idx: int in range(team.squad.size()):
		var data: PlayerData = team.squad[squad_idx]
		var state: PlayerCareerState = career.state_for_squad(user_team_idx, squad_idx)
		if data == null or state == null:
			continue
		if _has_pending_item_with_tag(career, state.player_key, "media_controversy"):
			continue
		if state.manager_trust >= 0.55 or data.morale >= 0.65:
			continue

		var has_grievance: bool = false
		if state.contract != null and state.contract.promised_status <= ContractData.Status.REGULAR_STARTER:
			if state.appearances < 4 and data.player_reputation >= 0.60:
				has_grievance = true
		if state.manager_trust < 0.38:
			has_grievance = true
		if data.has_trait(TRAIT_LOCKER_ROOM_CANCER) and data.morale < 0.55:
			has_grievance = true
		if data.has_trait(TRAIT_PRIDE_GLORY) and state.appearances < 5:
			has_grievance = true
		if data.professionalism < 0.35 and data.morale < 0.45:
			has_grievance = true

		if has_grievance:
			candidates.append(squad_idx)

	if candidates.is_empty():
		return -1
	return candidates[0]


static func _find_confrontation_pair(team: TeamData, career: CareerSaveData, rng: RandomNumberGenerator) -> Array[int]:
	var user_team_idx: int = career.user_team_index
	for squad_idx: int in range(team.squad.size()):
		var state: PlayerCareerState = career.state_for_squad(user_team_idx, squad_idx)
		if state == null:
			continue
		for other_key: int in state.relationships:
			var rel: RelationshipData = state.relationships[other_key] as RelationshipData
			if rel != null and rel.rivalry_score >= 0.35:
				var other_squad_idx: int = other_key % 1000
				if other_squad_idx >= 0 and other_squad_idx < team.squad.size() and other_squad_idx != squad_idx:
					return [squad_idx, other_squad_idx]

	var leaders: Array[int] = []
	var undisciplined: Array[int] = []
	for squad_idx: int in range(team.squad.size()):
		var data: PlayerData = team.squad[squad_idx]
		if data.has_trait(TRAIT_CAPTAIN_MATERIAL) or data.has_trait(TRAIT_VETERAN_LEADER) or data.is_captain:
			leaders.append(squad_idx)
		elif data.professionalism < 0.42 or data.morale < 0.38 or data.has_trait(TRAIT_LOCKER_ROOM_CANCER):
			undisciplined.append(squad_idx)

	if not leaders.is_empty() and not undisciplined.is_empty():
		var l_idx: int = leaders[rng.randi_range(0, leaders.size() - 1)]
		var u_idx: int = undisciplined[rng.randi_range(0, undisciplined.size() - 1)]
		return [l_idx, u_idx]

	for squad_idx: int in range(team.squad.size()):
		var toxic_p: PlayerData = team.squad[squad_idx]
		if toxic_p.has_trait(TRAIT_LOCKER_ROOM_CANCER) and toxic_p.morale < 0.45:
			var teammate: int = _pick_teammate(team, squad_idx, rng)
			if teammate >= 0:
				return [squad_idx, teammate]

	return []


static func _find_training_incident_pair(team: TeamData, _career: CareerSaveData, rng: RandomNumberGenerator) -> Array[int]:
	var hot_heads: Array[int] = []
	for squad_idx: int in range(team.squad.size()):
		var data: PlayerData = team.squad[squad_idx]
		if data.has_trait(TRAIT_HOT_HEADED_TACKLER) or data.temperament < 0.35:
			hot_heads.append(squad_idx)

	if not hot_heads.is_empty():
		var instigator: int = hot_heads[rng.randi_range(0, hot_heads.size() - 1)]
		var teammate: int = _pick_teammate(team, instigator, rng)
		if teammate >= 0:
			return [instigator, teammate]

	return []


static func _find_nightlife_candidate(team: TeamData, rng: RandomNumberGenerator) -> int:
	var candidates: Array[int] = []
	for squad_idx: int in range(team.squad.size()):
		var data: PlayerData = team.squad[squad_idx]
		if (data.has_trait(TRAIT_STREET_BALLER) or data.has_trait(TRAIT_NIGHT_OWL)) and data.professionalism < 0.40:
			candidates.append(squad_idx)
	if candidates.is_empty():
		return -1
	if rng.randf() < 0.05:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	return -1


static func _check_honeymoon_captain_welcome(career: CareerSaveData, team: TeamData) -> void:
	if career == null or team == null or career.today == null:
		return
	var captain_idx: int = _find_captain_index(team)
	if captain_idx < 0:
		return
	var state: PlayerCareerState = career.state_for_squad(career.user_team_index, captain_idx)
	if state == null:
		return
	if _has_pending_item_with_tag(career, state.player_key, "sounding_board"):
		return
	if career.profile != null and career.profile.contract != null and career.profile.contract.signed_on != null:
		var days: int = career.profile.contract.signed_on.days_until(career.today)
		if days >= 7 and days <= 14 and not _has_past_captain_consultation(career):
			var data: PlayerData = team.squad[captain_idx]
			_fire_captain_sounding_board(career, team, captain_idx, data, state)


static func _check_captain_sounding_board_due(career: CareerSaveData, team: TeamData) -> bool:
	if career == null or team == null or career.today == null:
		return false
	var captain_idx: int = _find_captain_index(team)
	if captain_idx < 0:
		return false
	var state: PlayerCareerState = career.state_for_squad(career.user_team_index, captain_idx)
	if state == null:
		return false
	if _has_pending_item_with_tag(career, state.player_key, "sounding_board"):
		return false

	var cutoff: CareerDate = career.today.advanced_by(-CAPTAIN_CONSULTATION_COOLDOWN_DAYS)
	for ev: WorldEvent in career.world_events:
		if ev.event_tag == &"captain_consultation" and ev.date != null and not ev.date.is_before(cutoff):
			return false

	var mean_morale: float = get_mean_squad_morale(team)
	var perf: Dictionary = _get_recent_performance(career)
	var winless: int = int(perf.get("winless_streak", 0))

	return mean_morale < 0.50 or winless >= 3


static func _has_past_captain_consultation(career: CareerSaveData) -> bool:
	if career == null:
		return false
	for ev: WorldEvent in career.world_events:
		if ev.event_tag == &"captain_consultation":
			return true
	return false


static func _find_captain_index(team: TeamData) -> int:
	if team == null:
		return -1
	for i: int in range(team.squad.size()):
		var p: PlayerData = team.squad[i]
		if p.is_captain:
			return i
	for i: int in range(team.squad.size()):
		var p_candidate: PlayerData = team.squad[i]
		if p_candidate.has_trait(TRAIT_CAPTAIN_MATERIAL):
			return i
	return 0 if not team.squad.is_empty() else -1


static func _trait_weight(data: PlayerData, state: PlayerCareerState) -> float:
	var mult: float = 1.0
	if data.has_trait(TRAIT_LOCKER_ROOM_CANCER):
		mult *= 2.2
	if data.has_trait(TRAIT_STREET_BALLER) or data.has_trait(TRAIT_NIGHT_OWL):
		mult *= 1.8
	if data.has_trait(TRAIT_HOT_HEADED_TACKLER):
		mult *= 1.5
	if data.has_trait(TRAIT_PRIDE_GLORY) and state.appearances < 5:
		mult *= 1.6
	if data.has_trait(TRAIT_VETERAN_LEADER) or data.has_trait(TRAIT_CAPTAIN_MATERIAL):
		mult *= 0.6
	if data.has_trait(TRAIT_DEAD_BALL_SPECIALIST):
		mult *= 0.8
	if data.professionalism < 0.4:
		mult *= 1.5
	return mult


static func _fire_event(
	career: CareerSaveData,
	team: TeamData,
	squad_idx: int,
	data: PlayerData,
	state: PlayerCareerState,
	rng: RandomNumberGenerator
) -> void:
	if (data.has_trait(TRAIT_CAPTAIN_MATERIAL) or data.is_captain) and not _has_pending_item_with_tag(career, state.player_key, "sounding_board"):
		_fire_captain_sounding_board(career, team, squad_idx, data, state)
		return

	var roll: float = rng.randf()
	if roll < 0.35:
		_fire_training_incident(career, team, squad_idx, data, state, rng)
	elif roll < 0.70:
		_fire_dressing_room_confrontation(career, team, squad_idx, data, state, rng)
	else:
		_fire_media_or_nightlife(career, team, squad_idx, data, state, rng)


static func _fire_captain_sounding_board(
	career: CareerSaveData,
	team: TeamData,
	_squad_idx: int = -1,
	p_data: PlayerData = null,
	p_state: PlayerCareerState = null
) -> void:
	var captain_idx: int = _squad_idx
	var data: PlayerData = p_data
	var state: PlayerCareerState = p_state
	if captain_idx < 0 or data == null or state == null:
		captain_idx = _find_captain_index(team)
		if captain_idx < 0:
			return
		data = team.squad[captain_idx]
		state = career.state_for_squad(career.user_team_index, captain_idx)
		if state == null:
			return

	var event: WorldEvent = WorldEvent.make(
		&"captain_consultation",
		WorldEvent.Category.DRESSING_ROOM,
		career.today,
		"%s requested a private meeting as team captain to assess dressing room morale and squad confidence." % data.player_name,
		0.1,
		0.5
	).with_player(state.player_key, data.player_name).with_club(team.team_name)
	WorldEventLog.log_event(event)
	var item: InboxItem = InboxEngine.build_captain_sounding_board(data, state, team, career.today)
	_push_inbox_item(career, item)


static func _fire_training_incident(
	career: CareerSaveData,
	team: TeamData,
	squad_idx: int,
	data: PlayerData,
	state: PlayerCareerState,
	rng: RandomNumberGenerator
) -> void:
	var teammate_idx: int = _pick_teammate(team, squad_idx, rng)
	_fire_training_incident_with_target(career, team, squad_idx, data, state, teammate_idx)


static func _fire_training_incident_with_target(
	career: CareerSaveData,
	team: TeamData,
	_squad_idx: int,
	data: PlayerData,
	state: PlayerCareerState,
	teammate_idx: int
) -> void:
	if _has_pending_item_with_tag(career, state.player_key, "training_incident"):
		return

	var teammate_data: PlayerData = team.squad[teammate_idx] if (teammate_idx >= 0 and teammate_idx < team.squad.size()) else null
	var teammate_name: String = teammate_data.player_name if teammate_data != null else "a teammate"

	var event: WorldEvent = WorldEvent.make(
		&"training_incident",
		WorldEvent.Category.TRAINING,
		career.today,
		"%s clashed heatedly with %s during a training drill after a reckless tackle." % [data.player_name, teammate_name],
		-0.25,
		0.45
	).with_player(state.player_key, data.player_name)
	if teammate_idx >= 0:
		event.with_secondary(career.user_team_index * 1000 + teammate_idx, teammate_name)
	event.with_club(team.team_name)

	WorldEventLog.log_event(event)
	var item: InboxItem = InboxEngine.build_training_incident_item(data, state, teammate_data, career.today)
	_push_inbox_item(career, item)


static func _fire_dressing_room_confrontation(
	career: CareerSaveData,
	team: TeamData,
	squad_idx: int,
	data: PlayerData,
	state: PlayerCareerState,
	rng: RandomNumberGenerator
) -> void:
	var teammate_idx: int = _pick_teammate(team, squad_idx, rng)
	_fire_dressing_room_confrontation_with_target(career, team, squad_idx, data, state, teammate_idx)


static func _fire_dressing_room_confrontation_with_target(
	career: CareerSaveData,
	team: TeamData,
	_squad_idx: int,
	data: PlayerData,
	state: PlayerCareerState,
	teammate_idx: int
) -> void:
	if _has_pending_item_with_tag(career, state.player_key, "confrontation"):
		return

	var teammate_data: PlayerData = team.squad[teammate_idx] if (teammate_idx >= 0 and teammate_idx < team.squad.size()) else null
	var teammate_name: String = teammate_data.player_name if teammate_data != null else "several teammates"

	var event: WorldEvent = WorldEvent.make(
		&"dressing_room_confrontation",
		WorldEvent.Category.DRESSING_ROOM,
		career.today,
		"%s sparked a heated dressing room confrontation with %s regarding standards and recent results." % [data.player_name, teammate_name],
		-0.35,
		0.55
	).with_player(state.player_key, data.player_name)
	if teammate_idx >= 0:
		event.with_secondary(career.user_team_index * 1000 + teammate_idx, teammate_name)
	event.with_club(team.team_name)

	WorldEventLog.log_event(event)
	var item: InboxItem = InboxEngine.build_dressing_room_confrontation_item(data, state, teammate_data, career.today)
	_push_inbox_item(career, item)


static func _fire_media_or_nightlife(
	career: CareerSaveData,
	team: TeamData,
	_squad_idx: int,
	data: PlayerData,
	state: PlayerCareerState,
	_rng: RandomNumberGenerator
) -> void:
	if data.has_trait(TRAIT_STREET_BALLER) or data.has_trait(TRAIT_NIGHT_OWL):
		if not _has_pending_item_with_tag(career, state.player_key, "nightlife"):
			var event: WorldEvent = WorldEvent.make(
				&"nightlife_incident",
				WorldEvent.Category.PERSONAL_LIFE,
				career.today,
				"%s was spotted partying into the early hours ahead of training." % data.player_name,
				-0.3,
				0.6
			).with_player(state.player_key, data.player_name).with_club(team.team_name)
			WorldEventLog.log_event(event)
			_push_inbox_item(career, InboxEngine.build_nightlife_incident(data, state, career.today))
	else:
		if not _has_pending_item_with_tag(career, state.player_key, "media_controversy"):
			var media_event: WorldEvent = WorldEvent.make(
				&"media_controversy",
				WorldEvent.Category.MEDIA,
				career.today,
				"%s gave an unsanctioned media interview criticizing recent tactical setups and team direction." % data.player_name,
				-0.2,
				0.5
			).with_player(state.player_key, data.player_name).with_club(team.team_name)
			WorldEventLog.log_event(media_event)
			var item: InboxItem = InboxEngine.build_media_controversy_item(data, state, career.today)
			_push_inbox_item(career, item)


static func _pick_teammate(team: TeamData, exclude_idx: int, rng: RandomNumberGenerator) -> int:
	if team.squad.size() <= 1:
		return -1
	var candidates: Array[int] = []
	for i: int in range(team.squad.size()):
		if i != exclude_idx:
			candidates.append(i)
	if candidates.is_empty():
		return -1
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _has_pending_item_with_tag(career: CareerSaveData, player_key: int, tag: String) -> bool:
	for item: InboxItem in career.inbox:
		if item.is_resolved:
			continue
		if item.subject_player_key == player_key and String(item.payload.get("kind", "")) == tag:
			return true
	return false


static func _push_inbox_item(career: CareerSaveData, item: InboxItem) -> void:
	if career == null or item == null:
		return
	career.inbox.push_front(item)
	while career.inbox.size() > 200:
		career.inbox.pop_back()
	GameEvents.career_inbox_changed.emit(
		career.unread_inbox_count(), career.pending_decision_count()
	)


## Evaluates dual conditions: mean squad morale < 0.35 AND mean manager trust
## among squad leaders (CaptainMaterial, VeteranLeader, or player_reputation >= 0.70) < 0.30.
## Returns true when mutiny threshold is breached.
static func check_mutiny_threshold(team: TeamData, career: CareerSaveData) -> bool:
	if team == null or team.squad.is_empty():
		return false

	var mean_morale: float = get_mean_squad_morale(team)
	if mean_morale >= MUTINY_SQUAD_MORALE_THRESHOLD:
		return false

	var mean_trust: float = get_mean_leader_trust(team, career)
	return mean_trust < MUTINY_MANAGER_TRUST_THRESHOLD


static func get_mean_squad_morale(team: TeamData) -> float:
	if team == null or team.squad.is_empty():
		return 0.5
	var total_morale: float = 0.0
	for p: PlayerData in team.squad:
		total_morale += p.morale
	return total_morale / float(team.squad.size())


static func get_mean_leader_trust(team: TeamData, career: CareerSaveData) -> float:
	if team == null or team.squad.is_empty():
		return 0.5

	var leader_trust_sum: float = 0.0
	var leader_count: int = 0
	var total_squad_trust: float = 0.0
	var squad_size: int = team.squad.size()

	var team_idx: int = career.user_team_index if career != null else 0
	for squad_idx: int in range(squad_size):
		var p: PlayerData = team.squad[squad_idx]
		var trust_val: float = 0.5
		if career != null:
			var st: PlayerCareerState = career.state_for_squad(team_idx, squad_idx)
			if st != null:
				trust_val = st.manager_trust
		elif p.get("manager_trust") != null:
			trust_val = float(p.get("manager_trust"))

		total_squad_trust += trust_val

		var is_leader: bool = (
			p.has_trait(TRAIT_CAPTAIN_MATERIAL)
			or p.has_trait(TRAIT_VETERAN_LEADER)
			or p.player_reputation >= 0.70
			or p.is_captain
		)
		if is_leader:
			leader_trust_sum += trust_val
			leader_count += 1

	if leader_count == 0:
		return total_squad_trust / float(squad_size)

	return leader_trust_sum / float(leader_count)


static func get_squad_leaders(team: TeamData) -> Array[PlayerData]:
	var leaders: Array[PlayerData] = []
	if team == null:
		return leaders
	for p: PlayerData in team.squad:
		if (
			p.has_trait(TRAIT_CAPTAIN_MATERIAL)
			or p.has_trait(TRAIT_VETERAN_LEADER)
			or p.player_reputation >= 0.70
			or p.is_captain
		):
			leaders.append(p)
	return leaders


static func _has_pending_mutiny(career: CareerSaveData) -> bool:
	if career == null:
		return false
	for item: InboxItem in career.inbox:
		if item.is_resolved:
			continue
		var kind: String = String(item.payload.get("kind", ""))
		if kind == "mutiny_warning" or kind == "dressing_room_mutiny":
			return true
	return false


static func _handle_mutiny_crisis(
	career: CareerSaveData,
	team: TeamData,
	_rng: RandomNumberGenerator
) -> void:
	if _has_pending_mutiny(career):
		return

	var mean_morale: float = get_mean_squad_morale(team)
	var leader_trust: float = get_mean_leader_trust(team, career)
	var is_escalated: bool = (
		(mean_morale < MUTINY_CRITICAL_MORALE_THRESHOLD and leader_trust < MUTINY_CRITICAL_TRUST_THRESHOLD)
		or (career.board != null and career.board.board_intervention_active)
	)

	if is_escalated:
		var ev_mutiny: WorldEvent = WorldEvent.make(
			&"dressing_room_mutiny",
			WorldEvent.Category.DRESSING_ROOM,
			career.today,
			"Full-scale dressing room mutiny has erupted at %s. Squad leaders have openly withdrawn support for the manager." % team.team_name,
			-0.90,
			0.95
		).with_club(team.team_name)
		WorldEventLog.log_event(ev_mutiny)

		if career.board != null:
			career.board.trigger_board_intervention("Full dressing room mutiny: Squad leaders have revolted.", 0.25)

		var ultimatum_item: InboxItem = InboxEngine.build_mutiny_board_ultimatum(team, career.board, career.today)
		_push_inbox_item(career, ultimatum_item)
	else:
		var ev_warn: WorldEvent = WorldEvent.make(
			&"mutiny_warning",
			WorldEvent.Category.DRESSING_ROOM,
			career.today,
			"Dressing room unrest at %s has reached boiling point. Senior squad leaders are warning of an imminent mutiny." % team.team_name,
			-0.85,
			0.85
		).with_club(team.team_name)
		WorldEventLog.log_event(ev_warn)

		var warning_item: InboxItem = InboxEngine.build_mutiny_warning(team, career.today)
		_push_inbox_item(career, warning_item)
