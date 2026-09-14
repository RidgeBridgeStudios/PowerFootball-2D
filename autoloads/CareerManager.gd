##
## CareerManager (Autoload singleton)
##
## The authoritative career-state singleton — GameManager's opposite number for
## everything that happens between matches. It owns the live CareerSaveData,
## drives the day loop, and is the only thing that mutates career state.
##
## The day loop is the spine of the mode. advance_day() runs one simulated day:
## recovery, training, scouting, transfer negotiations, AI club activity, inbox
## expiry, then any fixtures scheduled for that date. continue_until_event()
## repeats that until something actually needs the manager, which is the FM
## "Continue" button.
##
## Match-day results reach it through QuickSimEngine. The manager-only pivot
## retired the 22-player real-time match layer, so a fixture is now resolved
## statistically and its outcome is folded back into the career world here.
##
## Has no class_name — Godot 4.7 rejects a class_name that collides with an
## autoload's injected global (see .claude/rules/godot-47-core.md).
##
## Depends on: GameEvents, GameManager, DataLoader, ManagerLoader, StaffLoader,
##             RefereeLoader, WorldEventLog, and the whole shared/career layer.
## Exposes: start_new_career(), load_career(), save_career(), is_career_active(),
##          advance_day(), continue_until_event(), simulate_next_fixture(), career.
##

extends Node

## Reasons the Continue loop stops. Surfaced to the user verbatim.
enum HaltReason { NONE, MATCH_DAY, INBOX_DECISION, SEASON_END, SACKED, TRANSFER_RESPONSE }

## Hard cap on days a single Continue can burn through, so a career with no
## pending events can never spin forever.
const MAX_CONTINUE_DAYS: int = 120
## Season boundaries.
const SEASON_START_MONTH: int = 7
const SEASON_START_DAY: int = 1
const FIRST_MATCHDAY_MONTH: int = 8
const FIRST_MATCHDAY_DAY: int = 8
## Target date for the FINAL league matchday. Fixture spacing is derived from
## this rather than fixed, so a season fills a real football calendar at any
## league size. A hard 7-day spacing gave the shipped 8-club league a season
## that ended in early November.
const LAST_MATCHDAY_MONTH: int = 5
const LAST_MATCHDAY_DAY: int = 17
## Floor, so a very large league still cannot schedule two rounds in two days.
const MIN_MATCHDAY_SPACING_DAYS: int = 3
## The season rolls over on or after this date, once the league is complete.
const SEASON_END_MONTH: int = 6
const SEASON_END_DAY: int = 1
## Summer window: 1 July - 31 August. Winter window: 1 - 31 January.
const SUMMER_WINDOW_MONTHS: Array[int] = [7, 8]
const WINTER_WINDOW_MONTH: int = 1

## The live career. Null when no career is loaded — every public entry point
## guards on this rather than assuming.
var career: CareerSaveData = null

## Deterministic career RNG. Seeded from CareerSaveData.rng_seed so a career
## replays identically, and so two save slots never share a random stream.
##
## Constructed at member scope, not in _ready(): it is the "persistent cached
## member RNG" tools/lint_allocations.py prescribes (that linter flags any
## INDENTED RandomNumberGenerator.new() as a transient allocation), and it also
## guarantees the RNG exists before any autoload ordering question arises.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Last reason continue_until_event() stopped.
var _halt_reason: HaltReason = HaltReason.NONE
var _halt_message: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_career_active() -> bool:
	return career != null and not career.unemployed


func user_team() -> TeamData:
	if career == null:
		return null
	return DataLoader.get_team(career.user_team_index)


func user_manager_data() -> ManagerData:
	if career == null or career.profile == null:
		return null
	return career.profile.tactical


func halt_reason() -> HaltReason:
	return _halt_reason


func halt_message() -> String:
	return _halt_message


## --- Lifecycle -------------------------------------------------------------------

## Creates a career from a finished manager profile and a chosen club.
func start_new_career(profile: ManagerCareerProfile, team_index: int, slot: int) -> CareerSaveData:
	var club: TeamData = DataLoader.get_team(team_index)
	if club == null:
		push_error("CareerManager.start_new_career: team index %d does not exist." % team_index)
		return null

	var start_date: CareerDate = CareerDate.make(
		_default_start_year(), SEASON_START_MONTH, SEASON_START_DAY
	)
	var seed_value: int = int(Time.get_unix_time_from_system()) ^ (slot * 7919)
	career = CareerSaveData.make_new(profile, team_index, start_date, seed_value)
	career.slot_index = slot
	career.save_name = "%s — %s" % [profile.manager_name, club.team_name]
	_rng.seed = seed_value

	profile.current_club = club.team_name
	profile.contract = ContractData.make_default(
		club.team_name, _starting_manager_wage(club, profile), 3, start_date
	)
	profile.sync_to_tactical()

	# The human manager replaces whoever the pool had at this club, so the
	# match layer binds ManagerDirector to the PLAYER's philosophy.
	_install_user_manager(club, profile)

	career.board = BoardState.make_for_club(club, _default_capacity(club))
	career.training = TrainingSchedule.make_default(club.team_name)

	_build_player_states()
	_build_finances()
	_build_competitions()

	WorldEventLog.bind(career)
	WorldEventLog.record(
		&"career_started",
		WorldEvent.Category.BOARD,
		"%s was appointed manager of %s." % [profile.manager_name, club.team_name],
		0.4, 0.8
	)
	_push_inbox(InboxEngine.build_job_welcome(club, career.board, profile, career.today))

	save_career()
	GameEvents.career_started.emit(career.save_name, club.team_name)
	return career


func load_career(slot: int) -> bool:
	var loaded: CareerSaveData = CareerSerializer.load_from_slot(slot)
	if loaded == null:
		return false
	career = loaded
	_rng.seed = career.rng_seed
	# Advance the stream past the days already played, so reloading mid-season
	# does not replay the same random numbers as the first playthrough.
	_rng.state = int(absi(career.today.to_ordinal())) * 6364136223846793005

	if career.profile != null:
		career.profile.sync_to_tactical()
		var club: TeamData = user_team()
		if club != null:
			_install_user_manager(club, career.profile)

	WorldEventLog.bind(career)
	_rehydrate_inbox()
	GameEvents.career_started.emit(career.save_name, career.profile.current_club if career.profile != null else "")
	return true


func save_career() -> bool:
	if career == null:
		return false
	# The manager pool carries the human manager's ManagerData, so it has to be
	# written alongside or a reload would restore the AI manager it replaced.
	ManagerLoader.save_managers()
	return CareerSerializer.save_to_slot(career, career.slot_index)


func close_career() -> void:
	career = null
	WorldEventLog.bind(null)


## Replaces the club's pooled manager with the human one, and parks the
## displaced AI manager as available for hire rather than deleting it.
func _install_user_manager(club: TeamData, profile: ManagerCareerProfile) -> void:
	var incumbent: ManagerData = ManagerLoader.get_manager_for_team(club.team_name)
	if incumbent != null and incumbent != profile.tactical:
		incumbent.current_team = ""
	profile.tactical.current_team = club.team_name
	if not ManagerLoader.manager_pool.has(profile.tactical):
		ManagerLoader.manager_pool.append(profile.tactical)


func _default_start_year() -> int:
	var now: Dictionary = Time.get_datetime_dict_from_system()
	return int(now.get("year", 2026))


func _default_capacity(club: TeamData) -> int:
	# No stadium field exists on TeamData, so capacity is derived from stature
	# rather than invented as a new authored field nothing else would populate.
	return int(round(lerpf(8000.0, 68000.0, clampf(club.reputation, 0.0, 1.0))))


func _starting_manager_wage(club: TeamData, profile: ManagerCareerProfile) -> int:
	var base: float = 4000.0 + club.reputation * 90000.0
	base *= lerpf(0.55, 1.35, clampf(profile.reputation, 0.0, 1.0))
	return maxi(int(round(base / 500.0)) * 500, 1500)


## --- World construction -----------------------------------------------------------

## Creates a PlayerCareerState for every player at every club — AI squads age,
## get injured and develop exactly as the user's does, which is what stops the
## league going stale over a long career.
func _build_player_states() -> void:
	career.player_states.clear()
	if DataLoader.league == null:
		return
	for team_index: int in range(DataLoader.league.teams.size()):
		var team: TeamData = DataLoader.league.teams[team_index]
		for squad_index: int in range(team.squad.size()):
			var data: PlayerData = team.squad[squad_index]
			var age: int = data.get_age(career.today.year, career.today.month, career.today.day)
			var potential: int = PlayerDevelopmentEngine.roll_potential(data, age, _rng)
			var state: PlayerCareerState = PlayerCareerState.make_for(
				data, team_index, squad_index, potential, career.today
			)
			state.contract.club_name = team.team_name
			# Stagger contract lengths so an entire league does not expire at
			# once — authored data has everyone on the same nominal term.
			state.contract.expiry = CareerDate.make(
				career.today.year + _rng.randi_range(1, 4), 6, 30
			)
			state.sharpness = _rng.randf_range(0.45, 0.70)
			career.player_states[state.player_key] = state
	_seed_initial_relationships()


## Gives every squad a starting social graph. Relationships are seeded from
## shared nationality and language plus a little noise, so a dressing room
## begins with real structure rather than a uniform neutral sheet.
func _seed_initial_relationships() -> void:
	if DataLoader.league == null:
		return
	var ordinal: int = career.today.to_ordinal()
	for team_index: int in range(DataLoader.league.teams.size()):
		var team: TeamData = DataLoader.league.teams[team_index]
		for a: int in range(team.squad.size()):
			var state_a: PlayerCareerState = career.state_for_squad(team_index, a)
			if state_a == null:
				continue
			var player_a: PlayerData = team.squad[a]
			for b: int in range(team.squad.size()):
				if a == b:
					continue
				var player_b: PlayerData = team.squad[b]
				var rel: RelationshipData = state_a.relationship_with(team_index * 1000 + b, ordinal)
				var affinity: float = 0.5
				if player_a.nationality == player_b.nationality:
					affinity += 0.14
				elif _share_language(player_a, player_b):
					affinity += 0.07
				else:
					affinity -= 0.05
				# A high-professionalism player gets on with more people.
				affinity += (player_a.professionalism - 0.5) * 0.10
				rel.trust = clampf(affinity + _rng.randf_range(-0.07, 0.07), 0.15, 0.9)
				# A locker-room cancer (32) starts with friction already.
				if player_b.has_trait(32):
					rel.rivalry_score = clampf(_rng.randf_range(0.10, 0.35), 0.0, 1.0)


func _share_language(a: PlayerData, b: PlayerData) -> bool:
	for entry: Dictionary in a.spoken_languages:
		if b.speaks_language(String(entry.get("language", "")), 0.4):
			return true
	return false


func _build_finances() -> void:
	career.club_finances.clear()
	if DataLoader.league == null:
		return
	for team_index: int in range(DataLoader.league.teams.size()):
		var team: TeamData = DataLoader.league.teams[team_index]
		career.club_finances[team_index] = ClubFinances.from_team(team, _default_capacity(team))


