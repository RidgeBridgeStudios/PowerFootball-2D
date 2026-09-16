##
## ManagerLoader (Autoload singleton)
##
## Owns the pool of all managers across the save file. Loads custom managers
## from user://custom_managers.json if the file exists, otherwise loads from
## packaged res://data/managers.json, and falls back to built-in programmatic
## managers if neither file is present. CareerManager assigns a manager to each
## team from here for every fixture rather than constructing a ManagerData itself,
## and QuickSimEngine's career stats are persisted back through here.
##
## Depends on: ManagerData.
## Exposes: manager_pool, get_manager_for_team(team_name),
##          get_or_assign_manager(team_name), all_available(), save_managers()
##

extends Node

const CUSTOM_MANAGERS_PATH: String = "user://custom_managers.json"
const DEFAULT_MANAGERS_PATH: String = "res://data/managers.json"
const WORLD_MANAGERS_PATH: String = "res://data/world_managers.json"

var manager_pool: Array[ManagerData] = []


func _ready() -> void:
	_load_managers()


## Returns the manager currently assigned to team_name, or null if no manager
## in the pool has that current_team.
func get_manager_for_team(team_name: String) -> ManagerData:
	for manager: ManagerData in manager_pool:
		if manager.current_team == team_name:
			return manager
	return null


## Returns the manager for team_name, assigning one if none exists yet: the
## highest-experience manager currently available for hire (current_team ==
## ""), or a freshly minted "Unknown" manager if the pool has no one free.
func get_or_assign_manager(team_name: String) -> ManagerData:
	var existing: ManagerData = get_manager_for_team(team_name)
	if existing != null:
		return existing

	var best: ManagerData = null
	for manager: ManagerData in manager_pool:
		if manager.current_team == "":
			if best == null or manager.experience > best.experience:
				best = manager

	if best != null:
		best.current_team = team_name
		return best

	var fresh: ManagerData = ManagerData.make_default("Unknown", "Unknown")
	fresh.current_team = team_name
	manager_pool.append(fresh)
	return fresh


## Returns every manager in the pool currently available for hire.
func all_available() -> Array[ManagerData]:
	var available: Array[ManagerData] = []
	for manager: ManagerData in manager_pool:
		if manager.current_team == "":
			available.append(manager)
	return available


## Writes the live manager pool (including career stats) to
## user://custom_managers.json so progress survives between sessions.
func save_managers() -> void:
	var managers: Array = []
	for manager: ManagerData in manager_pool:
		managers.append(_to_dict(manager))

	var file := FileAccess.open(CUSTOM_MANAGERS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("ManagerLoader: could not open %s for writing (%s)." % [CUSTOM_MANAGERS_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"managers": managers}, "\t"))


func _load_managers() -> void:
	if FileAccess.file_exists(CUSTOM_MANAGERS_PATH):
		if _parse_json_managers(CUSTOM_MANAGERS_PATH):
			return
	if FileAccess.file_exists(WORLD_MANAGERS_PATH):
		if _parse_json_managers(WORLD_MANAGERS_PATH):
			return
	if FileAccess.file_exists(DEFAULT_MANAGERS_PATH):
		if _parse_json_managers(DEFAULT_MANAGERS_PATH):
			return
	_build_default_managers()


