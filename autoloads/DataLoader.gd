##
## DataLoader (Autoload singleton)
##
## Owns the live league data. Loads a custom league from user://custom_league.json
## if one exists, otherwise builds the two built-in placeholder teams. Everything
## else — PitchScene, PlayerFactory — reads squad data through this rather than
## touching a Resource file directly, so a future roster editor only has to
## change what is written to user://custom_league.json.
##
## Depends on: PlayerData, TeamData, LeagueData.
## Exposes: league, get_team(index), get_player(team_index, squad_index)
##

extends Node

const CUSTOM_LEAGUE_PATH: String = "user://custom_league.json"

var league: LeagueData = null


func _ready() -> void:
	_load_league()


func get_team(index: int) -> TeamData:
	if league == null or index < 0 or index >= league.teams.size():
		push_warning("DataLoader.get_team: index %d out of bounds." % index)
		return null
	return league.teams[index]


func get_player(team_index: int, squad_index: int) -> PlayerData:
	var team: TeamData = get_team(team_index)
	if team == null or squad_index < 0 or squad_index >= team.squad.size():
		push_warning("DataLoader.get_player: squad index %d out of bounds for team %d." % [squad_index, team_index])
		return null
	return team.squad[squad_index]


func _load_league() -> void:
	if FileAccess.file_exists(CUSTOM_LEAGUE_PATH):
		if _parse_json_league(CUSTOM_LEAGUE_PATH):
			return
	_build_default_league()