func _build_competitions() -> void:
	career.competitions.clear()
	if DataLoader.league == null:
		return

	var total_teams: int = DataLoader.league.teams.size()
	if total_teams == 0:
		return

	var first_matchday: CareerDate = CareerDate.make(
		career.today.year, FIRST_MATCHDAY_MONTH, FIRST_MATCHDAY_DAY
	)

	# 1. Initialize tiers and competitions
	if not DataLoader.divisions.is_empty():
		_build_divisions_competitions(first_matchday)
	else:
		_build_flat_competitions(first_matchday, total_teams)

	# 2. European Champions Cup (Tier 1 qualifiers - top 4)
	var t1_teams: Array[int] = _get_tier_team_indices(1)
	if career.continental_indices.is_empty():
		career.continental_indices.clear()
		for i_c: int in range(mini(4, t1_teams.size())):
			career.continental_indices.append(t1_teams[i_c])

	if not career.continental_indices.is_empty():
		var continental: CompetitionData = CompetitionData.build_continental(
			"European Champions Cup", career.continental_indices, true
		)
		continental.draw_cup_round(first_matchday.advanced_by(18), _rng)
		career.competitions.append(continental)

	# 3. Domestic Cup: Knockout among all teams (with automatic bye seeding)
	var all_indices: Array[int] = []
	for i_all: int in range(total_teams):
		all_indices.append(i_all)
	var cup: CompetitionData = CompetitionData.build_cup("Domestic Cup", all_indices, false)
	cup.draw_cup_round(first_matchday.advanced_by(24), _rng)
	career.competitions.append(cup)

	_tag_user_fixtures()


func _build_divisions_competitions(first_matchday: CareerDate) -> void:
	career.tier_indices.clear()
	var current_idx: int = 0
	var tier_map: Dictionary = {}

	for div_desc: Dictionary in DataLoader.divisions:
		var count: int = int(div_desc.get("team_count", 0))
		var div_name: String = str(div_desc.get("name", "Division"))
		var tier_idx: int = int(div_desc.get("tier_index", 1))
		var grp_idx: int = int(div_desc.get("group_index", -1)) if div_desc.get("group_index") != null else -1
		var promo: int = int(div_desc.get("promotion_slots", 2))
		var releg: int = int(div_desc.get("relegation_slots", 2))

		var div_team_indices: Array[int] = []
		var div_team_names: Array[String] = []
		for i: int in range(count):
			var t_idx: int = current_idx + i
			if t_idx < DataLoader.league.teams.size():
				div_team_indices.append(t_idx)
				div_team_names.append(DataLoader.league.teams[t_idx].team_name)
		current_idx += count

		var comp: CompetitionData = CompetitionData.build_league(
			div_name, div_team_indices, div_team_names, tier_idx, grp_idx, promo, releg
		)
		_schedule_league_competition(comp, first_matchday)
		career.competitions.append(comp)

		if not tier_map.has(tier_idx):
			var arr: Array[int] = []
			tier_map[tier_idx] = arr
		var t_list: Array[int] = tier_map[tier_idx] as Array[int]
		t_list.append_array(div_team_indices)

	var sorted_tier_keys: Array = tier_map.keys()
	sorted_tier_keys.sort()
	for tk: Variant in sorted_tier_keys:
		career.tier_indices.append(tier_map[tk])

	career.tier_1_indices = _get_tier_team_indices(1)
	career.tier_2_indices = _get_tier_team_indices(2)


func _build_flat_competitions(first_matchday: CareerDate, total_teams: int) -> void:
	if career.tier_indices.is_empty():
		career.tier_indices.clear()
		if total_teams <= 20:
			var t1: Array[int] = []
			for i in range(total_teams):
				t1.append(i)
			career.tier_indices.append(t1)
		else:
			var teams_per_tier: int = 20
			var num_tiers: int = (total_teams + teams_per_tier - 1) / teams_per_tier
			var cur: int = 0
			for _t_i: int in range(num_tiers):
				var t_arr: Array[int] = []
				for _j: int in range(teams_per_tier):
					if cur < total_teams:
						t_arr.append(cur)
						cur += 1
				if not t_arr.is_empty():
					career.tier_indices.append(t_arr)

	career.tier_1_indices = _get_tier_team_indices(1)
	career.tier_2_indices = _get_tier_team_indices(2)

	for t_num: int in range(1, career.tier_indices.size() + 1):
		var t_indices: Array[int] = _get_tier_team_indices(t_num)
		if t_indices.is_empty():
			continue
		var t_names: Array[String] = []
		for idx: int in t_indices:
			t_names.append(DataLoader.league.teams[idx].team_name)
		var comp_name: String = "Premier Championship" if t_num == 1 else ("Championship Division %d" % (t_num - 1))
		var promo_slots: int = 0 if t_num == 1 else 2
		var releg_slots: int = 0 if t_num == career.tier_indices.size() else 2
		var comp: CompetitionData = CompetitionData.build_league(
			comp_name, t_indices, t_names, t_num, -1, promo_slots, releg_slots
		)
		_schedule_league_competition(comp, first_matchday)
		career.competitions.append(comp)


func _get_tier_team_indices(tier_num: int) -> Array[int]:
	var res: Array[int] = []
	var idx: int = tier_num - 1
	if idx >= 0 and idx < career.tier_indices.size():
		var raw: Array = career.tier_indices[idx]
		for item: Variant in raw:
			res.append(int(item))
	elif tier_num == 1:
		return career.tier_1_indices
	elif tier_num == 2:
		return career.tier_2_indices
	return res


func _schedule_league_competition(comp: CompetitionData, first_matchday: CareerDate) -> void:
	var team_count: int = comp.participant_indices.size()
	if team_count < 2:
		return

	var first: CareerDate = CareerDate.make(
		career.today.year, FIRST_MATCHDAY_MONTH, FIRST_MATCHDAY_DAY
	)
	var last: CareerDate = CareerDate.make(
		career.today.year + 1, LAST_MATCHDAY_MONTH, LAST_MATCHDAY_DAY
	)
	var window: int = first.days_until(last)
	var double_rounds: int = (team_count - 1) * 2
	var double_fixtures: int = team_count * (team_count - 1)

	var use_single: bool = false
	var max_cap: int = -1

	if double_fixtures > 500 or (double_rounds - 1) * MIN_MATCHDAY_SPACING_DAYS > window:
		push_warning("CareerManager: division '%s' (%d teams) cannot fit double round-robin in season window (%d days) or exceeds 500 fixtures; falling back to single round-robin." % [
			comp.competition_name, team_count, window
		])
		use_single = true

	var single_fixtures: int = team_count * (team_count - 1) / 2
	var single_rounds: int = team_count - 1
	if use_single and (single_fixtures > 500 or (single_rounds - 1) * MIN_MATCHDAY_SPACING_DAYS > window):
		push_warning("CareerManager: division '%s' (%d teams) exceeds 500 fixtures in single round-robin; capping fixtures." % [
			comp.competition_name, team_count
		])
		max_cap = 500 / maxi(team_count / 2, 1)

	var spacing: int = _matchday_spacing(team_count, 1 if use_single else 2)
	comp.generate_league_fixtures(first_matchday, spacing, 1, use_single, max_cap)


## Days between league matchdays, bounded so the season fits within window
## without generating decades-long spacing.
func _matchday_spacing(team_count: int, repeat_cycles: int = 1) -> int:
	var rounds: int = maxi((team_count - 1) * 2 * repeat_cycles, 1)
	if rounds <= 1:
		return MIN_MATCHDAY_SPACING_DAYS
	var first: CareerDate = CareerDate.make(
		career.today.year, FIRST_MATCHDAY_MONTH, FIRST_MATCHDAY_DAY
	)
	var last: CareerDate = CareerDate.make(
		career.today.year + 1, LAST_MATCHDAY_MONTH, LAST_MATCHDAY_DAY
	)
	var window: int = first.days_until(last)
	var target_spacing: int = window / (rounds - 1)
	if target_spacing < MIN_MATCHDAY_SPACING_DAYS:
		push_warning("CareerManager._matchday_spacing: division of %d teams requires %d rounds which cannot fit in %d-day window with spacing >= %d; using minimum spacing." % [
			team_count, rounds, window, MIN_MATCHDAY_SPACING_DAYS
		])
		return MIN_MATCHDAY_SPACING_DAYS
	return target_spacing


func _tag_user_fixtures() -> void:
	for comp: CompetitionData in career.competitions:
		for f: FixtureData in comp.fixtures:
			f.involves_user = f.involves(career.user_team_index)


## --- The day loop ------------------------------------------------------------------

## Advances one simulated day. Returns the halt reason if the day produced
## something the manager must deal with, else HaltReason.NONE.
func advance_day() -> HaltReason:
	if career == null or career.is_sacked:
		return HaltReason.SACKED

	career.today = career.today.advanced_by(1)
	var today: CareerDate = career.today

	_update_transfer_window()
	_update_season_phase()
	_process_takeover_tick()
	_process_international_duty()
	_process_recovery_and_training()
	_process_scouting()
	_process_transfer_negotiations()
	_process_ai_transfer_activity()
	_process_loan_expiries()
	_review_promises()

	# Monday is accounting and U23 development day.
	if today.day_of_week() == 0:
		_run_weekly_cycle()
		_simulate_u23_fixtures()

	# Expiring an ignored decision is itself an event worth stopping for.
	var expired: Array[WorldEvent] = InboxEngine.expire_overdue(career, user_team(), today)
	for e: WorldEvent in expired:
		WorldEventLog.log_event(e)

	var fixtures_today: Array[FixtureData] = career.fixtures_on(today)
	if not fixtures_today.is_empty():
		var user_fixture: FixtureData = null
		for f: FixtureData in fixtures_today:
			if f.involves(career.user_team_index) and not f.played:
				user_fixture = f
			elif not f.played:
				_simulate_ai_fixture(f)
		_advance_cup_rounds()
		if user_fixture != null:
			GameEvents.career_day_advanced.emit(today.to_iso())
			return _halt(HaltReason.MATCH_DAY, "Matchday: %s" % _fixture_label(user_fixture))

	if _check_season_rollover():
		GameEvents.career_day_advanced.emit(today.to_iso())
		return _halt(HaltReason.SEASON_END, "The season has ended.")

	if career.board != null and career.board.should_sack():
		_execute_sacking()
		return _halt(HaltReason.SACKED, "You have been dismissed by the board.")

	GameEvents.career_day_advanced.emit(today.to_iso())
	_emit_inbox_changed()

	if career.pending_decision_count() > 0:
		return _halt(HaltReason.INBOX_DECISION, "There are decisions waiting in your inbox.")

	return HaltReason.NONE


## The FM Continue button: keep advancing until something needs attention.
func continue_until_event() -> HaltReason:
	if career == null:
		return HaltReason.SACKED
	_halt_reason = HaltReason.NONE
	_halt_message = ""
	for _day: int in range(MAX_CONTINUE_DAYS):
		var reason: HaltReason = advance_day()
		if reason != HaltReason.NONE:
			GameEvents.career_advance_halted.emit(_halt_message)
			return reason
	_halt_message = "Nothing scheduled for the next %d days." % MAX_CONTINUE_DAYS
	GameEvents.career_advance_halted.emit(_halt_message)
	return HaltReason.NONE


func _halt(reason: HaltReason, message: String) -> HaltReason:
	_halt_reason = reason
	_halt_message = message
	return reason


