##
## ManagerLoader (Autoload singleton)
##
## Owns the pool of all managers across the save file. Loads custom managers
## from user://custom_managers.json if the file exists, otherwise builds the
## four built-in managers. PitchScene assigns a manager to each team from
## here at match start rather than constructing a ManagerData itself, and
## writes career stats back through here after every match — the same
## database-loader pattern DataLoader and RefereeLoader use, so a future
## manager editor only has to change what is written to
## user://custom_managers.json.
##
## Depends on: ManagerData. DataLoader is not read at load time — only
## get_or_assign_manager() callers pass in a team name, so no autoload
## ordering dependency exists beyond being declared after DataLoader in
## project.godot.
## Exposes: manager_pool, get_manager_for_team(team_name),
##          get_or_assign_manager(team_name), all_available(), save_managers()
##

extends Node

const CUSTOM_MANAGERS_PATH: String = "user://custom_managers.json"

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
	_build_default_managers()


## Parses a JSON manager file into `manager_pool`. Parses into a local var
## first so a malformed file can never leave `manager_pool` half-overwritten.
## Returns false on any error (and pushes an error naming the path) —
## `_load_managers()` falls back to the built-in manager pool when this
## returns false.
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
	var m := ManagerData.make_default(
		d.get("name", ""),
		d.get("nationality", "")
	)
	m.experience = d.get("experience", m.experience)
	m.current_team = d.get("current_team", m.current_team)

	m.defensive_line = d.get("defensive_line", m.defensive_line)
	m.tempo = d.get("tempo", m.tempo)
	m.width = d.get("width", m.width)
	m.pressing_intensity = d.get("pressing_intensity", m.pressing_intensity)
	m.physicality = d.get("physicality", m.physicality)

	m.preferred_formation = d.get("preferred_formation", m.preferred_formation)
	m.attacking_formation = d.get("attacking_formation", m.attacking_formation)
	m.defensive_formation = d.get("defensive_formation", m.defensive_formation)

	m.youth_trust = d.get("youth_trust", m.youth_trust)
	m.loyalty_bias = d.get("loyalty_bias", m.loyalty_bias)
	m.form_sensitivity = d.get("form_sensitivity", m.form_sensitivity)

	m.preferred_min_age = d.get("preferred_min_age", m.preferred_min_age)
	m.preferred_max_age = d.get("preferred_max_age", m.preferred_max_age)
	m.budget_flexibility = d.get("budget_flexibility", m.budget_flexibility)
	m.preferred_mass_min = d.get("preferred_mass_min", m.preferred_mass_min)
	m.preferred_mass_max = d.get("preferred_mass_max", m.preferred_mass_max)
	m.prized_attribute = d.get("prized_attribute", m.prized_attribute)
	m.preferred_playstyle = d.get("preferred_playstyle", m.preferred_playstyle)

	m.traits = int(d.get("traits", m.traits))

	m.matches_managed = d.get("matches_managed", m.matches_managed)
	m.wins = d.get("wins", m.wins)
	m.draws = d.get("draws", m.draws)
	m.losses = d.get("losses", m.losses)
	m.goals_scored = d.get("goals_scored", m.goals_scored)
	m.goals_conceded = d.get("goals_conceded", m.goals_conceded)
	return m


func _to_dict(m: ManagerData) -> Dictionary:
	return {
		"name": m.manager_name,
		"nationality": m.nationality,
		"experience": m.experience,
		"current_team": m.current_team,
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
	]


## A physical, defensive-minded veteran who is intensely loyal to his senior
## players, never plays youth, and becomes volatile in the press when things
## go wrong. Does not believe in pretty football.
func _skok() -> ManagerData:
	var m := ManagerData.make_default("Branimir Skok", "Dalmatian")
	m.experience = 28
	m.current_team = "Nordvik FC"
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


## A sophisticated high-press possession coach who builds from the youth,
## rotates ruthlessly on form, and is calculatedly charming in the media while
## quietly working to destabilise opponents pre-match.
func _larrarte() -> ManagerData:
	var m := ManagerData.make_default("Sebastián Larrarte", "Platense")
	m.experience = 41
	m.current_team = "FC Solano"
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


## A young, structured head-coach type. Demands discipline and high work-rate.
## Gives away nothing in the press. Results-only mindset with a sharp eye for
## composed box-to-box players.
func _peet() -> ManagerData:
	var m := ManagerData.make_default("Raivo Peet", "Hanseatic")
	m.experience = 17
	m.current_team = ""
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


## A warm, philosophically-inclined coach who plays a wide positional game,
## spends freely, and produces genuinely emotional press conferences that
## consistently win the crowd over.
func _tsurumoto() -> ManagerData:
	var m := ManagerData.make_default("Yuki Tsurumoto", "Far Eastern")
	m.experience = 35
	m.current_team = ""
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
	m.prized_attribute = "none"
	m.preferred_playstyle = "pace"
	m.traits = 64 | 128 | 8 # Sentimental | MediaSavvy | Visionary
	return m
