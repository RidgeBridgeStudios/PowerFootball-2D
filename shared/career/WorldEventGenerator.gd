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


static func roll_for_day(career: CareerSaveData, rng: RandomNumberGenerator) -> void:
	if career == null or career.today == null:
		return

	var user_team_idx: int = career.user_team_index
	var team: TeamData = DataLoader.get_team(user_team_idx)
	if team == null or team.squad.is_empty():
		return

	# Roll per player in user squad
	for squad_idx: int in range(team.squad.size()):
		var data: PlayerData = team.squad[squad_idx]
		var state: PlayerCareerState = career.state_for_squad(user_team_idx, squad_idx)
		if data == null or state == null:
			continue

		var mult: float = _trait_weight(data, state)
		var chance: float = BASE_DAILY_EVENT_CHANCE * mult
		if rng.randf() < chance:
			_fire_event(career, team, squad_idx, data, state, rng)
			# At most one major off-pitch world event per day to keep narrative pacing clean
			break


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
	# Low professionalism elevates incident risk
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
	var roll: float = rng.randf()
	if roll < 0.35:
		_fire_training_incident(career, team, squad_idx, data, state, rng)
	elif roll < 0.70:
		_fire_dressing_room_confrontation(career, team, squad_idx, data, state, rng)
	else:
		_fire_media_or_nightlife(career, team, squad_idx, data, state, rng)


static func _fire_training_incident(
	career: CareerSaveData,
	team: TeamData,
	squad_idx: int,
	data: PlayerData,
	state: PlayerCareerState,
	rng: RandomNumberGenerator
) -> void:
	if _has_pending_item_with_tag(career, state.player_key, "training_incident"):
		return

	# Find a teammate involved if possible
	var teammate_idx: int = _pick_teammate(team, squad_idx, rng)
	var teammate_data: PlayerData = team.squad[teammate_idx] if teammate_idx >= 0 else null
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
	career.inbox.push_front(item)
	GameEvents.career_inbox_changed.emit()


static func _fire_dressing_room_confrontation(
	career: CareerSaveData,
	team: TeamData,
	squad_idx: int,
	data: PlayerData,
	state: PlayerCareerState,
	rng: RandomNumberGenerator
) -> void:
	if _has_pending_item_with_tag(career, state.player_key, "confrontation"):
		return

	var teammate_idx: int = _pick_teammate(team, squad_idx, rng)
	var teammate_data: PlayerData = team.squad[teammate_idx] if teammate_idx >= 0 else null
	var teammate_name: String = teammate_data.player_name if teammate_data != null else "several teammates"

	var event: WorldEvent = WorldEvent.make(
		&"dressing_room_confrontation",
		WorldEvent.Category.DRESSING_ROOM,
		career.today,
		"%s sparked an argument in the dressing room with %s regarding team hierarchy and standards." % [data.player_name, teammate_name],
		-0.35,
		0.55
	).with_player(state.player_key, data.player_name)
	if teammate_idx >= 0:
		event.with_secondary(career.user_team_index * 1000 + teammate_idx, teammate_name)
	event.with_club(team.team_name)

	WorldEventLog.log_event(event)
	var item: InboxItem = InboxEngine.build_dressing_room_confrontation_item(data, state, teammate_data, career.today)
	career.inbox.push_front(item)
	GameEvents.career_inbox_changed.emit()


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
			career.inbox.push_front(InboxEngine.build_nightlife_incident(data, state, career.today))
			GameEvents.career_inbox_changed.emit()
	else:
		if not _has_pending_item_with_tag(career, state.player_key, "media_controversy"):
			var media_event: WorldEvent = WorldEvent.make(
				&"media_controversy",
				WorldEvent.Category.MEDIA,
				career.today,
				"%s gave an unsanctioned media interview criticizing recent tactical setups." % data.player_name,
				-0.2,
				0.5
			).with_player(state.player_key, data.player_name).with_club(team.team_name)
			WorldEventLog.log_event(media_event)
			var item: InboxItem = InboxEngine.build_media_controversy_item(data, state, career.today)
			career.inbox.push_front(item)
			GameEvents.career_inbox_changed.emit()


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