## Parses a JSON league file into the live `league`. Parses into a local var
## first so a malformed file can never leave `league` half-overwritten. Returns
## false on any error (and pushes an error naming the path) — `_load_league()`
## falls back to the built-in placeholder league when this returns false.
func _parse_json_league(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: could not open %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false

	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("teams"):
		push_error("DataLoader: %s is missing a \"teams\" key." % path)
		return false

	var parsed_league := LeagueData.new()
	parsed_league.league_name = parsed.get("league_name", "")

	var teams: Array[TeamData] = []
	for team_dict: Variant in parsed["teams"]:
		if typeof(team_dict) != TYPE_DICTIONARY:
			push_error("DataLoader: malformed team entry in %s." % path)
			return false
		teams.append(_team_from_dict(team_dict))
	parsed_league.teams = teams

	league = parsed_league
	return true


func _team_from_dict(team_dict: Dictionary) -> TeamData:
	var team := TeamData.new()
	team.team_name = team_dict.get("team_name", "")
	var color_array: Array = team_dict.get("team_color", [1.0, 1.0, 1.0])
	team.team_color = Color(color_array[0], color_array[1], color_array[2])

	var squad: Array[PlayerData] = []
	for player_dict: Variant in team_dict.get("squad", []):
		squad.append(_player_from_dict(player_dict))
	team.squad = squad
	return team


func _player_from_dict(player_dict: Dictionary) -> PlayerData:
	var data := PlayerData.make_default(
		player_dict.get("player_name", ""),
		player_dict.get("shirt_number", 0),
		player_dict.get("position_role", "")
	)
	data.mass = player_dict.get("mass", data.mass)
	data.top_speed = player_dict.get("top_speed", data.top_speed)
	data.acceleration_time = player_dict.get("acceleration_time", data.acceleration_time)
	data.friction_time = player_dict.get("friction_time", data.friction_time)
	data.turning_penalty = player_dict.get("turning_penalty", data.turning_penalty)
	data.sprint_multiplier = player_dict.get("sprint_multiplier", data.sprint_multiplier)
	data.stamina_max = player_dict.get("stamina_max", data.stamina_max)
	data.stamina_drain = player_dict.get("stamina_drain", data.stamina_drain)
	data.stamina_recover = player_dict.get("stamina_recover", data.stamina_recover)
	data.vision = player_dict.get("vision", data.vision)
	data.composure = player_dict.get("composure", data.composure)
	data.aggression = player_dict.get("aggression", data.aggression)
	data.formation_ball_weight = player_dict.get("formation_ball_weight", data.formation_ball_weight)
	return data


func _build_default_league() -> void:
	var default_league := LeagueData.new()
	default_league.league_name = "Placeholder League"
	default_league.teams = [_build_nordvik(), _build_solano()]
	league = default_league


## --- Placeholder squads --------------------------------------------------------

func _build_nordvik() -> TeamData:
	var team := TeamData.new()
	team.team_name = "FC Nordvik"
	team.team_color = Color(0.18, 0.32, 0.72)
	team.squad = [
		_player(1, "Mads Dahl", "GK", 82.0, 175.0, 0.80, 0.30, 0.55, 1.30, 0.80, 0.85, 0.30),
		_player(5, "Halvard Brann", "CB", 92.0, 185.0, 0.90, 0.28, 0.85, 1.25, 0.60, 0.75, 0.70),
		_player(4, "Sigurd Voss", "CB", 88.0, 188.0, 0.85, 0.29, 0.80, 1.28, 0.65, 0.70, 0.65),
		_player(3, "Erik Lund", "LB", 77.0, 210.0, 0.68, 0.34, 0.72, 1.42, 0.70, 0.60, 0.55),
		_player(2, "Torben Hauge", "RB", 76.0, 212.0, 0.67, 0.34, 0.70, 1.43, 0.72, 0.62, 0.58),
		_player(6, "Niklas Borg", "DM", 80.0, 200.0, 0.72, 0.32, 0.78, 1.35, 0.82, 0.78, 0.72),
		_player(8, "Olav Strand", "CM", 74.0, 208.0, 0.66, 0.35, 0.68, 1.40, 0.85, 0.72, 0.60),
		_player(10, "Petter Naess", "AM", 71.0, 215.0, 0.62, 0.37, 0.62, 1.48, 0.90, 0.80, 0.55),
		_player(11, "Jonas Elv", "LW", 69.0, 228.0, 0.58, 0.38, 0.60, 1.52, 0.75, 0.55, 0.62),
		_player(7, "Rune Kval", "RW", 70.0, 225.0, 0.59, 0.38, 0.62, 1.50, 0.73, 0.58, 0.65),
		_player(9, "Henrik Ask", "ST", 83.0, 220.0, 0.70, 0.33, 0.65, 1.50, 0.68, 0.65, 0.88),
	]
	return team


func _build_solano() -> TeamData:
	var team := TeamData.new()
	team.team_name = "CD Solano"
	team.team_color = Color(0.72, 0.14, 0.18)
	team.squad = [
		_player(1, "Carlos Vega", "GK", 80.0, 172.0, 0.82, 0.29, 0.50, 1.28, 0.78, 0.88, 0.25),
		_player(5, "Mateo Ruiz", "CB", 87.0, 190.0, 0.84, 0.29, 0.82, 1.27, 0.62, 0.72, 0.68),
		_player(4, "Diego Pons", "CB", 90.0, 186.0, 0.88, 0.28, 0.83, 1.26, 0.58, 0.68, 0.72),
		_player(3, "Luis Ferrer", "LB", 74.0, 218.0, 0.63, 0.36, 0.65, 1.48, 0.74, 0.64, 0.52),
		_player(2, "Andres Mora", "RB", 75.0, 216.0, 0.64, 0.35, 0.66, 1.46, 0.71, 0.62, 0.54),
		_player(6, "Pablo Cano", "DM", 79.0, 202.0, 0.71, 0.33, 0.76, 1.36, 0.80, 0.76, 0.75),
		_player(8, "Rafael Soto", "CM", 73.0, 212.0, 0.64, 0.36, 0.65, 1.42, 0.83, 0.74, 0.58),
		_player(10, "Marco Reyes", "AM", 70.0, 218.0, 0.61, 0.38, 0.60, 1.50, 0.92, 0.82, 0.52),
		_player(11, "Javier Tur", "LW", 67.0, 258.0, 0.55, 0.40, 0.55, 1.58, 0.65, 0.45, 0.70),
		_player(7, "Ivan Blasco", "RW", 68.0, 245.0, 0.57, 0.39, 0.58, 1.55, 0.68, 0.50, 0.68),
		_player(9, "Bruno Tena", "ST", 81.0, 222.0, 0.68, 0.34, 0.62, 1.52, 0.70, 0.68, 0.85),
	]
	return team


## Shared constructor for the two placeholder squads. `stamina_max = 100.0`,
## `stamina_drain = 18.0`, `stamina_recover = 9.0` and `formation_ball_weight =
## 0.35` are the defaults for every player on both teams — no player-specific
## override makes gameplay sense for them yet.
func _player(
	shirt_number: int, player_name: String, position_role: String,
	mass: float, top_speed: float, acceleration_time: float, friction_time: float,
	turning_penalty: float, sprint_multiplier: float,
	vision: float, composure: float, aggression: float
) -> PlayerData:
	var data := PlayerData.make_default(player_name, shirt_number, position_role)
	data.mass = mass
	data.top_speed = top_speed
	data.acceleration_time = acceleration_time
	data.friction_time = friction_time
	data.turning_penalty = turning_penalty
	data.sprint_multiplier = sprint_multiplier
	data.vision = vision
	data.composure = composure
	data.aggression = aggression
	data.stamina_max = 100.0
	data.stamina_drain = 18.0
	data.stamina_recover = 9.0
	data.formation_ball_weight = 0.35
	return data