## --- Daily subsystems ----------------------------------------------------------------

## Pre-season runs from the July restart to the first competitive fixture;
## the off-season is the gap between the last one and the rollover. Without
## this the phase set at _start_new_season() would read "Pre-Season" all year.
func _update_season_phase() -> void:
	var league: CompetitionData = career.league_competition()
	if league == null:
		return
	if league.is_complete():
		career.phase = CareerSaveData.Phase.OFF_SEASON
		return
	var played_any: bool = false
	for f: FixtureData in league.fixtures:
		if f.played:
			played_any = true
			break
	career.phase = CareerSaveData.Phase.REGULAR_SEASON if played_any \
		else CareerSaveData.Phase.PRE_SEASON


func _update_transfer_window() -> void:
	var month: int = career.today.month
	career.transfer_window_open = SUMMER_WINDOW_MONTHS.has(month) or month == WINTER_WINDOW_MONTH


## Recovery, training load, development and injury rolls, for every club.
func _process_recovery_and_training() -> void:
	if DataLoader.league == null:
		return
	var day_of_week: int = career.today.day_of_week()
	var user_index: int = career.user_team_index

	for team_index: int in range(DataLoader.league.teams.size()):
		var team: TeamData = DataLoader.league.teams[team_index]
		var is_user_club: bool = team_index == user_index

		# Only the user's club has an authored schedule; AI clubs train on a
		# sensible default rather than needing a TrainingSchedule each.
		var session: TrainingSchedule.Session = TrainingSchedule.Session.TECHNICAL
		if is_user_club and career.training != null:
			session = career.training.session_for_day(day_of_week)
		elif day_of_week == 6:
			session = TrainingSchedule.Session.REST

		var intensity: float = TrainingSchedule.intensity_of(session)
		var physio: float = _staff_quality(team, "physio")
		var coach: float = TrainingSchedule.coach_bonus(
			team.staff,
			TrainingSchedule.SESSION_FOCUS[clampi(int(session), 0, TrainingSchedule.SESSION_FOCUS.size() - 1)]
		)
		var facility_mult: float = 1.0
		var medical_mult: float = 1.0
		if is_user_club and career.board != null:
			facility_mult = career.board.facility_multiplier(career.board.training_facilities)
			medical_mult = career.board.facility_multiplier(career.board.medical_facility)

		for squad_index: int in range(team.squad.size()):
			var data: PlayerData = team.squad[squad_index]
			var state: PlayerCareerState = career.state_for_squad(team_index, squad_index)
			if state == null:
				continue

			var healed: bool = state.tick_recovery(physio, 1.0 - intensity, medical_mult)
			if healed and is_user_club:
				_push_inbox(InboxEngine.build_simple(
					"%s is fit again" % data.player_name,
					"%s has completed his rehabilitation and is available for selection." % data.player_name,
					InboxItem.Category.PLAYER, 0.5, career.today
				))
				data.is_unavailable = false

			if state.is_injured():
				continue

			state.apply_training_load(intensity)
			var age: int = data.get_age(career.today.year, career.today.month, career.today.day)
			var focus: TrainingSchedule.Focus = TrainingSchedule.Focus.BALANCED
			if is_user_club and career.training != null:
				focus = career.training.focus_for_player(squad_index)
			PlayerDevelopmentEngine.apply_daily_training(
				data, state, session, focus, coach, facility_mult, age
			)

			# Injury roll.
			var risk: float = TrainingSchedule.daily_injury_risk(
				data, state.condition, intensity, facility_mult, physio, age
			)
			if risk > 0.0 and _rng.randf() < risk:
				_inflict_injury(team_index, squad_index, data, state, is_user_club)

			# StreetBaller (128) nightlife incident — rare, and only for the
			# user's own club, where it actually needs a managerial decision.
			if is_user_club and data.has_trait(128) and _rng.randf() < 0.006 \
					and not _has_pending_nightlife_incident(state.player_key):
				_push_inbox(InboxEngine.build_nightlife_incident(data, state, career.today))

			MoraleEngine.daily_drift(data)


func _inflict_injury(
	team_index: int,
	squad_index: int,
	data: PlayerData,
	state: PlayerCareerState,
	is_user_club: bool
) -> void:
	# Most training injuries are minor; the severe tail is deliberately thin.
	var roll: float = _rng.randf()
	var kind: PlayerCareerState.InjuryKind = PlayerCareerState.InjuryKind.KNOCK
	if roll > 0.97:
		kind = PlayerCareerState.InjuryKind.LIGAMENT
	elif roll > 0.90:
		kind = PlayerCareerState.InjuryKind.MUSCLE_TEAR
	elif roll > 0.65:
		kind = PlayerCareerState.InjuryKind.STRAIN

	state.begin_injury(kind, career.today, _rng)
	data.is_unavailable = true

	if is_user_club:
		_push_inbox(InboxEngine.build_injury_notice(data, state, career.today))
		WorldEventLog.record_for_player(
			&"training_injury", WorldEvent.Category.INJURY,
			state.player_key, data.player_name,
			"%s picked up a %s in training and will be out for around %d days." % [
				data.player_name, state.injury_name().to_lower(), state.injury_days_remaining
			],
			-0.5,
			clampf(float(state.injury_days_remaining) / 90.0, 0.25, 0.95)
		)


## Guards the nightlife-incident roll above against filing a second one for
## the same player while an earlier one is still unresolved in the inbox.
func _has_pending_nightlife_incident(player_key: int) -> bool:
	for item: InboxItem in career.inbox:
		if item.is_resolved or item.subject_player_key != player_key:
			continue
		if String(item.payload.get("kind", "")) == "nightlife":
			return true
	return false


func _staff_quality(team: TeamData, kind: String) -> float:
	var best: float = 0.5
	for s: StaffData in team.staff:
		match kind:
			"physio":
				if s.role.to_lower().contains("physio"):
					best = maxf(best, s.physiotherapy)
			"analyst":
				if s.role.to_lower().contains("analyst"):
					best = maxf(best, s.tactical_knowledge)
			"scout":
				if s.role.to_lower().contains("scout"):
					best = maxf(best, s.judging_ability)
			_:
				best = maxf(best, s.coaching)
	return best


func _process_scouting() -> void:
	var club: TeamData = user_team()
	if club == null:
		return
	var ready: Array[ScoutReport] = ScoutingNetwork.advance_reports(career, club, career.today)
	for r: ScoutReport in ready:
		_push_inbox(InboxEngine.build_scout_report_ready(r, career.today))

	if DataLoader.league != null:
		var found: Array[ScoutReport] = ScoutingNetwork.discover_targets(
			career, club, DataLoader.league.teams, career.today, _rng
		)
		for r2: ScoutReport in found:
			var state: PlayerCareerState = career.state_for(r2.target_key())
			var age: int = 20
			var target_team: TeamData = DataLoader.get_team(r2.target_team_index)
			if target_team != null and r2.target_squad_index < target_team.squad.size():
				age = target_team.squad[r2.target_squad_index].get_age(
					career.today.year, career.today.month, career.today.day
				)
			var headline: String = "Scout report: %s" % r2.target_name
			if ScoutingNetwork.is_wonderkid(r2, age):
				headline = "Wonderkid found: %s" % r2.target_name
			_push_inbox(InboxEngine.build_simple(
				headline, r2.verdict, InboxItem.Category.SCOUTING, 0.6, career.today
			))
			if state != null:
				pass


func _process_transfer_negotiations() -> void:
	var club: TeamData = user_team()
	if club == null:
		return
	for offer: TransferOffer in career.active_offers:
		if offer.is_terminal():
			continue
		var target_team: TeamData = DataLoader.get_team(offer.player_team_index)
		if target_team == null or offer.player_squad_index >= target_team.squad.size():
			continue
		var data: PlayerData = target_team.squad[offer.player_squad_index]
		var state: PlayerCareerState = career.state_for(offer.player_key())

		if offer.club_response_due(career.today):
			if offer.is_loan():
				TransferMarket.evaluate_loan_response(
					offer, data, state, target_team, career.today, _rng
				)
			else:
				TransferMarket.evaluate_club_response(
					offer, data, state, target_team, career.today, _rng
				)
			_push_inbox(InboxEngine.build_transfer_response(offer, career.today))
		elif offer.player_response_due(career.today):
			TransferMarket.evaluate_player_terms(
				offer, data, state, club, target_team, career.today, _rng
			)
			_push_inbox(InboxEngine.build_transfer_response(offer, career.today))
			if offer.state == TransferOffer.State.COMPLETED:
				_execute_transfer(offer)


## AI clubs shop for themselves while the window is open, so the league is not
## static around the player.
func _process_ai_transfer_activity() -> void:
	if not career.transfer_window_open or DataLoader.league == null:
		return
	# One club considers one signing per day — enough movement to feel alive
	# without churning the whole league every week.
	if _rng.randf() > 0.35:
		return

	var team_count: int = DataLoader.league.teams.size()
	if team_count < 2:
		return
	var buyer_index: int = _rng.randi_range(0, team_count - 1)
	if buyer_index == career.user_team_index:
		return

	var buyer: TeamData = DataLoader.league.teams[buyer_index]
	var buyer_manager: ManagerData = ManagerLoader.get_or_assign_manager(buyer.team_name)
	var buyer_finances: ClubFinances = career.finances_for(buyer_index)
	var budget: int = buyer_finances.transfer_budget if buyer_finances != null else buyer.transfer_budget

	var seller_index: int = _rng.randi_range(0, team_count - 1)
	if seller_index == buyer_index:
		return
	var seller: TeamData = DataLoader.league.teams[seller_index]
	if seller.squad.size() <= 14:
		return
	var squad_index: int = _rng.randi_range(0, seller.squad.size() - 1)
	var target: PlayerData = seller.squad[squad_index]
	var target_state: PlayerCareerState = career.state_for_squad(seller_index, squad_index)

	var bid: int = TransferMarket.ai_should_bid(
		buyer, buyer_manager, target, target_state, seller, budget, career.today, _rng
	)
	if bid <= 0:
		return

	var ask: int = TransferMarket.asking_price(target, target_state, seller, career.today)
	if bid < ask:
		return

	# The user's own players are never sold out from under them silently — a
	# bid for one becomes an inbox decision instead.
	if seller_index == career.user_team_index:
		_push_bid_received(buyer, target, target_state, bid)
		return

	_transfer_between_ai(buyer_index, seller_index, squad_index, bid)


func _push_bid_received(buyer: TeamData, target: PlayerData, state: PlayerCareerState, bid: int) -> void:
	var item: InboxItem = InboxItem.make(
		"Offer received for %s" % target.player_name,
		"%s have offered %s for %s.\n\nThe player is currently valued at around %s." % [
			buyer.team_name, TransferMarket.format_fee(bid), target.player_name,
			TransferMarket.format_fee(TransferMarket.market_value(target, state, career.today))
		],
		InboxItem.Category.TRANSFER, career.today
	)
	item.priority = 0.85
	if state != null:
		item.with_subject_player(state.player_key, target.player_name)
	item.payload = {"incoming_bid": bid, "buyer": buyer.team_name}
	item.add_option(
		"Accept the offer", "Bank the fee and lose the player.",
		&"accept_incoming_bid", -0.01, 0.0, 0.01, 0.0
	)
	item.add_option(
		"Reject the offer", "Keep the player. He may be unsettled by the interest.",
		&"reject_incoming_bid", 0.0, -0.02, 0.0, 0.0
	)
	item.with_deadline(career.today.advanced_by(5), 1)
	_push_inbox(item)


