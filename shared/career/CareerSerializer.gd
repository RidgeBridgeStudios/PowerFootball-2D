##
## CareerSerializer
##
## Writes a CareerSaveData to disk as JSON and reads it back.
##
## Godot's ResourceSaver could persist these resources directly, but a career
## save has to survive the SCRIPTS changing between versions — adding a field
## to PlayerCareerState should not invalidate every existing save. JSON plus an
## explicit version number and a migration chain gives that; binary .tres does
## not.
##
## Layout on disk, per slot:
##   user://career/slot_<n>/career.json   — this file's output
##   user://career/slot_<n>/league.json   — DataLoader.save_league() output
##   user://career/slot_<n>/managers.json — ManagerLoader.save_managers() output
##
## The league is saved SEPARATELY and deliberately: squads, attributes and
## staff already have a canonical serialised form owned by DataLoader, and
## duplicating every PlayerData in here would guarantee the two copies
## eventually disagree.
##
## Depends on: every shared/career resource, DataLoader.
## Exposes: save_to_slot(), load_from_slot(), slot_summary(), list_slots(),
##          delete_slot(), slot_dir().
##

class_name CareerSerializer
extends RefCounted

const ROOT_DIR: String = "user://career"
const MAX_SLOTS: int = 3
const CAREER_FILE: String = "career.json"
const LEAGUE_FILE: String = "league.json"
const MANAGERS_FILE: String = "managers.json"


static func slot_dir(slot: int) -> String:
	return "%s/slot_%d" % [ROOT_DIR, slot]


static func career_path(slot: int) -> String:
	return "%s/%s" % [slot_dir(slot), CAREER_FILE]


static func league_path(slot: int) -> String:
	return "%s/%s" % [slot_dir(slot), LEAGUE_FILE]


static func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(career_path(slot))


