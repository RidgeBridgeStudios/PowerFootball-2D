##
## StaffLoader (Autoload singleton)
##
## Owns the pool of backroom staff members across clubs and free agency.
## Loads custom staff from user://custom_staff.json if present, otherwise loads
## from packaged res://data/staff.json, and falls back to procedurally generated
## staff if neither file is present.
##
## Depends on: StaffData, NationDatabase.
## Exposes: staff_pool, get_staff_for_team(team_name), get_assistant_manager(team_name),
##          get_head_physio(team_name), get_tactical_analyst(team_name),
##          all_available_staff(), save_staff().
##

extends Node

const CUSTOM_STAFF_PATH: String = "user://custom_staff.json"
const DEFAULT_STAFF_PATH: String = "res://data/staff.json"

var staff_pool: Array[StaffData] = []


func _ready() -> void:
	_load_staff()


## Returns all staff assigned to team_name.
func get_staff_for_team(team_name: String) -> Array[StaffData]:
	var result: Array[StaffData] = []
	for s: StaffData in staff_pool:
		if s.team_name == team_name:
			result.append(s)
	return result


## Returns the Assistant Manager for team_name, or creates a fallback if none exists.
func get_assistant_manager(team_name: String) -> StaffData:
	for s: StaffData in staff_pool:
		if s.team_name == team_name and s.role.nocasecmp_to("Assistant Manager") == 0:
			return s
	return _make_fallback_staff(team_name, "Assistant Manager")


## Returns the Head Physio for team_name, or creates a fallback if none exists.
func get_head_physio(team_name: String) -> StaffData:
	for s: StaffData in staff_pool:
		if s.team_name == team_name and s.role.nocasecmp_to("Head Physio") == 0:
			return s
	return _make_fallback_staff(team_name, "Head Physio")


## Returns the Tactical Analyst for team_name, or creates a fallback if none exists.
func get_tactical_analyst(team_name: String) -> StaffData:
	for s: StaffData in staff_pool:
		if s.team_name == team_name and s.role.nocasecmp_to("Tactical Analyst") == 0:
			return s
	return _make_fallback_staff(team_name, "Tactical Analyst")


## Returns all free agent staff (no current team).
func all_available_staff() -> Array[StaffData]:
	var available: Array[StaffData] = []
	for s: StaffData in staff_pool:
		if s.team_name == "":
			available.append(s)
	return available


func save_staff() -> void:
	var staff_list: Array[Dictionary] = []
	for s: StaffData in staff_pool:
		staff_list.append(_staff_to_dict(s))

	var file: FileAccess = FileAccess.open(CUSTOM_STAFF_PATH, FileAccess.WRITE)
	if file == null:
		push_error("StaffLoader: could not open %s for writing (%s)." % [CUSTOM_STAFF_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"staff": staff_list}, "\t"))


func _load_staff() -> void:
	if FileAccess.file_exists(CUSTOM_STAFF_PATH):
		if _parse_json_staff(CUSTOM_STAFF_PATH):
			return
	if FileAccess.file_exists(DEFAULT_STAFF_PATH):
		if _parse_json_staff(DEFAULT_STAFF_PATH):
			return
	_build_default_staff()


func _parse_json_staff(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("staff"):
		return false

	var pool: Array[StaffData] = []
	for item: Variant in (parsed as Dictionary)["staff"]:
		if typeof(item) == TYPE_DICTIONARY:
			pool.append(_staff_from_dict(item as Dictionary))

	staff_pool = pool
	return true


func _staff_from_dict(d: Dictionary) -> StaffData:
	var s := StaffData.new()
	s.staff_name = str(d.get("staff_name", d.get("name", "Unknown Staff")))
	s.role = str(d.get("role", "Assistant Manager"))
	s.team_name = str(d.get("team_name", ""))
	s.nationality = str(d.get("nationality", "English"))
	s.secondary_nationality = str(d.get("secondary_nationality", ""))
	s.date_of_birth = str(d.get("date_of_birth", "1982-01-01"))

	var raw_langs: Variant = d.get("spoken_languages", [])
	var parsed_langs: Array[Dictionary] = []
	if typeof(raw_langs) == TYPE_ARRAY:
		for l_item: Variant in (raw_langs as Array):
			if typeof(l_item) == TYPE_DICTIONARY:
				parsed_langs.append(l_item as Dictionary)
	if parsed_langs.is_empty():
		var prim_lang: String = NationDatabase.get_primary_language_for_nation(s.nationality)
		parsed_langs.append({"language": prim_lang, "proficiency": 1.0, "level": "Native"})
		if prim_lang != "English":
			parsed_langs.append({"language": "English", "proficiency": 0.80, "level": "Fluent"})
	s.spoken_languages = parsed_langs

	s.experience = int(d.get("experience", 20))
	s.coaching = float(d.get("coaching", 0.70))
	s.judging_ability = float(d.get("judging_ability", 0.70))
	s.physiotherapy = float(d.get("physiotherapy", 0.70))
	s.tactical_knowledge = float(d.get("tactical_knowledge", 0.70))
	s.salary_weekly = int(d.get("salary_weekly", 6000))
	s.contract_years = int(d.get("contract_years", 2))
	return s


func _staff_to_dict(s: StaffData) -> Dictionary:
	return {
		"staff_name": s.staff_name,
		"role": s.role,
		"team_name": s.team_name,
		"nationality": s.nationality,
		"secondary_nationality": s.secondary_nationality,
		"date_of_birth": s.date_of_birth,
		"spoken_languages": s.spoken_languages,
		"experience": s.experience,
		"coaching": s.coaching,
		"judging_ability": s.judging_ability,
		"physiotherapy": s.physiotherapy,
		"tactical_knowledge": s.tactical_knowledge,
		"salary_weekly": s.salary_weekly,
		"contract_years": s.contract_years
	}


func _make_fallback_staff(team_name: String, role: String) -> StaffData:
	var s := StaffData.make_default("Coach (%s)" % role, role, "English")
	s.team_name = team_name
	staff_pool.append(s)
	return s


func _build_default_staff() -> void:
	staff_pool.clear()
	# Fallback basic staff pool
	var teams: Array[String] = [
		"FC Nordvik", "CD Solano", "Valence Athletic", "Real Maritimo",
		"Borussia Eisenwald", "Aurora Calcio", "Highland Thistle FC", "Porto Sol Stella"
	]
	var roles: Array[String] = ["Assistant Manager", "Head Physio", "Tactical Analyst"]
	for t: String in teams:
		for r: String in roles:
			var s := StaffData.make_default("%s %s" % [t, r], r, "English")
			s.team_name = t
			staff_pool.append(s)