## Moves a player between two AI clubs. Squad arrays are mutated, so every
## PlayerCareerState after the removed index shifts and must be re-keyed.
func _transfer_between_ai(buyer_index: int, seller_index: int, squad_index: int, fee: int) -> void:
	var buyer: TeamData = DataLoader.league.teams[buyer_index]
	var seller: TeamData = DataLoader.league.teams[seller_index]
	if squad_index < 0 or squad_index >= seller.squad.size():
		return
	var player: PlayerData = seller.squad[squad_index]

	var buyer_fin: ClubFinances = career.finances_for(buyer_index)
	var seller_fin: ClubFinances = career.finances_for(seller_index)
	if buyer_fin != null and not buyer_fin.can_afford_fee(fee):
		return
	if buyer_fin != null:
		buyer_fin.commit_fee(fee, 1, player.player_name, career.season_start_year)
	if seller_fin != null:
		seller_fin.receive_fee(fee, 1, player.player_name, career.season_start_year)

	_move_player(seller_index, squad_index, buyer_index)

	WorldEventLog.record(
		&"ai_transfer", WorldEvent.Category.TRANSFER,
		"%s joined %s from %s for %s." % [
			player.player_name, buyer.team_name, seller.team_name, TransferMarket.format_fee(fee)
		],
		0.0, 0.45
	)


## The single place a player changes clubs. Re-keys every PlayerCareerState on
## the selling side, because squad_index IS the identity (see ai-architect.md)
## and removing an entry silently renumbers everyone behind it.
func _move_player(from_team: int, from_squad_index: int, to_team: int) -> void:
	var source: TeamData = DataLoader.get_team(from_team)
	var dest: TeamData = DataLoader.get_team(to_team)
	if source == null or dest == null:
		return
	if from_squad_index < 0 or from_squad_index >= source.squad.size():
		return

	var player: PlayerData = source.squad[from_squad_index]
	var moving_state: PlayerCareerState = career.state_for_squad(from_team, from_squad_index)

	source.squad.remove_at(from_squad_index)
	# The lineup indexes into the squad by position, so it has to be repaired
	# in the same breath or the XI silently points at the wrong players.
	_repair_lineup_after_removal(source, from_squad_index)
	_rekey_states_after_removal(from_team, from_squad_index)

	dest.squad.append(player)
	var new_index: int = dest.squad.size() - 1
	if moving_state != null:
		career.player_states.erase(from_team * 1000 + from_squad_index)
		moving_state.team_index = to_team
		moving_state.squad_index = new_index
		moving_state.player_key = to_team * 1000 + new_index
		# Relationships are with players at the OLD club and no longer apply.
		moving_state.relationships.clear()
		moving_state.manager_trust = 0.5
		if moving_state.contract != null:
			moving_state.contract.club_name = dest.team_name
		career.player_states[moving_state.player_key] = moving_state


func _repair_lineup_after_removal(team: TeamData, removed_index: int) -> void:
	var repaired: Array[int] = []
	for idx: int in team.lineup_indices:
		if idx == removed_index:
			continue
		repaired.append(idx - 1 if idx > removed_index else idx)
	# Backfill so the XI stays eleven strong.
	var candidate: int = 0
	while repaired.size() < mini(11, team.squad.size()) and candidate < team.squad.size():
		if not repaired.has(candidate):
			repaired.append(candidate)
		candidate += 1
	team.lineup_indices = repaired
	if team.captain_index == removed_index:
		team.captain_index = -1
	elif team.captain_index > removed_index:
		team.captain_index -= 1


func _rekey_states_after_removal(team_index: int, removed_index: int) -> void:
	var team: TeamData = DataLoader.get_team(team_index)
	if team == null:
		return
	var rebuilt: Dictionary = {}
	for key: int in career.player_states:
		var st: PlayerCareerState = career.player_states[key] as PlayerCareerState
		if st == null:
			continue
		if st.team_index != team_index:
			rebuilt[key] = st
			continue
		if st.squad_index == removed_index:
			continue  # Already handled by the caller.
		if st.squad_index > removed_index:
			st.squad_index -= 1
			st.player_key = team_index * 1000 + st.squad_index
		rebuilt[st.player_key] = st
	career.player_states = rebuilt


func _execute_transfer(offer: TransferOffer) -> void:
	var club: TeamData = user_team()
	if club == null:
		return

	if offer.is_loan():
		var parent_club_name: String = DataLoader.get_team(offer.player_team_index).team_name
		_move_player(offer.player_team_index, offer.player_squad_index, career.user_team_index)
		var new_loan_index: int = club.squad.size() - 1
		var loan_state: PlayerCareerState = career.state_for_squad(career.user_team_index, new_loan_index)
		if loan_state != null and loan_state.contract != null:
			loan_state.contract.is_on_loan = true
			loan_state.contract.loan_parent_club = parent_club_name
			loan_state.contract.loan_expires = CareerDate.make(career.today.year + 1, 6, 30)
			loan_state.contract.loan_wage_subsidy = offer.loan_wage_share
		if new_loan_index < club.squad.size():
			club.squad[new_loan_index].wage_weekly = int(round(club.squad[new_loan_index].wage_weekly * offer.loan_wage_share))
		WorldEventLog.record(
			&"loan_completed", WorldEvent.Category.TRANSFER,
			"%s joined %s on loan from %s." % [
				offer.player_name, club.team_name, parent_club_name
			],
			0.4, 0.6
		)
		return

	var fin: ClubFinances = career.user_finances()
	if fin != null:
		fin.commit_fee(offer.fee_offered, offer.instalment_years, offer.player_name, career.season_start_year)
	var seller_fin: ClubFinances = career.finances_for(offer.player_team_index)
	if seller_fin != null:
		seller_fin.receive_fee(offer.fee_offered, offer.instalment_years, offer.player_name, career.season_start_year)

	_move_player(offer.player_team_index, offer.player_squad_index, career.user_team_index)

	var new_index: int = club.squad.size() - 1
	var state: PlayerCareerState = career.state_for_squad(career.user_team_index, new_index)
	if state != null:
		state.contract = ContractData.make_default(
			club.team_name, offer.wage_offered, offer.contract_years_offered, career.today
		)
		state.contract.transfer_fee_paid = offer.fee_offered
		state.contract.promised_status = offer.promised_status
		state.contract.signing_bonus = offer.signing_bonus_offered
		state.contract.release_clause = offer.release_clause_offered
	if new_index < club.squad.size():
		club.squad[new_index].wage_weekly = offer.wage_offered

	WorldEventLog.record(
		&"signing_completed", WorldEvent.Category.TRANSFER,
		"%s signed for %s for %s." % [
			offer.player_name, club.team_name, TransferMarket.format_fee(offer.fee_offered)
		],
		0.5, 0.7
	)


func _process_loan_expiries() -> void:
	if DataLoader.league == null:
		return
	for t_idx: int in range(DataLoader.league.teams.size()):
		var team: TeamData = DataLoader.league.teams[t_idx]
		for s_idx: int in range(team.squad.size() - 1, -1, -1):
			var data: PlayerData = team.squad[s_idx]
			var state: PlayerCareerState = career.state_for_squad(t_idx, s_idx)
			if state != null and state.contract != null and state.contract.is_on_loan:
				if state.contract.loan_expires != null and not career.today.is_before(state.contract.loan_expires):
					_return_loan_player(t_idx, s_idx, data, state)


func _return_loan_player(current_team_index: int, squad_index: int, data: PlayerData, state: PlayerCareerState) -> void:
	var parent_club_name: String = state.contract.loan_parent_club if state.contract != null else ""
	var parent_team_idx: int = -1
	for t_i: int in range(DataLoader.league.teams.size()):
		if DataLoader.league.teams[t_i].team_name == parent_club_name:
			parent_team_idx = t_i
			break

	state.contract.is_on_loan = false
	state.contract.loan_parent_club = ""
	state.contract.loan_expires = null
	state.contract.loan_wage_subsidy = 0.0

	if parent_team_idx >= 0:
		_move_player(current_team_index, squad_index, parent_team_idx)
	else:
		var cur_team: TeamData = DataLoader.get_team(current_team_index)
		if cur_team != null and squad_index < cur_team.squad.size():
			cur_team.squad.remove_at(squad_index)
			_repair_lineup_after_removal(cur_team, squad_index)
			_rekey_states_after_removal(current_team_index, squad_index)
			career.player_states.erase(current_team_index * 1000 + squad_index)

	WorldEventLog.record(
		&"loan_expired", WorldEvent.Category.TRANSFER,
		"%s has completed their loan spell and returned to their parent club." % data.player_name,
		0.3, 0.5
	)
	if current_team_index == career.user_team_index:
		_push_inbox(InboxEngine.build_simple(
			"Loan Spell Concluded",
			"%s has finished their loan spell and returned to %s." % [
				data.player_name, parent_club_name
			],
			InboxItem.Category.TRANSFER, 0.75, career.today
		))


## A playing-time promise that was never honoured costs more than refusing it.
func _review_promises() -> void:
	var club: TeamData = user_team()
	if club == null:
		return
	var league: CompetitionData = career.league_competition()
	var row: LeagueTableRow = league.row_for(career.user_team_index) if league != null else null
	var matches: int = row.played if row != null else 0

	for squad_index: int in range(club.squad.size()):
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if state == null or state.promise_review_date == null:
			continue
		if career.today.is_before(state.promise_review_date):
			continue

		var data: PlayerData = club.squad[squad_index]
		var share: float = state.minutes_share(matches)
		state.promise_review_date = null
		if share >= 0.45:
			state.manager_trust = clampf(state.manager_trust + 0.15, 0.0, 1.0)
			data.morale = clampf(data.morale + 0.10, 0.0, 1.0)
			WorldEventLog.record_for_player(
				&"promise_kept", WorldEvent.Category.DRESSING_ROOM,
				state.player_key, data.player_name,
				"%s is happy with the game time he was promised." % data.player_name,
				0.5, 0.4
			)
		else:
			state.manager_trust = clampf(state.manager_trust - 0.30, 0.0, 1.0)
			data.morale = clampf(data.morale - 0.22, 0.0, 1.0)
			if not state.grievances.has(&"broken_promise"):
				state.grievances.append(&"broken_promise")
			WorldEventLog.record_for_player(
				&"promise_broken", WorldEvent.Category.DRESSING_ROOM,
				state.player_key, data.player_name,
				"%s feels the manager broke a promise over playing time." % data.player_name,
				-0.7, 0.7
			)
			_push_inbox(InboxEngine.build_simple(
				"%s feels let down" % data.player_name,
				"%s was promised regular football and has not received it. The dressing room has noticed." % data.player_name,
				InboxItem.Category.PLAYER, 0.8, career.today
			))