## Parses a JSON manager file into `manager_pool`.
func _parse_json_managers(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ManagerLoader: could not open %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false

	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("managers"):
		push_error("ManagerLoader: %s is missing a \"managers\" key." % path)
		return false

	var pool: Array[ManagerData] = []
	for manager_dict: Variant in parsed["managers"]:
		if typeof(manager_dict) != TYPE_DICTIONARY:
			push_error("ManagerLoader: malformed manager entry in %s." % path)
			return false
		pool.append(_from_dict(manager_dict))

	manager_pool = pool
	return true


func _from_dict(d: Dictionary) -> ManagerData:
	var name_str: String = d.get("manager_name", d.get("name", ""))
	if name_str == "" and d.has("first_name"):
		name_str = "%s %s" % [d.get("first_name", ""), d.get("last_name", "")]

	var m := ManagerData.make_default(
		name_str,
		d.get("nationality", "Unknown")
	)
	m.experience = int(d.get("experience", m.experience))
	m.current_team = d.get("current_team", m.current_team)

	m.defensive_line = float(d.get("defensive_line", m.defensive_line))
	m.tempo = float(d.get("tempo", d.get("base_tempo", m.tempo)))
	m.width = float(d.get("width", m.width))
	m.pressing_intensity = float(d.get("pressing_intensity", m.pressing_intensity))
	m.physicality = float(d.get("physicality", m.physicality))

	m.preferred_formation = d.get("preferred_formation", m.preferred_formation)
	m.attacking_formation = d.get("attacking_formation", m.attacking_formation)
	m.defensive_formation = d.get("defensive_formation", m.defensive_formation)

	m.youth_trust = float(d.get("youth_trust", m.youth_trust))
	m.loyalty_bias = float(d.get("loyalty_bias", m.loyalty_bias))
	m.form_sensitivity = float(d.get("form_sensitivity", m.form_sensitivity))

	m.preferred_min_age = int(d.get("preferred_min_age", m.preferred_min_age))
	m.preferred_max_age = int(d.get("preferred_max_age", m.preferred_max_age))
	m.budget_flexibility = float(d.get("budget_flexibility", m.budget_flexibility))
	m.preferred_mass_min = float(d.get("preferred_mass_min", m.preferred_mass_min))
	m.preferred_mass_max = float(d.get("preferred_mass_max", m.preferred_mass_max))
	m.prized_attribute = d.get("prized_attribute", m.prized_attribute)
	m.preferred_playstyle = d.get("preferred_playstyle", m.preferred_playstyle)

	m.traits = int(d.get("traits", d.get("trait_bits", m.traits)))

	m.reputation = float(d.get("reputation", m.reputation))
	m.board_confidence = float(d.get("board_confidence", m.board_confidence))
	m.contract_years = int(d.get("contract_years", m.contract_years))
	m.salary_weekly = int(d.get("salary_weekly", m.salary_weekly))
	m.referee_respect = float(d.get("referee_respect", m.referee_respect))

	m.matches_managed = int(d.get("matches_managed", m.matches_managed))
	m.wins = int(d.get("wins", m.wins))
	m.draws = int(d.get("draws", m.draws))
	m.losses = int(d.get("losses", m.losses))
	m.goals_scored = int(d.get("goals_scored", m.goals_scored))
	m.goals_conceded = int(d.get("goals_conceded", m.goals_conceded))
	m.secondary_nationality = str(d.get("secondary_nationality", m.secondary_nationality))
	m.date_of_birth = str(d.get("date_of_birth", m.date_of_birth))

	var raw_langs: Variant = d.get("spoken_languages", [])
	var parsed_langs: Array[Dictionary] = []
	if typeof(raw_langs) == TYPE_ARRAY:
		for l_item: Variant in (raw_langs as Array):
			if typeof(l_item) == TYPE_DICTIONARY:
				parsed_langs.append(l_item as Dictionary)
	if not parsed_langs.is_empty():
		m.spoken_languages = parsed_langs
	else:
		var prim_lang: String = NationDatabase.get_primary_language_for_nation(m.nationality)
		m.spoken_languages = [
			{"language": prim_lang, "proficiency": 1.0, "level": "Native"},
			{"language": "English", "proficiency": 0.85, "level": "Fluent"}
		]
	return m


func _to_dict(m: ManagerData) -> Dictionary:
	return {
		"name": m.manager_name,
		"nationality": m.nationality,
		"secondary_nationality": m.secondary_nationality,
		"date_of_birth": m.date_of_birth,
		"spoken_languages": m.spoken_languages,
		"experience": m.experience,
		"current_team": m.current_team,
		"reputation": m.reputation,
		"board_confidence": m.board_confidence,
		"contract_years": m.contract_years,
		"salary_weekly": m.salary_weekly,
		"referee_respect": m.referee_respect,
		"defensive_line": m.defensive_line,
		"tempo": m.tempo,
		"width": m.width,
		"pressing_intensity": m.pressing_intensity,
		"physicality": m.physicality,
		"preferred_formation": m.preferred_formation,
		"attacking_formation": m.attacking_formation,
		"defensive_formation": m.defensive_formation,
		"youth_trust": m.youth_trust,
		"loyalty_bias": m.loyalty_bias,
		"form_sensitivity": m.form_sensitivity,
		"preferred_min_age": m.preferred_min_age,
		"preferred_max_age": m.preferred_max_age,
		"budget_flexibility": m.budget_flexibility,
		"preferred_mass_min": m.preferred_mass_min,
		"preferred_mass_max": m.preferred_mass_max,
		"prized_attribute": m.prized_attribute,
		"preferred_playstyle": m.preferred_playstyle,
		"traits": m.traits,
		"matches_managed": m.matches_managed,
		"wins": m.wins,
		"draws": m.draws,
		"losses": m.losses,
		"goals_scored": m.goals_scored,
		"goals_conceded": m.goals_conceded,
	}


## --- Built-in manager pool --------------------------------------------------

func _build_default_managers() -> void:
	manager_pool = [
		_skok(),
		_larrarte(),
		_peet(),
		_tsurumoto(),
		_klausner(),
		_bellini(),
		_maccallum(),
		_cruz(),
		_pendelton(),
		_wilczek()
	]


func _skok() -> ManagerData:
	var m := ManagerData.make_default("Branimir Skok", "Croatian")
	m.experience = 28
	m.current_team = "FC Nordvik"
	m.defensive_line = 0.35
	m.tempo = 0.40
	m.width = 0.42
	m.pressing_intensity = 0.30
	m.physicality = 0.72
	m.preferred_formation = "4-4-2"
	m.attacking_formation = "4-3-3"
	m.defensive_formation = "5-3-2"
	m.youth_trust = 0.25
	m.loyalty_bias = 0.80
	m.form_sensitivity = 0.30
	m.preferred_min_age = 23
	m.preferred_max_age = 33
	m.budget_flexibility = 0.30
	m.preferred_mass_min = 74.0
	m.preferred_mass_max = 95.0
	m.prized_attribute = "aggression"
	m.preferred_playstyle = "physical"
	m.traits = 1 | 2 | 4 # HotHead | Loyalist | Pragmatist
	return m


func _larrarte() -> ManagerData:
	var m := ManagerData.make_default("Sebastián Larrarte", "Argentine")
	m.experience = 41
	m.current_team = "CD Solano"
	m.defensive_line = 0.72
	m.tempo = 0.78
	m.width = 0.82
	m.pressing_intensity = 0.88
	m.physicality = 0.32
	m.preferred_formation = "4-3-3"
	m.attacking_formation = "4-3-3"
	m.defensive_formation = "4-4-2"
	m.youth_trust = 0.80
	m.loyalty_bias = 0.30
	m.form_sensitivity = 0.75
	m.preferred_min_age = 17
	m.preferred_max_age = 26
	m.budget_flexibility = 0.65
	m.preferred_mass_min = 60.0
	m.preferred_mass_max = 80.0
	m.prized_attribute = "vision"
	m.preferred_playstyle = "technical"
	m.traits = 8 | 128 | 32 # Visionary | MediaSavvy | MindGames
	return m


func _peet() -> ManagerData:
	var m := ManagerData.make_default("Raivo Peet", "Dutch")
	m.experience = 19
	m.current_team = "Valence Athletic"
	m.defensive_line = 0.55
	m.tempo = 0.58
	m.width = 0.50
	m.pressing_intensity = 0.62
	m.physicality = 0.55
	m.preferred_formation = "4-2-3-1"
	m.attacking_formation = "4-3-3"
	m.defensive_formation = "4-4-2"
	m.youth_trust = 0.50
	m.loyalty_bias = 0.40
	m.form_sensitivity = 0.72
	m.preferred_min_age = 19
	m.preferred_max_age = 29
	m.budget_flexibility = 0.50
	m.preferred_mass_min = 67.0
	m.preferred_mass_max = 85.0
	m.prized_attribute = "composure"
	m.preferred_playstyle = "engine"
	m.traits = 16 | 4 # Disciplinarian | Pragmatist
	return m


func _tsurumoto() -> ManagerData:
	var m := ManagerData.make_default("Yuki Tsurumoto", "Japanese")
	m.experience = 35
	m.current_team = "Real Maritimo"
	m.defensive_line = 0.60
	m.tempo = 0.55
	m.width = 0.70
	m.pressing_intensity = 0.50
	m.physicality = 0.25
	m.preferred_formation = "3-5-2"
	m.attacking_formation = "3-5-2"
	m.defensive_formation = "5-3-2"
	m.youth_trust = 0.70
	m.loyalty_bias = 0.55
	m.form_sensitivity = 0.45
	m.preferred_min_age = 21
	m.preferred_max_age = 30
	m.budget_flexibility = 0.82
	m.preferred_mass_min = 62.0
	m.preferred_mass_max = 82.0
	m.prized_attribute = "vision"
	m.preferred_playstyle = "pace"
	m.traits = 64 | 128 | 8 # Sentimental | MediaSavvy | Visionary
	return m


func _klausner() -> ManagerData:
	var m := ManagerData.make_default("Dietrich Klausner", "German")
	m.experience = 32
	m.current_team = "Borussia Eisenwald"
	m.defensive_line = 0.28
	m.tempo = 0.45
	m.width = 0.38
	m.pressing_intensity = 0.40
	m.physicality = 0.85
	m.preferred_formation = "5-3-2"
	m.attacking_formation = "4-3-3"
	m.defensive_formation = "5-3-2"
	m.youth_trust = 0.30
	m.loyalty_bias = 0.75
	m.form_sensitivity = 0.40
	m.preferred_min_age = 24
	m.preferred_max_age = 34
	m.budget_flexibility = 0.40
	m.preferred_mass_min = 78.0
	m.preferred_mass_max = 96.0
	m.prized_attribute = "aggression"
	m.preferred_playstyle = "physical"
	m.traits = 16 | 2 | 4 # Disciplinarian | Loyalist | Pragmatist
	return m


func _bellini() -> ManagerData:
	var m := ManagerData.make_default("Giancarlo Bellini", "Italian")
	m.experience = 38
	m.current_team = "Aurora Calcio"
	m.defensive_line = 0.68
	m.tempo = 0.65
	m.width = 0.75
	m.pressing_intensity = 0.70
	m.physicality = 0.35
	m.preferred_formation = "4-3-3"
	m.attacking_formation = "4-3-3"
	m.defensive_formation = "4-4-2"
	m.youth_trust = 0.65
	m.loyalty_bias = 0.35
	m.form_sensitivity = 0.60
	m.preferred_min_age = 20
	m.preferred_max_age = 29
	m.budget_flexibility = 0.75
	m.preferred_mass_min = 64.0
	m.preferred_mass_max = 84.0
	m.prized_attribute = "vision"
	m.preferred_playstyle = "technical"
	m.traits = 8 | 128 | 512 # Visionary | MediaSavvy | Idealist
	return m


func _maccallum() -> ManagerData:
	var m := ManagerData.make_default("Alistair MacCallum", "Scottish")
	m.experience = 26
	m.current_team = "Highland Thistle FC"
	m.defensive_line = 0.48
	m.tempo = 0.75
	m.width = 0.55
	m.pressing_intensity = 0.85
	m.physicality = 0.90
	m.preferred_formation = "4-4-2"
	m.attacking_formation = "4-4-2"
	m.defensive_formation = "5-3-2"
	m.youth_trust = 0.40
	m.loyalty_bias = 0.65
	m.form_sensitivity = 0.50
	m.preferred_min_age = 22
	m.preferred_max_age = 32
	m.budget_flexibility = 0.35
	m.preferred_mass_min = 74.0
	m.preferred_mass_max = 94.0
	m.prized_attribute = "aggression"
	m.preferred_playstyle = "engine"
	m.traits = 1 | 16 | 4 # HotHead | Disciplinarian | Pragmatist
	return m


func _cruz() -> ManagerData:
	var m := ManagerData.make_default("Valdemar Cruz", "Portuguese")
	m.experience = 29
	m.current_team = "Porto Sol Stella"
	m.defensive_line = 0.62
	m.tempo = 0.70
	m.width = 0.78
	m.pressing_intensity = 0.65
	m.physicality = 0.40
	m.preferred_formation = "4-2-3-1"
	m.attacking_formation = "4-3-3"
	m.defensive_formation = "4-4-2"
	m.youth_trust = 0.75
	m.loyalty_bias = 0.30
	m.form_sensitivity = 0.65
	m.preferred_min_age = 18
	m.preferred_max_age = 28
	m.budget_flexibility = 0.70
	m.preferred_mass_min = 63.0
	m.preferred_mass_max = 82.0
	m.prized_attribute = "composure"
	m.preferred_playstyle = "technical"
	m.traits = 256 | 8 | 32 # Volatile | Visionary | MindGames
	return m


func _pendelton() -> ManagerData:
	var m := ManagerData.make_default("Arthur Pendelton", "English")
	m.experience = 45
	m.current_team = ""
	m.defensive_line = 0.42
	m.tempo = 0.50
	m.width = 0.48
	m.pressing_intensity = 0.45
	m.physicality = 0.65
	m.preferred_formation = "4-4-2"
	m.attacking_formation = "4-3-3"
	m.defensive_formation = "5-4-1"
	m.youth_trust = 0.35
	m.loyalty_bias = 0.85
	m.form_sensitivity = 0.25
	m.preferred_min_age = 25
	m.preferred_max_age = 35
	m.budget_flexibility = 0.45
	m.preferred_mass_min = 72.0
	m.preferred_mass_max = 92.0
	m.prized_attribute = "composure"
	m.preferred_playstyle = "physical"
	m.traits = 2 | 4 | 64 # Loyalist | Pragmatist | Sentimental
	return m


func _wilczek() -> ManagerData:
	var m := ManagerData.make_default("Mateusz Wilczek", "Polish")
	m.experience = 22
	m.current_team = ""
	m.defensive_line = 0.65
	m.tempo = 0.80
	m.width = 0.60
	m.pressing_intensity = 0.92
	m.physicality = 0.68
	m.preferred_formation = "4-3-3"
	m.attacking_formation = "4-3-3"
	m.defensive_formation = "4-4-2"
	m.youth_trust = 0.85
	m.loyalty_bias = 0.20
	m.form_sensitivity = 0.80
	m.preferred_min_age = 18
	m.preferred_max_age = 26
	m.budget_flexibility = 0.60
	m.preferred_mass_min = 66.0
	m.preferred_mass_max = 86.0
	m.prized_attribute = "aggression"
	m.preferred_playstyle = "engine"
	m.traits = 1 | 8 | 128 # HotHead | Visionary | MediaSavvy
	return m