static func _ensure_dir(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true
	var err: int = DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("CareerSerializer: could not create %s (%s)." % [path, error_string(err)])
		return false
	return true


## --- Save ---------------------------------------------------------------------

static func save_to_slot(career: CareerSaveData, slot: int) -> bool:
	if career == null:
		return false
	if not _ensure_dir(slot_dir(slot)):
		return false

	career.slot_index = slot
	career.save_version = CareerSaveData.SAVE_VERSION
	if career.today != null:
		career.last_played_iso = career.today.to_iso()

	var file := FileAccess.open(career_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("CareerSerializer: could not write %s (%s)." % [
			career_path(slot), error_string(FileAccess.get_open_error())
		])
		return false
	file.store_string(JSON.stringify(to_dict(career), "\t"))
	file.close()

	# The league (squads/staff/attributes) rides along in the same slot.
	DataLoader.save_league(league_path(slot))
	return true


static func to_dict(c: CareerSaveData) -> Dictionary:
	var comps: Array = []
	for comp: CompetitionData in c.competitions:
		comps.append(_competition_to_dict(comp))

	var states: Dictionary = {}
	for key: int in c.player_states:
		var st: PlayerCareerState = c.player_states[key] as PlayerCareerState
		if st != null:
			states[str(key)] = _player_state_to_dict(st)

	var finances: Dictionary = {}
	for team_index: int in c.club_finances:
		var f: ClubFinances = c.club_finances[team_index] as ClubFinances
		if f != null:
			finances[str(team_index)] = _finances_to_dict(f)

	var inbox: Array = []
	for item: InboxItem in c.inbox:
		inbox.append(_inbox_to_dict(item))

	var events: Array = []
	for e: WorldEvent in c.world_events:
		events.append(_event_to_dict(e))

	var reports: Array = []
	for r: ScoutReport in c.scout_reports:
		reports.append(_report_to_dict(r))

	var offers: Array = []
	for o: TransferOffer in c.active_offers:
		offers.append(_offer_to_dict(o))

	return {
		"save_version": c.save_version,
		"slot_index": c.slot_index,
		"save_name": c.save_name,
		"created_iso": c.created_iso,
		"last_played_iso": c.last_played_iso,
		"profile": _profile_to_dict(c.profile),
		"user_team_index": c.user_team_index,
		"today": _date_to_str(c.today),
		"season_start_year": c.season_start_year,
		"phase": int(c.phase),
		"rng_seed": c.rng_seed,
		"competitions": comps,
		"season_archive": c.season_archive,
		"tier_1_indices": c.tier_1_indices,
		"tier_2_indices": c.tier_2_indices,
		"continental_indices": c.continental_indices,
		"player_states": states,
		"club_finances": finances,
		"board": _board_to_dict(c.board),
		"training": _training_to_dict(c.training),
		"inbox": inbox,
		"world_events": events,
		"scout_reports": reports,
		"shortlist_keys": c.shortlist_keys,
		"active_offers": offers,
		"scout_assignments": c.scout_assignments,
		"transfer_window_open": c.transfer_window_open,
		"is_sacked": c.is_sacked,
		"unemployed": c.unemployed,
		"awaiting_match_result": c.awaiting_match_result,
		"pending_fixture_round": c.pending_fixture_round,
		"pending_fixture_competition": c.pending_fixture_competition,
	}


## --- Load ---------------------------------------------------------------------

## Returns null when the slot is empty, unreadable, or written by a NEWER
## version than this build understands. A future save is refused outright
## rather than half-read into a corrupt career.
static func load_from_slot(slot: int) -> CareerSaveData:
	if not slot_exists(slot):
		return null
	var file := FileAccess.open(career_path(slot), FileAccess.READ)
	if file == null:
		push_error("CareerSerializer: could not read %s." % career_path(slot))
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CareerSerializer: slot %d is not valid JSON." % slot)
		return null

	var d: Dictionary = parsed
	var version: int = int(d.get("save_version", 0))
	if version > CareerSaveData.SAVE_VERSION:
		push_error("CareerSerializer: slot %d was written by a newer version (%d > %d) and cannot be loaded." % [
			slot, version, CareerSaveData.SAVE_VERSION
		])
		return null
	if version < CareerSaveData.SAVE_VERSION:
		d = migrate(d, version)

	# The squads must be restored BEFORE the career state that indexes into
	# them, or every player_state would point at the wrong PlayerData.
	if FileAccess.file_exists(league_path(slot)):
		DataLoader.load_league_from(league_path(slot))

	return from_dict(d)


## Forward migration chain. Each step upgrades one version to the next, so a
## very old save walks all the way up rather than needing a bespoke path.
static func migrate(d: Dictionary, from_version: int) -> Dictionary:
	var working: Dictionary = d
	var v: int = from_version
	while v < CareerSaveData.SAVE_VERSION:
		match v:
			0:
				# v0 -> v1: pre-release saves had no explicit phase or seed.
				if not working.has("phase"):
					working["phase"] = int(CareerSaveData.Phase.REGULAR_SEASON)
				if not working.has("rng_seed"):
					working["rng_seed"] = 12345
			_:
				pass
		v += 1
	working["save_version"] = CareerSaveData.SAVE_VERSION
	return working


static func from_dict(d: Dictionary) -> CareerSaveData:
	var c := CareerSaveData.new()
	c.save_version = int(d.get("save_version", CareerSaveData.SAVE_VERSION))
	c.slot_index = int(d.get("slot_index", 0))
	c.save_name = String(d.get("save_name", "Career"))
	c.created_iso = String(d.get("created_iso", ""))
	c.last_played_iso = String(d.get("last_played_iso", ""))
	c.profile = _profile_from_dict(d.get("profile", {}))
	c.user_team_index = int(d.get("user_team_index", 0))
	c.today = _date_from_str(String(d.get("today", "2026-07-01")))
	c.season_start_year = int(d.get("season_start_year", 2026))
	c.phase = int(d.get("phase", 0)) as CareerSaveData.Phase
	c.rng_seed = int(d.get("rng_seed", 0))

	var comps: Array[CompetitionData] = []
	for raw: Variant in d.get("competitions", []):
		if typeof(raw) == TYPE_DICTIONARY:
			comps.append(_competition_from_dict(raw))
	c.competitions = comps

	var archive: Array[Dictionary] = []
	for raw2: Variant in d.get("season_archive", []):
		if typeof(raw2) == TYPE_DICTIONARY:
			archive.append(raw2)
	c.season_archive = archive

	var t1: Array[int] = []
	for raw_t1: Variant in d.get("tier_1_indices", []):
		t1.append(int(raw_t1))
	c.tier_1_indices = t1

	var t2: Array[int] = []
	for raw_t2: Variant in d.get("tier_2_indices", []):
		t2.append(int(raw_t2))
	c.tier_2_indices = t2

	var cont: Array[int] = []
	for raw_cont: Variant in d.get("continental_indices", []):
		cont.append(int(raw_cont))
	c.continental_indices = cont

	var states: Dictionary = {}
	var raw_states: Dictionary = d.get("player_states", {})
	for key_str: Variant in raw_states:
		var st: PlayerCareerState = _player_state_from_dict(raw_states[key_str])
		states[String(key_str).to_int()] = st
	c.player_states = states

	var finances: Dictionary = {}
	var raw_fin: Dictionary = d.get("club_finances", {})
	for fk: Variant in raw_fin:
		finances[String(fk).to_int()] = _finances_from_dict(raw_fin[fk])
	c.club_finances = finances

	c.board = _board_from_dict(d.get("board", {}))
	c.training = _training_from_dict(d.get("training", {}))

	var inbox: Array[InboxItem] = []
	for raw3: Variant in d.get("inbox", []):
		if typeof(raw3) == TYPE_DICTIONARY:
			inbox.append(_inbox_from_dict(raw3))
	c.inbox = inbox

	var events: Array[WorldEvent] = []
	for raw4: Variant in d.get("world_events", []):
		if typeof(raw4) == TYPE_DICTIONARY:
			events.append(_event_from_dict(raw4))
	c.world_events = events

	var reports: Array[ScoutReport] = []
	for raw5: Variant in d.get("scout_reports", []):
		if typeof(raw5) == TYPE_DICTIONARY:
			reports.append(_report_from_dict(raw5))
	c.scout_reports = reports

	var shortlist: Array[int] = []
	for raw6: Variant in d.get("shortlist_keys", []):
		shortlist.append(int(raw6))
	c.shortlist_keys = shortlist

	var offers: Array[TransferOffer] = []
	for raw7: Variant in d.get("active_offers", []):
		if typeof(raw7) == TYPE_DICTIONARY:
			offers.append(_offer_from_dict(raw7))
	c.active_offers = offers

	c.scout_assignments = d.get("scout_assignments", {})
	c.transfer_window_open = bool(d.get("transfer_window_open", true))
	c.is_sacked = bool(d.get("is_sacked", false))
	c.unemployed = bool(d.get("unemployed", false))
	c.awaiting_match_result = bool(d.get("awaiting_match_result", false))
	c.pending_fixture_round = int(d.get("pending_fixture_round", -1))
	c.pending_fixture_competition = int(d.get("pending_fixture_competition", -1))
	return c


## --- Slot listing -----------------------------------------------------------------

## Lightweight header for the load screen — reads only what it needs to render
## a slot row, without deserialising the whole career.
static func slot_summary(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {"slot": slot, "empty": true}
	var file := FileAccess.open(career_path(slot), FileAccess.READ)
	if file == null:
		return {"slot": slot, "empty": true}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"slot": slot, "empty": true, "corrupt": true}
	var d: Dictionary = parsed
	var profile: Dictionary = d.get("profile", {})
	return {
		"slot": slot,
		"empty": false,
		"save_name": String(d.get("save_name", "Career")),
		"manager_name": String(profile.get("manager_name", "Unknown")),
		"club": String(profile.get("current_club", "")),
		"date": String(d.get("last_played_iso", "")),
		"season": int(d.get("season_start_year", 2026)),
		"version": int(d.get("save_version", 0)),
		"outdated": int(d.get("save_version", 0)) < CareerSaveData.SAVE_VERSION,
		"future": int(d.get("save_version", 0)) > CareerSaveData.SAVE_VERSION,
	}


static func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(MAX_SLOTS):
		out.append(slot_summary(i))
	return out


static func delete_slot(slot: int) -> bool:
	var dir_path: String = slot_dir(slot)
	if not DirAccess.dir_exists_absolute(dir_path):
		return false
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	for f: String in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(dir_path)
	return true


## --- Per-resource conversion ------------------------------------------------------

static func _date_to_str(d: CareerDate) -> String:
	return d.to_iso() if d != null else ""


static func _date_from_str(s: String) -> CareerDate:
	if s == "":
		return null
	return CareerDate.from_iso(s)


static func _profile_to_dict(p: ManagerCareerProfile) -> Dictionary:
	if p == null:
		return {}
	return {
		"manager_name": p.manager_name,
		"nationality": p.nationality,
		"date_of_birth": p.date_of_birth,
		"background": int(p.background),
		"philosophy": int(p.philosophy),
		"preferred_formation": p.preferred_formation,
		"reputation": p.reputation,
		"press_standing": p.press_standing,
		"attributes": p.attributes,
		"attribute_xp": p.attribute_xp,
		"current_club": p.current_club,
		"contract": _contract_to_dict(p.contract),
		"matches_managed": p.matches_managed,
		"wins": p.wins,
		"draws": p.draws,
		"losses": p.losses,
		"trophies_won": p.trophies_won,
		"times_sacked": p.times_sacked,
		"promotions": p.promotions,
		"relegations": p.relegations,
		"job_history": p.job_history,
		"season_history": p.season_history,
		"tactical_presets": p.tactical_presets,
	}


static func _profile_from_dict(raw: Variant) -> ManagerCareerProfile:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	var p := ManagerCareerProfile.new()
	p.manager_name = String(d.get("manager_name", "Manager"))
	p.nationality = String(d.get("nationality", "English"))
	p.date_of_birth = String(d.get("date_of_birth", "1985-01-01"))
	p.background = int(d.get("background", 0)) as ManagerCareerProfile.Background
	p.philosophy = int(d.get("philosophy", 4)) as ManagerCareerProfile.Philosophy
	p.preferred_formation = String(d.get("preferred_formation", "4-4-2"))
	p.reputation = float(d.get("reputation", 0.15))
	p.press_standing = float(d.get("press_standing", 0.5))
	p.attributes = d.get("attributes", {})
	p.attribute_xp = d.get("attribute_xp", {})
	p.current_club = String(d.get("current_club", ""))
	p.contract = _contract_from_dict(d.get("contract", {}))
	p.matches_managed = int(d.get("matches_managed", 0))
	p.wins = int(d.get("wins", 0))
	p.draws = int(d.get("draws", 0))
	p.losses = int(d.get("losses", 0))
	p.trophies_won = int(d.get("trophies_won", 0))
	p.times_sacked = int(d.get("times_sacked", 0))
	p.promotions = int(d.get("promotions", 0))
	p.relegations = int(d.get("relegations", 0))
	var jobs: Array[Dictionary] = []
	for j: Variant in d.get("job_history", []):
		if typeof(j) == TYPE_DICTIONARY:
			jobs.append(j)
	p.job_history = jobs
	var seasons: Array[Dictionary] = []
	for s: Variant in d.get("season_history", []):
		if typeof(s) == TYPE_DICTIONARY:
			seasons.append(s)
	p.season_history = seasons
	var presets: Array[Dictionary] = []
	for pr: Variant in d.get("tactical_presets", []):
		if typeof(pr) == TYPE_DICTIONARY:
			presets.append(pr)
	p.tactical_presets = presets
	p.ensure_default_presets()
	# tactical is DERIVED, never stored — rebuilding it guarantees it can never
	# drift out of sync with the philosophy/attributes that produce it.
	p.sync_to_tactical()
	return p


static func _contract_to_dict(c: ContractData) -> Dictionary:
	if c == null:
		return {}
	return {
		"club_name": c.club_name,
		"wage_weekly": c.wage_weekly,
		"expiry": _date_to_str(c.expiry),
		"signed_on": _date_to_str(c.signed_on),
		"release_clause": c.release_clause,
		"loyalty_bonus": c.loyalty_bonus,
		"signing_bonus": c.signing_bonus,
		"goal_bonus": c.goal_bonus,
		"promotion_bonus": c.promotion_bonus,
		"promised_status": int(c.promised_status),
		"transfer_fee_paid": c.transfer_fee_paid,
		"is_on_loan": c.is_on_loan,
		"loan_parent_club": c.loan_parent_club,
		"loan_expires": _date_to_str(c.loan_expires),
		"loan_wage_subsidy": c.loan_wage_subsidy,
	}


static func _contract_from_dict(raw: Variant) -> ContractData:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	if d.is_empty():
		return null
	var c := ContractData.new()
	c.club_name = String(d.get("club_name", ""))
	c.wage_weekly = int(d.get("wage_weekly", 0))
	c.expiry = _date_from_str(String(d.get("expiry", "")))
	c.signed_on = _date_from_str(String(d.get("signed_on", "")))
	c.release_clause = int(d.get("release_clause", 0))
	c.loyalty_bonus = int(d.get("loyalty_bonus", 0))
	c.signing_bonus = int(d.get("signing_bonus", 0))
	c.goal_bonus = int(d.get("goal_bonus", 0))
	c.promotion_bonus = int(d.get("promotion_bonus", 0))
	c.promised_status = int(d.get("promised_status", 2)) as ContractData.Status
	c.transfer_fee_paid = int(d.get("transfer_fee_paid", 0))
	c.is_on_loan = bool(d.get("is_on_loan", false))
	c.loan_parent_club = String(d.get("loan_parent_club", ""))
	c.loan_expires = _date_from_str(String(d.get("loan_expires", "")))
	c.loan_wage_subsidy = float(d.get("loan_wage_subsidy", 0.0))
	return c


static func _player_state_to_dict(s: PlayerCareerState) -> Dictionary:
	var rels: Dictionary = {}
	for other_key: int in s.relationships:
		var r: RelationshipData = s.relationships[other_key] as RelationshipData
		if r != null:
			rels[str(other_key)] = {
				"trust": r.trust,
				"rivalry": r.rivalry_score,
				"history": r.history,
				"last": r.last_interaction_ordinal,
			}
	var grievances: Array = []
	for g: StringName in s.grievances:
		grievances.append(String(g))
	return {
		"player_key": s.player_key,
		"display_name": s.display_name,
		"squad_index": s.squad_index,
		"team_index": s.team_index,
		"condition": s.condition,
		"sharpness": s.sharpness,
		"injury": int(s.injury),
		"injury_days_remaining": s.injury_days_remaining,
		"injury_return_date": _date_to_str(s.injury_return_date),
		"injury_proneness": s.injury_proneness,
		"potential_ability": s.potential_ability,
		"development_xp": s.development_xp,
		"is_youth_player": s.is_youth_player,
		"in_u23_squad": s.in_u23_squad,
		"appearances": s.appearances,
		"minutes_played": s.minutes_played,
		"goals_this_season": s.goals_this_season,
		"assists_this_season": s.assists_this_season,
		"average_rating": s.average_rating,
		"yellow_cards_season": s.yellow_cards_season,
		"red_cards_season": s.red_cards_season,
		"suspension_matches": s.suspension_matches,
		"contract": _contract_to_dict(s.contract),
		"manager_trust": s.manager_trust,
		"relationships": rels,
		"grievances": grievances,
		"transfer_listed": s.transfer_listed,
		"loan_listed": s.loan_listed,
		"wants_new_contract": s.wants_new_contract,
		"has_requested_transfer": s.has_requested_transfer,
		"promised_status": s.promised_status,
		"promise_review_date": _date_to_str(s.promise_review_date),
	}


static func _player_state_from_dict(raw: Variant) -> PlayerCareerState:
	var s := PlayerCareerState.new()
	if typeof(raw) != TYPE_DICTIONARY:
		return s
	var d: Dictionary = raw
	s.player_key = int(d.get("player_key", -1))
	s.display_name = String(d.get("display_name", ""))
	s.squad_index = int(d.get("squad_index", -1))
	s.team_index = int(d.get("team_index", -1))
	s.condition = float(d.get("condition", 1.0))
	s.sharpness = float(d.get("sharpness", 0.6))
	s.injury = int(d.get("injury", 0)) as PlayerCareerState.InjuryKind
	s.injury_days_remaining = int(d.get("injury_days_remaining", 0))
	s.injury_return_date = _date_from_str(String(d.get("injury_return_date", "")))
	s.injury_proneness = float(d.get("injury_proneness", 0.25))
	s.potential_ability = int(d.get("potential_ability", 65))
	s.development_xp = float(d.get("development_xp", 0.0))
	s.is_youth_player = bool(d.get("is_youth_player", false))
	s.in_u23_squad = bool(d.get("in_u23_squad", false))
	s.appearances = int(d.get("appearances", 0))
	s.minutes_played = int(d.get("minutes_played", 0))
	s.goals_this_season = int(d.get("goals_this_season", 0))
	s.assists_this_season = int(d.get("assists_this_season", 0))
	s.average_rating = float(d.get("average_rating", 0.0))
	s.yellow_cards_season = int(d.get("yellow_cards_season", 0))
	s.red_cards_season = int(d.get("red_cards_season", 0))
	s.suspension_matches = int(d.get("suspension_matches", 0))
	s.contract = _contract_from_dict(d.get("contract", {}))
	s.manager_trust = float(d.get("manager_trust", 0.5))

	var rels: Dictionary = {}
	var raw_rels: Dictionary = d.get("relationships", {})
	for other_key_str: Variant in raw_rels:
		var rd: Dictionary = raw_rels[other_key_str]
		var r := RelationshipData.new()
		r.trust = float(rd.get("trust", 0.5))
		r.rivalry_score = float(rd.get("rivalry", 0.0))
		var hist: Array[String] = []
		for h: Variant in rd.get("history", []):
			hist.append(String(h))
		r.history = hist
		r.last_interaction_ordinal = int(rd.get("last", 0))
		rels[String(other_key_str).to_int()] = r
	s.relationships = rels

	var grievances: Array[StringName] = []
	for g: Variant in d.get("grievances", []):
		grievances.append(StringName(String(g)))
	s.grievances = grievances

	s.transfer_listed = bool(d.get("transfer_listed", false))
	s.loan_listed = bool(d.get("loan_listed", false))
	s.wants_new_contract = bool(d.get("wants_new_contract", false))
	s.has_requested_transfer = bool(d.get("has_requested_transfer", false))
	s.promised_status = int(d.get("promised_status", -1))
	s.promise_review_date = _date_from_str(String(d.get("promise_review_date", "")))
	return s


static func _finances_to_dict(f: ClubFinances) -> Dictionary:
	return {
		"club_name": f.club_name,
		"balance": f.balance,
		"transfer_budget": f.transfer_budget,
		"wage_budget_weekly": f.wage_budget_weekly,
		"stadium_capacity": f.stadium_capacity,
		"season_income": f.season_income,
		"season_expense": f.season_expense,
		"payables": f.payables,
		"receivables": f.receivables,
		"last_weekly_cycle": _date_to_str(f.last_weekly_cycle),
		"spending_frozen": f.spending_frozen,
	}


static func _finances_from_dict(raw: Variant) -> ClubFinances:
	var f := ClubFinances.new()
	if typeof(raw) != TYPE_DICTIONARY:
		return f
	var d: Dictionary = raw
	f.club_name = String(d.get("club_name", ""))
	f.balance = int(d.get("balance", 0))
	f.transfer_budget = int(d.get("transfer_budget", 0))
	f.wage_budget_weekly = int(d.get("wage_budget_weekly", 0))
	f.stadium_capacity = int(d.get("stadium_capacity", 24000))
	f.season_income = _int_array(d.get("season_income", []), 9)
	f.season_expense = _int_array(d.get("season_expense", []), 9)
	var pay: Array[Dictionary] = []
	for p: Variant in d.get("payables", []):
		if typeof(p) == TYPE_DICTIONARY:
			pay.append(p)
	f.payables = pay
	var rec: Array[Dictionary] = []
	for r: Variant in d.get("receivables", []):
		if typeof(r) == TYPE_DICTIONARY:
			rec.append(r)
	f.receivables = rec
	f.last_weekly_cycle = _date_from_str(String(d.get("last_weekly_cycle", "")))
	f.spending_frozen = bool(d.get("spending_frozen", false))
	return f


static func _int_array(raw: Variant, min_size: int) -> Array[int]:
	var out: Array[int] = []
	if typeof(raw) == TYPE_ARRAY:
		for v: Variant in (raw as Array):
			out.append(int(v))
	while out.size() < min_size:
		out.append(0)
	return out


static func _board_to_dict(b: BoardState) -> Dictionary:
	if b == null:
		return {}
	return {
		"club_name": b.club_name,
		"expectation": int(b.expectation),
		"confidence": b.confidence,
		"trajectory": b.trajectory,
		"matches_below_threshold": b.matches_below_threshold,
		"patience_notes": b.patience_notes,
		"training_facilities": b.training_facilities,
		"youth_facilities": b.youth_facilities,
		"scouting_range": b.scouting_range,
		"stadium_capacity": b.stadium_capacity,
		"pending_requests": b.pending_requests,
		"request_history": b.request_history,
		"takeover_pending": b.takeover_pending,
		"takeover_stage": int(b.takeover_stage),
		"takeover_consortium_name": b.takeover_consortium_name,
		"takeover_days_remaining": b.takeover_days_remaining,
		"takeover_cash_injection": b.takeover_cash_injection,
		"transfer_embargo": b.transfer_embargo,
		"owner_name": b.owner_name,
	}


static func _board_from_dict(raw: Variant) -> BoardState:
	if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		return null
	var d: Dictionary = raw
	var b := BoardState.new()
	b.club_name = String(d.get("club_name", ""))
	b.expectation = int(d.get("expectation", 2)) as BoardState.Expectation
	b.confidence = float(d.get("confidence", 0.65))
	b.trajectory = float(d.get("trajectory", 0.5))
	b.matches_below_threshold = int(d.get("matches_below_threshold", 0))
	var notes: Array[String] = []
	for n: Variant in d.get("patience_notes", []):
		notes.append(String(n))
	b.patience_notes = notes
	b.training_facilities = int(d.get("training_facilities", 3))
	b.youth_facilities = int(d.get("youth_facilities", 3))
	b.scouting_range = int(d.get("scouting_range", 2))
	b.stadium_capacity = int(d.get("stadium_capacity", 24000))
	var pend: Array[Dictionary] = []
	for p: Variant in d.get("pending_requests", []):
		if typeof(p) == TYPE_DICTIONARY:
			pend.append(p)
	b.pending_requests = pend
	var hist: Array[Dictionary] = []
	for h: Variant in d.get("request_history", []):
		if typeof(h) == TYPE_DICTIONARY:
			hist.append(h)
	b.request_history = hist
	b.takeover_pending = bool(d.get("takeover_pending", false))
	b.takeover_stage = int(d.get("takeover_stage", 0)) as BoardState.TakeoverStage
	b.takeover_consortium_name = String(d.get("takeover_consortium_name", ""))
	b.takeover_days_remaining = int(d.get("takeover_days_remaining", 0))
	b.takeover_cash_injection = int(d.get("takeover_cash_injection", 0))
	b.transfer_embargo = bool(d.get("transfer_embargo", false))
	b.owner_name = String(d.get("owner_name", "The Board"))
	return b


static func _training_to_dict(t: TrainingSchedule) -> Dictionary:
	if t == null:
		return {}
	return {
		"club_name": t.club_name,
		"week": t.week,
		"youth_week": t.youth_week,
		"individual_focus": t.individual_focus,
		"retrain_target": t.retrain_target,
	}


static func _training_from_dict(raw: Variant) -> TrainingSchedule:
	if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		return null
	var d: Dictionary = raw
	var t := TrainingSchedule.new()
	t.club_name = String(d.get("club_name", ""))
	t.week = _int_array(d.get("week", []), 7)
	t.youth_week = _int_array(d.get("youth_week", []), 7)
	t.individual_focus = _int_keyed(d.get("individual_focus", {}))
	t.retrain_target = _int_keyed(d.get("retrain_target", {}))
	return t


## JSON object keys are always strings; squad-index-keyed dictionaries have to
## be converted back to int keys or every lookup silently misses.
static func _int_keyed(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for k: Variant in (raw as Dictionary):
		out[String(k).to_int()] = (raw as Dictionary)[k]
	return out


static func _competition_to_dict(c: CompetitionData) -> Dictionary:
	var fx: Array = []
	for f: FixtureData in c.fixtures:
		fx.append({
			"competition": int(f.competition),
			"round_number": f.round_number,
			"round_label": f.round_label,
			"date": _date_to_str(f.date),
			"home": f.home_team_index,
			"away": f.away_team_index,
			"played": f.played,
			"home_score": f.home_score,
			"away_score": f.away_score,
			"attendance": f.attendance,
			"leg": f.leg,
			"tie_id": f.tie_id,
			"involves_user": f.involves_user,
			"decided_winner_index": f.decided_winner_index,
		})
	var rows: Array = []
	for r: LeagueTableRow in c.table:
		rows.append({
			"team_index": r.team_index,
			"team_name": r.team_name,
			"played": r.played,
			"won": r.won,
			"drawn": r.drawn,
			"lost": r.lost,
			"goals_for": r.goals_for,
			"goals_against": r.goals_against,
			"points": r.points,
			"form": r.form,
		})
	return {
		"competition_name": c.competition_name,
		"kind": int(c.kind),
		"participant_indices": c.participant_indices,
		"fixtures": fx,
		"table": rows,
		"current_round": c.current_round,
		"total_rounds": c.total_rounds,
		"remaining_indices": c.remaining_indices,
		"winner_index": c.winner_index,
		"two_legged": c.two_legged,
		"fixture_tag": int(c.fixture_tag),
		"tier": c.tier,
	}


static func _competition_from_dict(d: Dictionary) -> CompetitionData:
	var c := CompetitionData.new()
	c.competition_name = String(d.get("competition_name", "League"))
	c.kind = int(d.get("kind", 0)) as CompetitionData.Kind
	c.participant_indices = _int_array(d.get("participant_indices", []), 0)
	c.current_round = int(d.get("current_round", 1))
	c.total_rounds = int(d.get("total_rounds", 1))
	c.remaining_indices = _int_array(d.get("remaining_indices", []), 0)
	c.winner_index = int(d.get("winner_index", -1))
	c.two_legged = bool(d.get("two_legged", false))
	c.fixture_tag = int(d.get("fixture_tag", 0)) as FixtureData.Competition
	c.tier = int(d.get("tier", 1))

	var fx: Array[FixtureData] = []
	for raw: Variant in d.get("fixtures", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var fd: Dictionary = raw
		var f := FixtureData.new()
		f.competition = int(fd.get("competition", 0)) as FixtureData.Competition
		f.round_number = int(fd.get("round_number", 1))
		f.round_label = String(fd.get("round_label", ""))
		f.date = _date_from_str(String(fd.get("date", "")))
		f.home_team_index = int(fd.get("home", 0))
		f.away_team_index = int(fd.get("away", 1))
		f.played = bool(fd.get("played", false))
		f.home_score = int(fd.get("home_score", 0))
		f.away_score = int(fd.get("away_score", 0))
		f.attendance = int(fd.get("attendance", 0))
		f.leg = int(fd.get("leg", 0))
		f.tie_id = String(fd.get("tie_id", ""))
		f.involves_user = bool(fd.get("involves_user", false))
		f.decided_winner_index = int(fd.get("decided_winner_index", -1))
		fx.append(f)
	c.fixtures = fx

	var rows: Array[LeagueTableRow] = []
	for raw2: Variant in d.get("table", []):
		if typeof(raw2) != TYPE_DICTIONARY:
			continue
		var rd: Dictionary = raw2
		var r := LeagueTableRow.new()
		r.team_index = int(rd.get("team_index", 0))
		r.team_name = String(rd.get("team_name", ""))
		r.played = int(rd.get("played", 0))
		r.won = int(rd.get("won", 0))
		r.drawn = int(rd.get("drawn", 0))
		r.lost = int(rd.get("lost", 0))
		r.goals_for = int(rd.get("goals_for", 0))
		r.goals_against = int(rd.get("goals_against", 0))
		r.points = int(rd.get("points", 0))
		var form: Array[String] = []
		for fv: Variant in rd.get("form", []):
			form.append(String(fv))
		r.form = form
		rows.append(r)
	c.table = rows
	return c


static func _inbox_to_dict(i: InboxItem) -> Dictionary:
	return {
		"subject": i.subject,
		"body": i.body,
		"category": int(i.category),
		"received": _date_to_str(i.received),
		"deadline": _date_to_str(i.deadline),
		"is_read": i.is_read,
		"is_resolved": i.is_resolved,
		"chosen_option": i.chosen_option,
		"subject_player_key": i.subject_player_key,
		"subject_player_name": i.subject_player_name,
		"priority": i.priority,
		"escalation_option": i.escalation_option,
		"payload": i.payload,
	}


## Note: options are NOT persisted. An InboxItem.Option is a plain inner class
## carrying behaviour-defining deltas, and re-reading those from disk would let
## a hand-edited save invent arbitrary effects. A restored item keeps its text
## and its resolved state; an UNRESOLVED decision is rebuilt with fresh options
## by CareerManager._rehydrate_inbox() from its category and payload.
static func _inbox_from_dict(d: Dictionary) -> InboxItem:
	var i := InboxItem.new()
	i.subject = String(d.get("subject", ""))
	i.body = String(d.get("body", ""))
	i.category = int(d.get("category", 0)) as InboxItem.Category
	i.received = _date_from_str(String(d.get("received", "")))
	i.deadline = _date_from_str(String(d.get("deadline", "")))
	i.is_read = bool(d.get("is_read", false))
	i.is_resolved = bool(d.get("is_resolved", false))
	i.chosen_option = int(d.get("chosen_option", -1))
	i.subject_player_key = int(d.get("subject_player_key", -1))
	i.subject_player_name = String(d.get("subject_player_name", ""))
	i.priority = float(d.get("priority", 0.4))
	i.escalation_option = int(d.get("escalation_option", -1))
	i.payload = d.get("payload", {})
	return i


static func _event_to_dict(e: WorldEvent) -> Dictionary:
	return {
		"event_tag": String(e.event_tag),
		"category": int(e.category),
		"date": _date_to_str(e.date),
		"season_year": e.season_year,
		"primary_player_key": e.primary_player_key,
		"secondary_player_key": e.secondary_player_key,
		"primary_player_name": e.primary_player_name,
		"secondary_player_name": e.secondary_player_name,
		"club_name": e.club_name,
		"narrative_context": e.narrative_context,
		"sentiment": e.sentiment,
		"significance": e.significance,
		"resolved": e.resolved,
		"resolution_choice": e.resolution_choice,
	}


static func _event_from_dict(d: Dictionary) -> WorldEvent:
	var e := WorldEvent.new()
	e.event_tag = StringName(String(d.get("event_tag", "")))
	e.category = int(d.get("category", 0)) as WorldEvent.Category
	e.date = _date_from_str(String(d.get("date", "")))
	e.season_year = int(d.get("season_year", 2026))
	e.primary_player_key = int(d.get("primary_player_key", -1))
	e.secondary_player_key = int(d.get("secondary_player_key", -1))
	e.primary_player_name = String(d.get("primary_player_name", ""))
	e.secondary_player_name = String(d.get("secondary_player_name", ""))
	e.club_name = String(d.get("club_name", ""))
	e.narrative_context = String(d.get("narrative_context", ""))
	e.sentiment = float(d.get("sentiment", 0.0))
	e.significance = float(d.get("significance", 0.3))
	e.resolved = bool(d.get("resolved", false))
	e.resolution_choice = int(d.get("resolution_choice", -1))
	return e


static func _report_to_dict(r: ScoutReport) -> Dictionary:
	return {
		"target_team_index": r.target_team_index,
		"target_squad_index": r.target_squad_index,
		"target_name": r.target_name,
		"target_club": r.target_club,
		"target_position": r.target_position,
		"knowledge": r.knowledge,
		"stage": int(r.stage),
		"assigned_scout_name": r.assigned_scout_name,
		"first_seen": _date_to_str(r.first_seen),
		"last_updated": _date_to_str(r.last_updated),
		"true_overall": r.true_overall,
		"true_potential": r.true_potential,
		"verdict": r.verdict,
		"estimate_bias": r.estimate_bias,
	}


static func _report_from_dict(d: Dictionary) -> ScoutReport:
	var r := ScoutReport.new()
	r.target_team_index = int(d.get("target_team_index", -1))
	r.target_squad_index = int(d.get("target_squad_index", -1))
	r.target_name = String(d.get("target_name", ""))
	r.target_club = String(d.get("target_club", ""))
	r.target_position = String(d.get("target_position", ""))
	r.knowledge = float(d.get("knowledge", 0.0))
	r.stage = int(d.get("stage", 0)) as ScoutReport.Stage
	r.assigned_scout_name = String(d.get("assigned_scout_name", ""))
	r.first_seen = _date_from_str(String(d.get("first_seen", "")))
	r.last_updated = _date_from_str(String(d.get("last_updated", "")))
	r.true_overall = int(d.get("true_overall", 50))
	r.true_potential = int(d.get("true_potential", 60))
	r.verdict = String(d.get("verdict", ""))
	r.estimate_bias = float(d.get("estimate_bias", 0.0))
	return r


static func _offer_to_dict(o: TransferOffer) -> Dictionary:
	return {
		"buying_club": o.buying_club,
		"buyer_team_index": o.buyer_team_index,
		"selling_club": o.selling_club,
		"player_name": o.player_name,
		"player_team_index": o.player_team_index,
		"player_squad_index": o.player_squad_index,
		"kind": int(o.kind),
		"state": int(o.state),
		"fee_offered": o.fee_offered,
		"fee_demanded": o.fee_demanded,
		"sell_on_percent": o.sell_on_percent,
		"instalment_years": o.instalment_years,
		"wage_offered": o.wage_offered,
		"wage_demanded": o.wage_demanded,
		"contract_years_offered": o.contract_years_offered,
		"signing_bonus_offered": o.signing_bonus_offered,
		"release_clause_offered": o.release_clause_offered,
		"promised_status": int(o.promised_status),
		"loan_wage_share": o.loan_wage_share,
		"loan_months": o.loan_months,
		"submitted_on": _date_to_str(o.submitted_on),
		"last_state_change": _date_to_str(o.last_state_change),
		"response_message": o.response_message,
		"initiated_by_user": o.initiated_by_user,
	}


static func _offer_from_dict(d: Dictionary) -> TransferOffer:
	var o := TransferOffer.new()
	o.buying_club = String(d.get("buying_club", ""))
	o.buyer_team_index = int(d.get("buyer_team_index", -1))
	o.selling_club = String(d.get("selling_club", ""))
	o.player_name = String(d.get("player_name", ""))
	o.player_team_index = int(d.get("player_team_index", -1))
	o.player_squad_index = int(d.get("player_squad_index", -1))
	o.kind = int(d.get("kind", 0)) as TransferOffer.Kind
	o.state = int(d.get("state", 0)) as TransferOffer.State
	o.fee_offered = int(d.get("fee_offered", 0))
	o.fee_demanded = int(d.get("fee_demanded", 0))
	o.sell_on_percent = float(d.get("sell_on_percent", 0.0))
	o.instalment_years = int(d.get("instalment_years", 1))
	o.wage_offered = int(d.get("wage_offered", 0))
	o.wage_demanded = int(d.get("wage_demanded", 0))
	o.contract_years_offered = int(d.get("contract_years_offered", 3))
	o.signing_bonus_offered = int(d.get("signing_bonus_offered", 0))
	o.release_clause_offered = int(d.get("release_clause_offered", 0))
	o.promised_status = int(d.get("promised_status", 2)) as ContractData.Status
	o.loan_wage_share = float(d.get("loan_wage_share", 0.5))
	o.loan_months = int(d.get("loan_months", 6))
	o.submitted_on = _date_from_str(String(d.get("submitted_on", "")))
	o.last_state_change = _date_from_str(String(d.get("last_state_change", "")))
	o.response_message = String(d.get("response_message", ""))
	o.initiated_by_user = bool(d.get("initiated_by_user", false))
	return o