func _run_weekly_cycle() -> void:
	var club: TeamData = user_team()
	var fin: ClubFinances = career.user_finances()
	if club == null or fin == null:
		return

	var contracts: Dictionary = {}
	for squad_index: int in range(club.squad.size()):
		var st: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if st != null and st.contract != null:
			contracts[squad_index] = st.contract

	fin.post_weekly_cycle(club, contracts, club.reputation, career.today)

	if fin.balance < 0:
		fin.spending_frozen = true
		_push_inbox(InboxEngine.build_simple(
			"The club is in the red",
			"Our balance has fallen to %s. The board have frozen transfer spending until this is corrected." % TransferMarket.format_fee(fin.balance),
			InboxItem.Category.FINANCE, 0.9, career.today
		))
	elif fin.spending_frozen and fin.balance > 0:
		fin.spending_frozen = false

	_run_weekly_morale_pass(club)
	_check_expiring_contracts(club)


func _run_weekly_morale_pass(club: TeamData) -> void:
	var league: CompetitionData = career.league_competition()
	var row: LeagueTableRow = league.row_for(career.user_team_index) if league != null else null
	var matches: int = row.played if row != null else 0
	var form: float = row.form_factor() if row != null else 0.5
	var harmony: float = career.squad_morale(club)
	var median_wage: int = _median_wage(club)

	for squad_index: int in range(club.squad.size()):
		var data: PlayerData = club.squad[squad_index]
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if state == null:
			continue
		var before: float = data.morale
		var drivers: Array[MoraleEngine.Driver] = MoraleEngine.evaluate_drivers(
			data, state, matches, form, harmony, median_wage
		)
		MoraleEngine.apply_drivers(data, drivers)

		# Crossing into genuine unhappiness raises a grievance once, not weekly.
		if before >= 0.35 and data.morale < 0.35 and not state.grievances.has(&"playing_time"):
			state.grievances.append(&"playing_time")
			_push_inbox(InboxEngine.build_playing_time_complaint(data, state, career.today))
			WorldEventLog.record_for_player(
				&"player_unhappy", WorldEvent.Category.DRESSING_ROOM,
				state.player_key, data.player_name,
				"%s is unhappy: %s" % [data.player_name, MoraleEngine.describe_drivers(drivers)],
				-0.5, 0.55
			)


func _median_wage(club: TeamData) -> int:
	if club.squad.is_empty():
		return 1
	var wages: Array[int] = []
	for p: PlayerData in club.squad:
		wages.append(p.wage_weekly)
	wages.sort()
	return wages[wages.size() / 2]


func _check_expiring_contracts(club: TeamData) -> void:
	for squad_index: int in range(club.squad.size()):
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if state == null or state.contract == null:
			continue
		if not state.contract.is_in_final_six_months(career.today):
			continue
		if state.wants_new_contract:
			continue
		state.wants_new_contract = true
		_push_inbox(InboxEngine.build_contract_expiry_warning(
			club.squad[squad_index], state, career.today
		))


## --- Fixtures and results -------------------------------------------------------------

## Quick-sims the user's next fixture through the existing QuickSimEngine.
func simulate_next_fixture() -> FixtureData:
	var fixture: FixtureData = career.next_user_fixture()
	if fixture == null:
		return null
	_simulate_fixture(fixture, true)
	_advance_cup_rounds()
	save_career()
	return fixture


func _simulate_ai_fixture(fixture: FixtureData) -> void:
	_simulate_fixture(fixture, false)


func _simulate_fixture(fixture: FixtureData, is_user: bool) -> void:
	var home: TeamData = DataLoader.get_team(fixture.home_team_index)
	var away: TeamData = DataLoader.get_team(fixture.away_team_index)
	if home == null or away == null:
		return
	var home_mgr: ManagerData = ManagerLoader.get_or_assign_manager(home.team_name)
	var away_mgr: ManagerData = ManagerLoader.get_or_assign_manager(away.team_name)
	var ref: RefereeData = RefereeLoader.get_or_assign_referee(home.team_name, away.team_name)

	var result: QuickSimEngine.QuickSimResult = QuickSimEngine.simulate_match(
		home, away, home_mgr, away_mgr, ref, home.lineup_indices, away.lineup_indices
	)
	fixture.played = true
	fixture.home_score = result.home_score
	fixture.away_score = result.away_score
	# QuickSimEngine produces real per-player ratings and events; threading
	# them into progression is what makes a simulated match develop players
	# and move reputations the same way a played one does.
	_apply_fixture_result(fixture, result.player_events, result.player_ratings)

	if is_user:
		GameEvents.career_result_recorded.emit(result.home_score, result.away_score)


## The one place a played fixture updates the world: table, finances, player
## records, morale, board confidence and the event log.
func _apply_fixture_result(
	fixture: FixtureData,
	player_events: Dictionary = {},
	player_ratings: Dictionary = {}
) -> void:
	var comp: CompetitionData = _competition_of(fixture)
	if comp != null:
		comp.record_result(fixture, _rng)

	var home: TeamData = DataLoader.get_team(fixture.home_team_index)
	var away: TeamData = DataLoader.get_team(fixture.away_team_index)
	if home == null or away == null:
		return

	var home_mgr: ManagerData = ManagerLoader.get_or_assign_manager(home.team_name)
	var away_mgr: ManagerData = ManagerLoader.get_or_assign_manager(away.team_name)
	var ref: RefereeData = RefereeLoader.get_or_assign_referee(home.team_name, away.team_name)

	# Reuse the existing progression engine rather than duplicating reputation,
	# board-confidence and referee drift maths that already live there.
	CareerProgressionEngine.process_matchday_progression(
		home, away, home_mgr, away_mgr, ref,
		fixture.home_score, fixture.away_score, 0, 0, 0, 0,
		player_events, player_ratings
	)

	_record_player_match_state(fixture.home_team_index, fixture, true, player_ratings)
	_record_player_match_state(fixture.away_team_index, fixture, false, player_ratings)

	if fixture.involves(career.user_team_index):
		_apply_user_result(fixture)


func _record_player_match_state(
	team_index: int,
	fixture: FixtureData,
	is_home: bool,
	player_ratings: Dictionary = {}
) -> void:
	var team: TeamData = DataLoader.get_team(team_index)
	if team == null:
		return
	var scored: int = fixture.home_score if is_home else fixture.away_score
	var conceded: int = fixture.away_score if is_home else fixture.home_score
	var goal_diff: int = scored - conceded

	for slot: int in range(team.lineup_indices.size()):
		var squad_index: int = team.lineup_indices[slot]
		if squad_index < 0 or squad_index >= team.squad.size():
			continue
		var state: PlayerCareerState = career.state_for_squad(team_index, squad_index)
		var data: PlayerData = team.squad[squad_index]
		if state == null:
			continue
		if not state.is_available():
			continue
		# QuickSimEngine keys ratings by the match SIDE (0/1), not the league
		# team index, so the lookup has to use the side this fixture put the
		# club on rather than team_index.
		var side: int = 0 if is_home else 1
		var rating: float = float(player_ratings.get(side * 1000 + squad_index, data.last_match_rating))
		state.record_appearance(90, rating, 0, 0)
		MoraleEngine.apply_result_reaction(data, true, goal_diff, rating)
		var age: int = data.get_age(career.today.year, career.today.month, career.today.day)
		MoraleEngine.apply_reputation_drift(data, rating, age)

	# Everyone who did not feature still reacts to the result.
	for squad_index2: int in range(team.squad.size()):
		if team.lineup_indices.has(squad_index2):
			continue
		MoraleEngine.apply_result_reaction(team.squad[squad_index2], false, goal_diff, 0.0)


func _apply_user_result(fixture: FixtureData) -> void:
	var league: CompetitionData = career.league_competition()
	var position: int = league.position_of(career.user_team_index) if league != null else 1
	var team_count: int = league.table.size() if league != null else 1

	var gf: int = fixture.goals_for(career.user_team_index)
	var ga: int = fixture.goals_against(career.user_team_index)
	var won: bool = gf > ga
	var drew: bool = gf == ga

	var opponent_index: int = fixture.opponent_of(career.user_team_index)
	var opponent: TeamData = DataLoader.get_team(opponent_index)
	var club: TeamData = user_team()
	var was_upset: bool = false
	if opponent != null and club != null:
		was_upset = absf(opponent.reputation - club.reputation) >= 0.18

	if career.board != null:
		career.board.apply_result(position, team_count, won, drew, was_upset)
		if career.board.confidence < BoardState.SACK_THRESHOLD + 0.06 and _rng.randf() < 0.5:
			_push_inbox(InboxEngine.build_board_warning(
				career.board, club.team_name if club != null else "", position, career.today
			))

	if career.profile != null:
		career.profile.record_result(gf, ga)
		# Managing matches is itself experience.
		career.profile.train_attribute(&"tactical_knowledge", 6.0)
		career.profile.train_attribute(&"man_management", 4.0)
		if won:
			career.profile.reputation = clampf(career.profile.reputation + 0.004, 0.05, 0.99)
		elif not drew:
			career.profile.reputation = clampf(career.profile.reputation - 0.003, 0.05, 0.99)

	# Gate receipts on a home game.
	var fin: ClubFinances = career.user_finances()
	if fin != null and fixture.is_home_for(career.user_team_index) and club != null:
		var row: LeagueTableRow = league.row_for(career.user_team_index) if league != null else null
		var form: float = row.form_factor() if row != null else 0.5
		fixture.attendance = int(round(float(fin.stadium_capacity) * clampf(
			ClubFinances.BASE_ATTENDANCE_RATE + club.reputation * 0.30 + form * 0.10, 0.25, 1.0
		)))
		fin.book_matchday(club.reputation, form)

	var sentiment: float = 0.6 if won else (-0.6 if not drew else 0.0)
	WorldEventLog.record(
		&"match_result", WorldEvent.Category.MATCH,
		"%s %d-%d %s" % [
			DataLoader.get_team(fixture.home_team_index).team_name,
			fixture.home_score, fixture.away_score,
			DataLoader.get_team(fixture.away_team_index).team_name
		],
		sentiment, 0.5
	)


func _competition_of(fixture: FixtureData) -> CompetitionData:
	for comp: CompetitionData in career.competitions:
		if comp.fixtures.has(fixture):
			return comp
	return null


## Draws the next round of any cup whose current round has finished.
func _advance_cup_rounds() -> void:
	for comp: CompetitionData in career.competitions:
		if comp.kind != CompetitionData.Kind.KNOCKOUT_CUP:
			continue
		if comp.is_complete() or not comp.cup_round_finished():
			continue
		comp.current_round += 1
		comp.draw_cup_round(career.today.advanced_by(21), _rng)
		_tag_user_fixtures()


## --- Season rollover --------------------------------------------------------------------

func _check_season_rollover() -> bool:
	var league: CompetitionData = career.league_competition()
	if league == null or not league.is_complete():
		return false
	# Roll over on a real season-end DATE, not a bare month comparison. The
	# earlier `month < 6` guard was incoherent across league sizes: an 8-club
	# league finishing in November read month 11 and rolled over on the spot,
	# while a 20-club league finishing in April read month 4 and blocked. An
	# explicit date is the same rule for every league.
	var season_end: CareerDate = CareerDate.make(
		_season_end_year(), SEASON_END_MONTH, SEASON_END_DAY
	)
	if career.today.is_before(season_end):
		return false
	_run_season_end()
	return true


## The calendar year the CURRENT season ends in. A season starting in July of
## year N ends in June of N+1.
func _season_end_year() -> int:
	return career.season_start_year + 1


func _run_season_end() -> void:
	var league: CompetitionData = career.league_competition()
	var position: int = league.position_of(career.user_team_index) if league != null else 1
	var team_count: int = league.table.size() if league != null else 1
	var club: TeamData = user_team()

	# Prize money for everyone.
	if league != null:
		var ordered: Array[LeagueTableRow] = league.sorted_table()
		for i: int in range(ordered.size()):
			var fin: ClubFinances = career.finances_for(ordered[i].team_index)
			if fin != null:
				fin.record_income(
					ClubFinances.Line.PRIZE_MONEY,
					ClubFinances.prize_money_for_position(i + 1, team_count)
				)
				fin.settle_due_instalments(career.season_start_year)

	# Board verdict against the expectation set at hire.
	if career.board != null:
		var target: int = career.board.target_position(team_count)
		var met: bool = position <= target
		career.board.confidence = clampf(
			career.board.confidence + (0.15 if met else -0.20), 0.0, 1.0
		)
		var verdict: String = "The board are satisfied with %s place." % _ordinal(position) if met \
			else "The board expected better than %s place." % _ordinal(position)
		_push_inbox(InboxEngine.build_simple(
			"End of season review", verdict, InboxItem.Category.BOARD, 0.95, career.today
		))
		if career.board.should_sack() or (not met and career.board.confidence < BoardState.SACK_THRESHOLD):
			_execute_sacking()
			return

	if career.profile != null:
		career.profile.season_history.append({
			"year": career.season_start_year,
			"club": club.team_name if club != null else "",
			"position": position,
			"points": league.row_for(career.user_team_index).points if league != null else 0,
		})
		if position == 1:
			career.profile.trophies_won += 1
			career.profile.reputation = clampf(career.profile.reputation + 0.08, 0.05, 0.99)

	career.season_archive.append({
		"year": career.season_start_year,
		"position": position,
		"club": club.team_name if club != null else "",
	})

	# Promotion, Relegation & Continental Qualification across tiers
	_apply_promotion_relegation()

	GameEvents.career_season_ended.emit(career.season_start_year, position)
	_start_new_season()


func _apply_promotion_relegation() -> void:
	var tier_comps: Dictionary = {}
	for c: CompetitionData in career.competitions:
		if c.kind == CompetitionData.Kind.LEAGUE:
			if not tier_comps.has(c.tier):
				var arr: Array[CompetitionData] = []
				tier_comps[c.tier] = arr
			(tier_comps[c.tier] as Array[CompetitionData]).append(c)

	var tiers: Array = tier_comps.keys()
	tiers.sort()
	if tiers.is_empty():
		return

	var club: TeamData = user_team()

	if tiers.size() >= 2:
		for i: int in range(tiers.size() - 1):
			var upper_tier: int = int(tiers[i])
			var lower_tier: int = int(tiers[i + 1])
			var upper_list: Array[CompetitionData] = tier_comps[upper_tier]
			var lower_list: Array[CompetitionData] = tier_comps[lower_tier]

			var relegated_indices: Array[int] = []
			for u_comp: CompetitionData in upper_list:
				var u_table: Array[LeagueTableRow] = u_comp.sorted_table()
				var r_count: int = mini(u_comp.relegation_slots, u_table.size())
				for r_i: int in range(u_table.size() - r_count, u_table.size()):
					relegated_indices.append(u_table[r_i].team_index)

			var promoted_indices: Array[int] = []
			for l_comp: CompetitionData in lower_list:
				var l_table: Array[LeagueTableRow] = l_comp.sorted_table()
				var p_count: int = mini(l_comp.promotion_slots, l_table.size())
				for p_i: int in range(p_count):
					promoted_indices.append(l_table[p_i].team_index)

			if promoted_indices.has(career.user_team_index):
				if career.profile != null:
					career.profile.promotions += 1
					career.profile.reputation = clampf(career.profile.reputation + 0.10, 0.05, 0.99)
				_push_inbox(InboxEngine.build_simple(
					"PROMOTION CELEBRATIONS!",
					"Congratulations! You have led %s to promotion!" % (club.team_name if club != null else "your club"),
					InboxItem.Category.BOARD, 1.0, career.today
				))
			elif relegated_indices.has(career.user_team_index):
				if career.profile != null:
					career.profile.relegations += 1
					career.profile.reputation = clampf(career.profile.reputation - 0.12, 0.05, 0.99)
				_push_inbox(InboxEngine.build_simple(
					"RELEGATION HEARTBREAK",
					"%s have suffered relegation. The board expect an immediate return next season." % (club.team_name if club != null else "Your club"),
					InboxItem.Category.BOARD, 1.0, career.today
				))

			var u_idx: int = upper_tier - 1
			var l_idx: int = lower_tier - 1
			if u_idx < career.tier_indices.size() and l_idx < career.tier_indices.size():
				var u_roster: Array = career.tier_indices[u_idx]
				var l_roster: Array = career.tier_indices[l_idx]
				for rel: int in relegated_indices:
					u_roster.erase(rel)
					l_roster.append(rel)
				for promo: int in promoted_indices:
					l_roster.erase(promo)
					u_roster.append(promo)

	career.tier_1_indices = _get_tier_team_indices(1)
	career.tier_2_indices = _get_tier_team_indices(2)

	# Continental qualification from Tier 1
	var t1_comp: CompetitionData = null
	for c_t1: CompetitionData in career.competitions:
		if c_t1.kind == CompetitionData.Kind.LEAGUE and c_t1.tier == 1:
			t1_comp = c_t1
			break
	if t1_comp != null:
		var t1_table: Array[LeagueTableRow] = t1_comp.sorted_table()
		var new_cont: Array[int] = []
		for i_q: int in range(mini(4, t1_table.size())):
			new_cont.append(t1_table[i_q].team_index)
		career.continental_indices = new_cont
		if new_cont.has(career.user_team_index):
			_push_inbox(InboxEngine.build_simple(
				"European Champions Cup Qualification",
				"Your league finish secures European football for %s next season!" % (club.team_name if club != null else "your club"),
				InboxItem.Category.BOARD, 0.95, career.today
			))


func _start_new_season() -> void:
	career.season_start_year += 1
	career.today = CareerDate.make(career.season_start_year, SEASON_START_MONTH, SEASON_START_DAY)
	career.phase = CareerSaveData.Phase.PRE_SEASON

	# Age every player in the league, then reset season records.
	if DataLoader.league != null:
		for team_index: int in range(DataLoader.league.teams.size()):
			var team: TeamData = DataLoader.league.teams[team_index]
			for squad_index: int in range(team.squad.size()):
				var data: PlayerData = team.squad[squad_index]
				var state: PlayerCareerState = career.state_for_squad(team_index, squad_index)
				if state == null:
					continue
				var age: int = data.get_age(career.today.year, career.today.month, career.today.day)
				var note: String = PlayerDevelopmentEngine.apply_seasonal_ageing(data, state, age, _rng)
				if note != "" and team_index == career.user_team_index:
					WorldEventLog.record_for_player(
						&"ageing", WorldEvent.Category.TRAINING,
						state.player_key, data.player_name, note, -0.3, 0.35
					)
				state.reset_season_record()
				if state.contract != null:
					state.contract.club_name = team.team_name

	for fin_key: int in career.club_finances:
		var fin: ClubFinances = career.club_finances[fin_key] as ClubFinances
		if fin != null:
			fin.reset_season_ledger()

	_run_youth_intake()
	_build_competitions()

	if career.board != null:
		career.board.matches_below_threshold = 0

	_push_inbox(InboxEngine.build_simple(
		"A new season begins",
		"Pre-season for %s is underway." % career.season_label(),
		InboxItem.Category.BOARD, 0.7, career.today
	))
	save_career()


func _run_youth_intake() -> void:
	var club: TeamData = user_team()
	if club == null or career.profile == null:
		return
	var cohort: Array[PlayerData] = YouthAcademy.generate_intake(
		club, career.board, career.profile.attribute(&"youth_development"), career.today, _rng
	)
	if cohort.is_empty():
		return

	var states: Array[PlayerCareerState] = []
	for data: PlayerData in cohort:
		club.squad.append(data)
		var squad_index: int = club.squad.size() - 1
		var age: int = data.get_age(career.today.year, career.today.month, career.today.day)
		var potential: int = PlayerDevelopmentEngine.roll_potential(data, age, _rng)
		var state: PlayerCareerState = PlayerCareerState.make_for(
			data, career.user_team_index, squad_index, potential, career.today
		)
		state.is_youth_player = true
		state.contract.club_name = club.team_name
		career.player_states[state.player_key] = state
		states.append(state)

	var summary: String = YouthAcademy.intake_report(
		club.team_name, cohort, states, _staff_quality(club, "scout")
	)
	_push_inbox(InboxEngine.build_youth_intake(club.team_name, summary, career.today))
	WorldEventLog.record(
		&"youth_intake", WorldEvent.Category.YOUTH, summary, 0.3, 0.6
	)


func _execute_sacking() -> void:
	var club: TeamData = user_team()
	var club_name: String = club.team_name if club != null else ""
	career.is_sacked = true
	career.unemployed = true
	if career.profile != null:
		career.profile.times_sacked += 1
		career.profile.current_club = ""
		career.profile.reputation = clampf(career.profile.reputation - 0.10, 0.05, 0.99)
		career.profile.unemployed_since = career.today.copy()
		if career.profile.tactical != null:
			career.profile.tactical.current_team = ""
	WorldEventLog.record(
		&"manager_sacked", WorldEvent.Category.BOARD,
		"%s was dismissed by %s." % [
			career.profile.manager_name if career.profile != null else "The manager", club_name
		],
		-0.9, 1.0
	)
	GameEvents.career_manager_sacked.emit(club_name, "Board confidence collapsed.")
	save_career()


## --- Inbox plumbing ---------------------------------------------------------------------

func _push_inbox(item: InboxItem) -> void:
	if career == null or item == null:
		return
	career.inbox.append(item)
	while career.inbox.size() > 200:
		career.inbox.remove_at(0)
	_emit_inbox_changed()


func _emit_inbox_changed() -> void:
	if career == null:
		return
	GameEvents.career_inbox_changed.emit(
		career.unread_inbox_count(), career.pending_decision_count()
	)


## Answers an inbox decision. The UI calls only this — never InboxEngine
## directly — so the world event and the save both happen.
func resolve_inbox_item(item: InboxItem, option_index: int) -> void:
	if career == null or item == null:
		return
	var event: WorldEvent = InboxEngine.resolve(career, item, option_index, user_team(), career.today)
	if event != null:
		WorldEventLog.log_event(event)
		_handle_structural_inbox_action(item, option_index)
	_emit_inbox_changed()


## Effects that need CareerManager's reach (moving players between clubs,
## touching finances) rather than the pure deltas InboxEngine applies.
func _handle_structural_inbox_action(item: InboxItem, option_index: int) -> void:
	var option: InboxItem.Option = item.get_option(option_index)
	if option == null:
		return
	match option.action_tag:
		&"accept_incoming_bid":
			var bid: int = int(item.payload.get("incoming_bid", 0))
			var state: PlayerCareerState = career.state_for(item.subject_player_key)
			if state != null and bid > 0:
				var fin: ClubFinances = career.user_finances()
				if fin != null:
					fin.receive_fee(bid, 1, item.subject_player_name, career.season_start_year)
				# The buying club is whoever bid; without a stored index the
				# player simply departs the league roster the user manages.
				_release_player(state)
		&"reject_incoming_bid":
			pass
		_:
			pass


## Removes a player from the user's squad, keeping every index consistent.
func _release_player(state: PlayerCareerState) -> void:
	var club: TeamData = user_team()
	if club == null or state == null:
		return
	var squad_index: int = state.squad_index
	if squad_index < 0 or squad_index >= club.squad.size():
		return
	var name_str: String = club.squad[squad_index].player_name
	club.squad.remove_at(squad_index)
	career.player_states.erase(state.player_key)
	_repair_lineup_after_removal(club, squad_index)
	_rekey_states_after_removal(career.user_team_index, squad_index)
	WorldEventLog.record(
		&"player_departed", WorldEvent.Category.TRANSFER,
		"%s left %s." % [name_str, club.team_name], -0.2, 0.5
	)


## Restored inbox items carry their text and resolved state, but NOT their
## options (see CareerSerializer._inbox_from_dict — persisting behaviour-
## defining deltas would let a hand-edited save invent arbitrary effects).
## Anything still awaiting a decision is rebuilt here from its category so the
## player is never left with an unanswerable item.
func _rehydrate_inbox() -> void:
	if career == null:
		return
	var club: TeamData = user_team()
	for item: InboxItem in career.inbox:
		if item.is_resolved or item.option_count() > 0:
			continue
		var state: PlayerCareerState = career.state_for(item.subject_player_key)
		match item.category:
			InboxItem.Category.PLAYER:
				if state != null and club != null \
						and state.squad_index >= 0 and state.squad_index < club.squad.size():
					var rebuilt: InboxItem
					if String(item.payload.get("kind", "")) == "nightlife":
						rebuilt = InboxEngine.build_nightlife_incident(
							club.squad[state.squad_index], state, item.received
						)
					else:
						rebuilt = InboxEngine.build_playing_time_complaint(
							club.squad[state.squad_index], state, item.received
						)
					item.options = rebuilt.options
					item.escalation_option = rebuilt.escalation_option
			InboxItem.Category.CONTRACT:
				if state != null and club != null \
						and state.squad_index >= 0 and state.squad_index < club.squad.size():
					var rebuilt2: InboxItem = InboxEngine.build_contract_expiry_warning(
						club.squad[state.squad_index], state, item.received
					)
					item.options = rebuilt2.options
					item.escalation_option = rebuilt2.escalation_option
			InboxItem.Category.BOARD:
				if career.board != null:
					var league: CompetitionData = career.league_competition()
					var pos: int = league.position_of(career.user_team_index) if league != null else 1
					var rebuilt3: InboxItem = InboxEngine.build_board_warning(
						career.board, club.team_name if club != null else "", pos, item.received
					)
					item.options = rebuilt3.options
					item.escalation_option = rebuilt3.escalation_option
			_:
				# A notification with no options needs nothing rebuilt.
				pass
	_emit_inbox_changed()


## --- Manager actions (called by the career UI) ---------------------------------------------

## Adds or removes a player from the tracked shortlist.
func toggle_shortlist(player_key: int) -> void:
	if career == null:
		return
	if career.shortlist_keys.has(player_key):
		career.shortlist_keys.erase(player_key)
	else:
		career.shortlist_keys.append(player_key)
	save_career()


## Puts a scout on a target, creating the report if this is the first look.
## Picks the least-loaded scout so one does not silently absorb every target.
func scout_player(team_index: int, squad_index: int) -> ScoutReport:
	if career == null:
		return null
	var target_team: TeamData = DataLoader.get_team(team_index)
	var club_node: TeamData = user_team()
	if target_team == null or club_node == null or squad_index >= target_team.squad.size():
		return null

	var data: PlayerData = target_team.squad[squad_index]
	var state: PlayerCareerState = career.state_for_squad(team_index, squad_index)
	var report: ScoutReport = ScoutingNetwork.ensure_report(
		career, team_index, squad_index, data, state, target_team.team_name, career.today, _rng
	)

	var scouts: Array[StaffData] = ScoutingNetwork.available_scouts(club_node)
	if scouts.is_empty():
		return report
	var best: StaffData = scouts[0]
	var lightest: int = ScoutingNetwork.caseload(career, best.staff_name)
	for s: StaffData in scouts:
		var load: int = ScoutingNetwork.caseload(career, s.staff_name)
		if load < lightest:
			lightest = load
			best = s
	ScoutingNetwork.assign_scout(report, best.staff_name)
	save_career()
	return report


## Opens a bid. The selling club answers after TransferOffer.CLUB_RESPONSE_DAYS,
## via _process_transfer_negotiations() on a later day — never in this frame,
## so a negotiation always takes real calendar time.
func submit_transfer_bid(team_index: int, squad_index: int, fee: int) -> TransferOffer:
	if career == null or not career.transfer_window_open:
		return null
	var target_team: TeamData = DataLoader.get_team(team_index)
	var club_node: TeamData = user_team()
	var finances: ClubFinances = career.user_finances()
	if target_team == null or club_node == null or squad_index >= target_team.squad.size():
		return null
	if finances != null and not finances.can_afford_fee(fee):
		_push_inbox(InboxEngine.build_simple(
			"Bid blocked",
			"The transfer budget cannot cover a fee of %s." % TransferMarket.format_fee(fee),
			InboxItem.Category.FINANCE, 0.7, career.today
		))
		return null

	var data: PlayerData = target_team.squad[squad_index]
	var offer: TransferOffer = TransferOffer.make(
		club_node.team_name, target_team.team_name, data.player_name,
		team_index, squad_index, TransferOffer.Kind.PERMANENT, career.today
	)
	offer.initiated_by_user = true
	offer.fee_offered = fee
	offer.advance_to(TransferOffer.State.BID_SUBMITTED, career.today,
		"Your offer of %s has been submitted to %s." % [
			TransferMarket.format_fee(fee), target_team.team_name
		])
	career.active_offers.append(offer)
	save_career()
	return offer


## Improves a live bid and re-submits it, restarting the response clock.
func raise_transfer_bid(offer: TransferOffer, new_fee: int) -> void:
	if career == null or offer == null:
		return
	var finances: ClubFinances = career.user_finances()
	if finances != null and not finances.can_afford_fee(new_fee):
		_push_inbox(InboxEngine.build_simple(
			"Bid blocked",
			"The transfer budget cannot cover a fee of %s." % TransferMarket.format_fee(new_fee),
			InboxItem.Category.FINANCE, 0.7, career.today
		))
		return
	offer.fee_offered = new_fee
	offer.advance_to(TransferOffer.State.BID_SUBMITTED, career.today,
		"Your improved offer of %s has been submitted." % TransferMarket.format_fee(new_fee))
	save_career()


## Opens (or improves) personal terms once a fee is agreed. Passing a wage of
## -1 offers the player's own asking wage, which is the sensible default.
func offer_personal_terms(offer: TransferOffer, wage: int = -1) -> void:
	if career == null or offer == null:
		return
	var target_team: TeamData = DataLoader.get_team(offer.player_team_index)
	var club_node: TeamData = user_team()
	if target_team == null or club_node == null or offer.player_squad_index >= target_team.squad.size():
		return
	var data: PlayerData = target_team.squad[offer.player_squad_index]
	var state: PlayerCareerState = career.state_for(offer.player_key())

	var proposed: int = wage
	if proposed < 0:
		proposed = TransferMarket.wage_demand(data, state, club_node, career.today)

	# The recurring wage cap is checked against the CURRENT bill, not the cash
	# balance — a club can be rich and still have no wage room.
	var finances: ClubFinances = career.user_finances()
	if finances != null and not finances.can_afford_wage(proposed, club_node.get_weekly_payroll()):
		_push_inbox(InboxEngine.build_simple(
			"Wage budget exceeded",
			"Offering %s per week to %s would breach the wage budget." % [
				TransferMarket.format_fee(proposed), offer.player_name
			],
			InboxItem.Category.FINANCE, 0.7, career.today
		))
		return

	offer.wage_offered = proposed
	offer.advance_to(TransferOffer.State.TERMS_OFFERED, career.today,
		"Personal terms of %s per week have been put to %s." % [
			TransferMarket.format_fee(proposed), offer.player_name
		])
	save_career()


func withdraw_offer(offer: TransferOffer) -> void:
	if career == null or offer == null:
		return
	offer.advance_to(TransferOffer.State.WITHDRAWN, career.today, "You withdrew your interest.")
	career.active_offers.erase(offer)
	save_career()


## Files a request with the board and resolves it immediately — a board does
## not need days to say no. Affordability is a real read of the club's books,
## so a broke club is refused however well the manager is doing.
func file_board_request(kind: BoardState.RequestKind) -> void:
	if career == null or career.board == null:
		return
	if career.board.has_recent_request(kind, career.today):
		return

	var finances: ClubFinances = career.user_finances()
	var affordability: float = 0.5
	if finances != null and finances.wage_budget_weekly > 0:
		affordability = clampf(
			float(finances.balance) / maxf(float(finances.wage_budget_weekly) * 40.0, 1.0), 0.0, 1.0
		)

	var amount: int = _request_amount(kind, finances)
	career.board.file_request(kind, amount, career.today)
	var request: Dictionary = career.board.pending_requests[career.board.pending_requests.size() - 1]
	var verdict: Dictionary = career.board.evaluate_request(request, affordability, _rng)
	var granted: float = float(verdict.get("granted_fraction", 0.0))
	var status: String = String(verdict.get("status", "rejected"))

	var message: String = _apply_request_verdict(kind, granted, status, amount, finances)
	verdict["response"] = message
	career.board.resolve_request(career.board.pending_requests.size() - 1, verdict)

	_push_inbox(InboxEngine.build_simple(
		"Board response: %s" % BoardState.REQUEST_NAMES[int(kind)],
		message, InboxItem.Category.BOARD, 0.75, career.today
	))
	WorldEventLog.record(
		&"board_request", WorldEvent.Category.BOARD, message,
		0.4 if status == "approved" else (-0.3 if status == "rejected" else 0.0), 0.5
	)
	save_career()


func _request_amount(kind: BoardState.RequestKind, finances: ClubFinances) -> int:
	match kind:
		BoardState.RequestKind.TRANSFER_BUDGET:
			return maxi(int(round(float(finances.transfer_budget) * 0.35)) if finances != null else 0, 500000)
		BoardState.RequestKind.WAGE_BUDGET:
			return maxi(int(round(float(finances.wage_budget_weekly) * 0.20)) if finances != null else 0, 5000)
		_:
			return 1


func _apply_request_verdict(
	kind: BoardState.RequestKind,
	granted: float,
	status: String,
	amount: int,
	finances: ClubFinances
) -> String:
	if status == "rejected" or granted <= 0.0:
		return "The board have rejected your request to %s." % 			BoardState.REQUEST_NAMES[int(kind)].to_lower()

	var board: BoardState = career.board
	match kind:
		BoardState.RequestKind.TRANSFER_BUDGET:
			var given: int = int(round(float(amount) * granted))
			if finances != null:
				finances.transfer_budget += given
			return "The board have released a further %s for transfers." % TransferMarket.format_fee(given)
		BoardState.RequestKind.WAGE_BUDGET:
			var given_wage: int = int(round(float(amount) * granted))
			if finances != null:
				finances.wage_budget_weekly += given_wage
			return "The wage budget has been increased by %s per week." % TransferMarket.format_fee(given_wage)
		BoardState.RequestKind.TRAINING_FACILITIES:
			board.training_facilities = clampi(board.training_facilities + 1, 1, 5)
			return "Training facilities will be upgraded to level %d." % board.training_facilities
		BoardState.RequestKind.YOUTH_FACILITIES:
			board.youth_facilities = clampi(board.youth_facilities + 1, 1, 5)
			return "Youth facilities will be upgraded to level %d." % board.youth_facilities
		BoardState.RequestKind.SCOUTING_NETWORK:
			board.scouting_range = clampi(board.scouting_range + 1, 1, 5)
			return "The scouting network has been expanded to level %d." % board.scouting_range
		BoardState.RequestKind.MEDICAL_FACILITIES:
			board.medical_facility = clampi(board.medical_facility + 1, 1, 5)
			return "The medical centre will be upgraded to level %d." % board.medical_facility
		BoardState.RequestKind.STADIUM_EXPANSION:
			var added: int = int(round(float(board.stadium_capacity) * 0.20 * granted))
			board.stadium_capacity += added
			if finances != null:
				finances.stadium_capacity = board.stadium_capacity
			return "The stadium will be expanded by %d seats." % added
		_:
			return "The board have approved your request."


func _fixture_label(fixture: FixtureData) -> String:
	var home: TeamData = DataLoader.get_team(fixture.home_team_index)
	var away: TeamData = DataLoader.get_team(fixture.away_team_index)
	return "%s v %s" % [
		home.team_name if home != null else "?",
		away.team_name if away != null else "?"
	]


func _ordinal(n: int) -> String:
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


## --- Active Takeover Subsystem ---------------------------------------------------

func _process_takeover_tick() -> void:
	if career == null or career.board == null:
		return
	var b: BoardState = career.board
	if b.is_takeover_active():
		b.takeover_days_remaining -= 1
		if b.takeover_stage == BoardState.TakeoverStage.RUMOURED and b.takeover_days_remaining <= 0:
			b.advance_takeover_to_due_diligence(21, 15000000)
			_push_inbox(InboxEngine.build_simple(
				"TAKEOVER UPDATE: Due Diligence Begins",
				"The %s consortium has entered formal due diligence to acquire %s. A temporary transfer embargo is in effect during the audit." % [
					b.takeover_consortium_name, b.club_name
				],
				InboxItem.Category.BOARD, 0.95, career.today
			))
		elif b.takeover_stage == BoardState.TakeoverStage.IN_PROGRESS and b.takeover_days_remaining <= 0:
			if _rng.randf() < 0.75:
				var cash: int = b.takeover_cash_injection
				b.complete_takeover(b.takeover_consortium_name)
				var fin: ClubFinances = career.user_finances()
				if fin != null:
					fin.transfer_budget += cash
					fin.record_income(ClubFinances.Line.INVESTOR_INJECTION, cash)
				_push_inbox(InboxEngine.build_simple(
					"TAKEOVER COMPLETED!",
					"The takeover by %s has completed! The transfer embargo has been lifted, and a £%s war chest has been injected." % [
						b.owner_name, TransferMarket.format_fee(cash)
					],
					InboxItem.Category.BOARD, 1.0, career.today
				))
			else:
				b.collapse_takeover()
				_push_inbox(InboxEngine.build_simple(
					"Takeover Talks Collapse",
					"Talks between the board and %s have broken down. The existing ownership remains and the transfer embargo is lifted." % b.takeover_consortium_name,
					InboxItem.Category.BOARD, 0.85, career.today
				))
	elif _rng.randf() < 0.002:
		var consortiums: Array[String] = [
			"Nordic Capital Partners", "Apex Sports Consortium", "Redstone Global Holdings", "Monaco Atlantic Group"
		]
		var c_name: String = consortiums[_rng.randi_range(0, consortiums.size() - 1)]
		b.start_takeover_process(c_name)
		_push_inbox(InboxEngine.build_simple(
			"Takeover Speculation",
			"Financial media report that %s is preparing a buyout offer for %s." % [
				c_name, b.club_name
			],
			InboxItem.Category.BOARD, 0.75, career.today
		))


## --- International Breaks Subsystem ----------------------------------------------

func is_international_break(date: CareerDate) -> bool:
	if date == null:
		return false
	var m: int = date.month
	var d: int = date.day
	if m == 9 and d >= 5 and d <= 15:
		return true
	if m == 10 and d >= 8 and d <= 18:
		return true
	if m == 11 and d >= 10 and d <= 20:
		return true
	if m == 3 and d >= 18 and d <= 28:
		return true
	return false


func _process_international_duty() -> void:
	var today: CareerDate = career.today
	var m: int = today.month
	var d: int = today.day

	var is_start: bool = (m == 9 and d == 5) or (m == 10 and d == 8) or (m == 11 and d == 10) or (m == 3 and d == 18)
	var is_end: bool = (m == 9 and d == 15) or (m == 10 and d == 18) or (m == 11 and d == 20) or (m == 3 and d == 28)

	var club: TeamData = user_team()
	if club == null:
		return

	if is_start:
		var callups: Array[String] = []
		for s_idx: int in range(club.squad.size()):
			var p: PlayerData = club.squad[s_idx]
			if p.calculate_overall_rating() >= 68 or p.is_captain or p.player_reputation >= 0.60:
				callups.append(p.player_name)
		if not callups.is_empty():
			var names_str: String = ", ".join(callups.slice(0, 4))
			if callups.size() > 4:
				names_str += " and %d others" % (callups.size() - 4)
			_push_inbox(InboxEngine.build_simple(
				"International Call-ups",
				"%s have departed for international duty during this FIFA international break." % names_str,
				InboxItem.Category.MATCH, 0.70, today
			))
	elif is_end:
		var count: int = 0
		for s_idx2: int in range(club.squad.size()):
			var p2: PlayerData = club.squad[s_idx2]
			var st: PlayerCareerState = career.state_for_squad(career.user_team_index, s_idx2)
			if st != null and (p2.calculate_overall_rating() >= 68 or p2.is_captain or p2.player_reputation >= 0.60):
				count += 1
				st.condition = clampf(st.condition - 0.05, 0.20, 1.0)
				st.sharpness = clampf(st.sharpness + 0.08, 0.0, 1.0)
		if count > 0:
			_push_inbox(InboxEngine.build_simple(
				"International Return",
				"Your international players have rejoined the squad with match sharpness improved." % [],
				InboxItem.Category.TRAINING, 0.65, today
			))


## --- U23 Squad & Development Fixtures --------------------------------------------

func _simulate_u23_fixtures() -> void:
	var club: TeamData = user_team()
	if club == null:
		return
	for s_idx: int in range(club.squad.size()):
		var st: PlayerCareerState = career.state_for_squad(career.user_team_index, s_idx)
		var p: PlayerData = club.squad[s_idx]
		var age: int = p.get_age(career.today.year, career.today.month, career.today.day)
		if st != null and (st.in_u23_squad or age <= 21 or st.is_youth_player):
			st.sharpness = clampf(st.sharpness + 0.08, 0.0, 1.0)
			st.development_xp += 18.0
			if _rng.randf() < 0.12:
				st.goals_this_season += 1


func move_player_to_u23(player_key: int) -> void:
	var st: PlayerCareerState = career.state_for(player_key)
	if st != null:
		st.in_u23_squad = true


func move_player_to_senior(player_key: int) -> void:
	var st: PlayerCareerState = career.state_for(player_key)
	if st != null:
		st.in_u23_squad = false


## --- Loans & Free Agent Market API -----------------------------------------------

func submit_loan_bid(player_key: int, wage_share: float) -> TransferOffer:
	var team_index: int = player_key / 1000
	var squad_index: int = player_key % 1000
	var target_team: TeamData = DataLoader.get_team(team_index)
	if target_team == null or squad_index >= target_team.squad.size():
		return null
	var data: PlayerData = target_team.squad[squad_index]
	var buyer: TeamData = user_team()

	var offer := TransferOffer.make_loan(
		buyer.team_name, career.user_team_index,
		target_team.team_name, team_index, squad_index,
		data.player_name, wage_share, career.today
	)
	career.active_offers.append(offer)
	return offer


func sign_free_agent(player: PlayerData, contract: ContractData) -> bool:
	var club: TeamData = user_team()
	if club == null or player == null or contract == null:
		return false
	if career.board != null and career.board.transfer_embargo:
		return false

	club.squad.append(player)
	var new_squad_idx: int = club.squad.size() - 1
	var st := PlayerCareerState.make_for(
		player, career.user_team_index, new_squad_idx,
		player.calculate_overall_rating() + 5, career.today
	)
	st.contract = contract
	career.player_states[st.player_key] = st

	var fin: ClubFinances = career.user_finances()
	if fin != null:
		fin.record_expense(ClubFinances.Line.SIGNING_BONUSES, contract.signing_bonus)

	WorldEventLog.record(
		&"free_agent_signed", WorldEvent.Category.TRANSFER,
		"%s signed for %s on a free transfer." % [player.player_name, club.team_name],
		0.5, 0.8
	)
	_push_inbox(InboxEngine.build_simple(
		"Free Agent Signed: %s" % player.player_name,
		"Free agent %s has joined %s on %s/wk." % [
			player.player_name, club.team_name, TransferMarket.format_fee(contract.wage_weekly)
		],
		InboxItem.Category.TRANSFER, 0.85, career.today
	))
	return true


## --- Staff Hiring & Dismissal ----------------------------------------------------

func hire_staff_member(staff: StaffData, weekly_salary: int, years: int) -> bool:
	var club: TeamData = user_team()
	if club == null or staff == null:
		return false
	return StaffLoader.hire_staff(staff, club.team_name, weekly_salary, years)


func sack_staff_member(staff: StaffData) -> void:
	StaffLoader.terminate_staff(staff)


## --- Regional Scouting API -------------------------------------------------------

func assign_scout_to_region(scout_name: String, region: String) -> void:
	ScoutingNetwork.assign_scout_to_region(career, scout_name, region)


func get_scout_region(scout_name: String) -> String:
	return ScoutingNetwork.scout_region(career, scout_name)


## --- Tactical Presets API --------------------------------------------------------

func get_tactical_preset(slot_index: int) -> Dictionary:
	if career == null or career.profile == null:
		return {}
	return career.profile.get_preset(slot_index)


func save_tactical_preset(
	slot_index: int,
	preset_name: String,
	formation: String,
	tempo: float,
	pressing: float,
	def_line: float,
	width: float,
	phys: float
) -> void:
	if career == null or career.profile == null:
		return
	career.profile.save_preset(
		slot_index, preset_name, formation, tempo, pressing, def_line, width, phys
	)
