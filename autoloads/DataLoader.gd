##
## DataLoader (Autoload singleton)
##
## Owns the live league data. Loads custom league from user://custom_league.json
## if one exists, otherwise loads from packaged res://data/league.json, and
## falls back to built-in programmatic squads if neither file is present.
## PitchScene, PlayerFactory, and UI screens read squad data through this rather
## than touching a Resource file directly.
##
## Depends on: PlayerData, TeamData, LeagueData.
## Exposes: league, get_team(index), get_match_team(match_team_index),
##          get_player(team_index, squad_index), save_league(path)
##
## get_team()/get_player() never return null, even for an index a loaded
## league doesn't cover — they fall back to a procedurally generated placeholder
## instead, so callers like PitchScene._bind_players() can iterate without null
## checks or crashes.
##

extends Node

const CUSTOM_LEAGUE_PATH: String = "user://custom_league.json"
const DEFAULT_LEAGUE_PATH: String = "res://data/league.json"

var league: LeagueData = null


func _ready() -> void:
	_load_league()


## Returns the TeamData for a given league index, falling back to a placeholder
## if the index is out of bounds.
func get_team(index: int) -> TeamData:
	if league == null or index < 0 or index >= league.teams.size():
		push_warning("DataLoader.get_team: index %d out of bounds; using a fallback team." % index)
		return _make_fallback_team(index)
	return league.teams[index]


## Returns the TeamData matching team_name, or null if not found.
func get_team_by_name(team_name: String) -> TeamData:
	if league == null:
		return null
	for t: TeamData in league.teams:
		if t.team_name == team_name:
			return t
	return null


## Returns the TeamData assigned to match side TEAM_A or TEAM_B, respecting
## any home/away team index selection metadata set on GameManager by KickOffMenu.
func get_match_team(match_side: int) -> TeamData:
	if match_side == GameManager.TEAM_A and GameManager.has_meta(&"home_team_index"):
		return get_team(int(GameManager.get_meta(&"home_team_index")))
	elif match_side == GameManager.TEAM_B and GameManager.has_meta(&"away_team_index"):
		return get_team(int(GameManager.get_meta(&"away_team_index")))
	return get_team(match_side)


## Returns a PlayerData from a team's squad. Automatically maps match side (0/1)
## to the selected team index if GameManager metadata is set.
func get_player(team_index: int, squad_index: int) -> PlayerData:
	var real_team_idx: int = team_index
	if team_index == GameManager.TEAM_A and GameManager.has_meta(&"home_team_index"):
		real_team_idx = int(GameManager.get_meta(&"home_team_index"))
	elif team_index == GameManager.TEAM_B and GameManager.has_meta(&"away_team_index"):
		real_team_idx = int(GameManager.get_meta(&"away_team_index"))

	var team: TeamData = get_team(real_team_idx)
	if squad_index < 0 or squad_index >= team.squad.size():
		push_warning("DataLoader.get_player: squad index %d out of bounds for team %d; using a fallback player." % [squad_index, real_team_idx])
		return _make_fallback_player(squad_index)
	return team.squad[squad_index]


## Placeholder squad used when a team index has no real data — an 18-player
## squad with 11 starters and 7 bench players.
func _make_fallback_team(index: int) -> TeamData:
	var team := TeamData.new()
	team.team_name = "Team %d" % (index + 1)
	team.team_color = Color(0.25, 0.55, 1.0) if index == 0 else Color(1.0, 0.35, 0.25)
	team.secondary_color = Color(0.95, 0.95, 0.95)
	team.gk_color = Color(0.15, 0.88, 0.45)

	var squad: Array[PlayerData] = []
	var roles: Array[String] = ["GK", "LB", "CB", "CB", "RB", "LM", "CM", "DM", "RM", "ST", "ST", "GK", "CB", "RB", "CM", "AM", "ST", "CB"]
	for i in range(roles.size()):
		var p: PlayerData = _make_fallback_player(i, roles[i])
		if i == 2:
			p.is_captain = true
		squad.append(p)
	team.squad = squad

	var default_lineup: Array[int] = []
	for i in range(11):
		default_lineup.append(i)
	team.lineup_indices = default_lineup
	return team


## Sensible neutral defaults matching FM2D reference compromise constants.
func _make_fallback_player(index: int, role: String = "CM") -> PlayerData:
	var data := PlayerData.make_default("Player %d" % (index + 1), index + 1, role)
	data.mass = 75.0
	data.top_speed = 210.0
	data.acceleration_time = 0.22
	data.friction_time = 0.12
	data.turning_penalty = 0.35
	data.sprint_multiplier = 1.45
	data.stamina_max = 100.0
	data.stamina_drain = 18.0
	data.stamina_recover = 9.0
	data.vision = 0.60
	data.composure = 0.60
	data.aggression = 0.60
	data.formation_ball_weight = 0.35
	data.close_control = 0.65
	data.reflexes = 0.60
	data.form = 6.5
	data.nationality = "Norwegian"
	data.date_of_birth = "2001-05-15"
	data.spoken_languages = [
		{"language": "Norwegian", "proficiency": 1.0, "level": "Native"},
		{"language": "English", "proficiency": 0.75, "level": "Fluent"}
	]
	return data


## Loads a league from an explicit path, replacing the live one. Used by
## CareerSerializer to restore the squads belonging to a career save slot —
## every career save keeps its own league.json, so two slots can diverge
## (different transfers, different youth intakes) without contaminating each
## other or the packaged default.
##
## Returns false and leaves the current league untouched if the file is
## missing or malformed, so a bad slot never leaves the game with no squads.
func load_league_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("DataLoader.load_league_from: %s does not exist." % path)
		return false
	return _parse_json_league(path)


func _load_league() -> void:
	if FileAccess.file_exists(CUSTOM_LEAGUE_PATH):
		if _parse_json_league(CUSTOM_LEAGUE_PATH):
			return
	if FileAccess.file_exists(DEFAULT_LEAGUE_PATH):
		if _parse_json_league(DEFAULT_LEAGUE_PATH):
			return
	_build_default_league()


## Parses a JSON league file into the live `league`.
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
	parsed_league.league_name = parsed.get("league_name", "League")

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
	team.team_name = team_dict.get("team_name", "Unnamed Team")

	if team_dict.has("team_color"):
		var raw_color: Variant = team_dict["team_color"]
		if typeof(raw_color) == TYPE_ARRAY:
			var c_pri_arr: Array = raw_color
			if c_pri_arr.size() >= 4:
				team.team_color = Color(float(c_pri_arr[0]), float(c_pri_arr[1]), float(c_pri_arr[2]), float(c_pri_arr[3]))
			elif c_pri_arr.size() >= 3:
				team.team_color = Color(float(c_pri_arr[0]), float(c_pri_arr[1]), float(c_pri_arr[2]))
			else:
				team.team_color = Color.WHITE
		elif typeof(raw_color) == TYPE_STRING:
			team.team_color = Color.from_string(String(raw_color), Color.WHITE)
	elif team_dict.has("primary_color"):
		team.team_color = Color.from_string(String(team_dict["primary_color"]), Color.WHITE)
	else:
		team.team_color = Color.WHITE

	if team_dict.has("secondary_color"):
		var raw_sec: Variant = team_dict["secondary_color"]
		if typeof(raw_sec) == TYPE_STRING:
			team.secondary_color = Color.from_string(String(raw_sec), Color.WHITE)
		elif typeof(raw_sec) == TYPE_ARRAY:
			var c_sec_arr: Array = raw_sec
			if c_sec_arr.size() >= 4:
				team.secondary_color = Color(float(c_sec_arr[0]), float(c_sec_arr[1]), float(c_sec_arr[2]), float(c_sec_arr[3]))
			elif c_sec_arr.size() >= 3:
				team.secondary_color = Color(float(c_sec_arr[0]), float(c_sec_arr[1]), float(c_sec_arr[2]))
			else:
				team.secondary_color = Color.WHITE
		else:
			team.secondary_color = Color.WHITE
	else:
		team.secondary_color = Color.WHITE

	if team_dict.has("gk_color"):
		var raw_gk: Variant = team_dict["gk_color"]
		if typeof(raw_gk) == TYPE_STRING:
			team.gk_color = Color.from_string(String(raw_gk), Color(0.12, 0.78, 0.42, 1.0))
		elif typeof(raw_gk) == TYPE_ARRAY:
			var c_gk_arr: Array = raw_gk
			if c_gk_arr.size() >= 4:
				team.gk_color = Color(float(c_gk_arr[0]), float(c_gk_arr[1]), float(c_gk_arr[2]), float(c_gk_arr[3]))
			elif c_gk_arr.size() >= 3:
				team.gk_color = Color(float(c_gk_arr[0]), float(c_gk_arr[1]), float(c_gk_arr[2]))
			else:
				team.gk_color = _generate_contrasting_gk_color(team.team_color)
		else:
			team.gk_color = _generate_contrasting_gk_color(team.team_color)
	else:
		team.gk_color = _generate_contrasting_gk_color(team.team_color)

	team.formation_override = team_dict.get("formation_override", "")
	team.substitutions_made = int(team_dict.get("substitutions_made", 0))
	team.reputation = float(team_dict.get("reputation", team.reputation))
	team.stature = str(team_dict.get("stature", team.get_stature_from_reputation()))
	team.transfer_budget = int(team_dict.get("transfer_budget", team.transfer_budget))
	team.wage_budget_weekly = int(team_dict.get("wage_budget_weekly", team.wage_budget_weekly))

	var squad: Array[PlayerData] = []
	var has_captain: bool = false
	for player_dict: Variant in team_dict.get("squad", []):
		if typeof(player_dict) == TYPE_DICTIONARY:
			var p_data: PlayerData = _player_from_dict(player_dict)
			if p_data.is_captain:
				has_captain = true
			squad.append(p_data)

	if not has_captain and squad.size() > 1:
		# Designate default captain (first outfield centre-back/midfielder or slot 2)
		var captain_idx: int = 2 if squad.size() > 2 else 1
		squad[captain_idx].is_captain = true

	team.squad = squad

	var staff_list: Array[StaffData] = []
	for staff_dict: Variant in team_dict.get("staff", []):
		if typeof(staff_dict) == TYPE_DICTIONARY:
			staff_list.append(StaffLoader._staff_from_dict(staff_dict as Dictionary))
	team.staff = staff_list

	var lineup: Array[int] = []
	if team_dict.has("lineup_indices"):
		var raw_lineup: Variant = team_dict["lineup_indices"]
		if typeof(raw_lineup) == TYPE_ARRAY:
			for idx: Variant in raw_lineup:
				lineup.append(int(idx))

	if lineup.size() == 11:
		team.lineup_indices = lineup
	else:
		var default_indices: Array[int] = []
		for i in range(mini(11, squad.size())):
			default_indices.append(i)
		team.lineup_indices = default_indices

	return team


func _generate_contrasting_gk_color(team_col: Color) -> Color:
	# If team color is greenish (hue between 0.20 and 0.45)
	if team_col.h >= 0.20 and team_col.h <= 0.45 and team_col.s > 0.25:
		return Color(1.0, 0.65, 0.10, 1.0)
	# If team color is reddish/warm (hue < 0.15 or hue > 0.85)
	if (team_col.h < 0.15 or team_col.h > 0.85) and team_col.s > 0.25:
		return Color(0.10, 0.85, 0.90, 1.0)
	# Default high-vis neon emerald green for blues, darks, and neutrals
	return Color(0.15, 0.88, 0.45, 1.0)


func _player_from_dict(player_dict: Dictionary) -> PlayerData:
	var name_str: String = player_dict.get("player_name", "")
	if name_str == "" and player_dict.has("first_name"):
		name_str = "%s %s" % [player_dict.get("first_name", ""), player_dict.get("last_name", "")]

	var role_str: String = player_dict.get("position_role", player_dict.get("role", "CM"))
	var shirt_num: int = int(player_dict.get("shirt_number", 0))

	var data := PlayerData.make_default(name_str, shirt_num, role_str)

	data.is_captain = bool(player_dict.get("is_captain", false))
	data.mass = float(player_dict.get("mass", player_dict.get("weight_kg", data.mass)))
	data.top_speed = float(player_dict.get("top_speed", data.top_speed))
	data.acceleration_time = float(player_dict.get("acceleration_time", data.acceleration_time))
	data.friction_time = float(player_dict.get("friction_time", data.friction_time))
	data.turning_penalty = float(player_dict.get("turning_penalty", data.turning_penalty))
	data.sprint_multiplier = float(player_dict.get("sprint_multiplier", data.sprint_multiplier))

	var raw_stamina: float = float(player_dict.get("stamina_max", player_dict.get("max_stamina", data.stamina_max)))
	data.stamina_max = raw_stamina * 100.0 if raw_stamina <= 1.0 and raw_stamina > 0.0 else raw_stamina
	data.stamina_drain = float(player_dict.get("stamina_drain", data.stamina_drain))
	data.stamina_recover = float(player_dict.get("stamina_recover", data.stamina_recover))

	data.vision = float(player_dict.get("vision", player_dict.get("positioning_iq", data.vision)))
	data.composure = float(player_dict.get("composure", player_dict.get("decision_speed", data.composure)))
	data.aggression = float(player_dict.get("aggression", data.aggression))
	data.formation_ball_weight = float(player_dict.get("formation_ball_weight", data.formation_ball_weight))

	data.close_control = float(player_dict.get("close_control", player_dict.get("pass_accuracy", data.close_control)))
	data.reflexes = float(player_dict.get("reflexes", data.reflexes))

	# Football Manager mental attributes & personality
	data.determination = float(player_dict.get("determination", data.determination))
	data.work_rate = float(player_dict.get("work_rate", data.work_rate))
	data.leadership = float(player_dict.get("leadership", data.leadership))
	data.temperament = float(player_dict.get("temperament", data.temperament))
	data.professionalism = float(player_dict.get("professionalism", data.professionalism))
	data.ambition = float(player_dict.get("ambition", data.ambition))
	data.loyalty = float(player_dict.get("loyalty", data.loyalty))
	data.adaptability = float(player_dict.get("adaptability", data.adaptability))
	data.traits = int(player_dict.get("traits", data.traits))
	data.player_reputation = float(player_dict.get("player_reputation", player_dict.get("reputation", data.player_reputation)))

	# Contracts & economics
	data.wage_weekly = int(player_dict.get("wage_weekly", data.wage_weekly))
	data.contract_years = int(player_dict.get("contract_years", data.contract_years))
	data.release_clause = int(player_dict.get("release_clause", data.release_clause))
	data.squad_status = str(player_dict.get("squad_status", data.squad_status))
	data.morale = float(player_dict.get("morale", data.morale))
	data.market_value = int(player_dict.get("market_value", data.calculate_market_value()))

	data.form = float(player_dict.get("form", data.form))
	data.career_goals = int(player_dict.get("career_goals", data.career_goals))
	data.career_assists = int(player_dict.get("career_assists", data.career_assists))
	data.last_match_rating = float(player_dict.get("last_match_rating", data.last_match_rating))
	data.is_unavailable = bool(player_dict.get("is_unavailable", data.is_unavailable))

	data.nationality = str(player_dict.get("nationality", data.nationality))
	data.secondary_nationality = str(player_dict.get("secondary_nationality", data.secondary_nationality))
	data.date_of_birth = str(player_dict.get("date_of_birth", data.date_of_birth))

	var raw_langs: Variant = player_dict.get("spoken_languages", [])
	var parsed_langs: Array[Dictionary] = []
	if typeof(raw_langs) == TYPE_ARRAY:
		for l_item: Variant in (raw_langs as Array):
			if typeof(l_item) == TYPE_DICTIONARY:
				parsed_langs.append(l_item as Dictionary)
	if parsed_langs.is_empty():
		var prim_lang: String = NationDatabase.get_primary_language_for_nation(data.nationality)
		parsed_langs.append({"language": prim_lang, "proficiency": 1.0, "level": "Native"})
		if prim_lang != "English":
			parsed_langs.append({"language": "English", "proficiency": 0.75, "level": "Fluent"})
	data.spoken_languages = parsed_langs

	return data


## Converts a PlayerData instance to a JSON-serializable Dictionary.
func _player_to_dict(p: PlayerData) -> Dictionary:
	return {
		"player_name": p.player_name,
		"shirt_number": p.shirt_number,
		"position_role": p.position_role,
		"is_captain": p.is_captain,
		"mass": p.mass,
		"top_speed": p.top_speed,
		"acceleration_time": p.acceleration_time,
		"friction_time": p.friction_time,
		"turning_penalty": p.turning_penalty,
		"sprint_multiplier": p.sprint_multiplier,
		"stamina_max": p.stamina_max,
		"stamina_drain": p.stamina_drain,
		"stamina_recover": p.stamina_recover,
		"vision": p.vision,
		"composure": p.composure,
		"aggression": p.aggression,
		"formation_ball_weight": p.formation_ball_weight,
		"close_control": p.close_control,
		"reflexes": p.reflexes,
		"determination": p.determination,
		"work_rate": p.work_rate,
		"leadership": p.leadership,
		"temperament": p.temperament,
		"professionalism": p.professionalism,
		"ambition": p.ambition,
		"loyalty": p.loyalty,
		"adaptability": p.adaptability,
		"traits": p.traits,
		"player_reputation": p.player_reputation,
		"wage_weekly": p.wage_weekly,
		"contract_years": p.contract_years,
		"release_clause": p.release_clause,
		"squad_status": p.squad_status,
		"morale": p.morale,
		"market_value": p.market_value,
		"form": p.form,
		"career_goals": p.career_goals,
		"career_assists": p.career_assists,
		"last_match_rating": p.last_match_rating,
		"is_unavailable": p.is_unavailable,
		"nationality": p.nationality,
		"secondary_nationality": p.secondary_nationality,
		"date_of_birth": p.date_of_birth,
		"spoken_languages": p.spoken_languages
	}


## Converts a TeamData instance to a JSON-serializable Dictionary.
func _team_to_dict(t: TeamData) -> Dictionary:
	var squad_list: Array = []
	for p: PlayerData in t.squad:
		squad_list.append(_player_to_dict(p))

	var staff_list: Array = []
	for s: StaffData in t.staff:
		staff_list.append(StaffLoader._staff_to_dict(s))

	return {
		"team_name": t.team_name,
		"team_color": [t.team_color.r, t.team_color.g, t.team_color.b],
		"secondary_color": [t.secondary_color.r, t.secondary_color.g, t.secondary_color.b],
		"gk_color": [t.gk_color.r, t.gk_color.g, t.gk_color.b],
		"formation_override": t.formation_override,
		"substitutions_made": t.substitutions_made,
		"lineup_indices": t.lineup_indices,
		"reputation": t.reputation,
		"stature": t.stature,
		"transfer_budget": t.transfer_budget,
		"wage_budget_weekly": t.wage_budget_weekly,
		"squad": squad_list,
		"staff": staff_list
	}


## Persists the live league data to JSON.
func save_league(path: String = CUSTOM_LEAGUE_PATH) -> bool:
	if league == null:
		return false
	var team_list: Array = []
	for t: TeamData in league.teams:
		team_list.append(_team_to_dict(t))

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DataLoader: could not open %s for writing (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false

	var payload := {
		"league_name": league.league_name,
		"teams": team_list
	}
	file.store_string(JSON.stringify(payload, "\t"))
	return true


func _build_default_league() -> void:
	var default_league := LeagueData.new()
	default_league.league_name = "Continental Championship"
	default_league.teams = [_build_nordvik(), _build_solano()]
	league = default_league


## --- Built-in fallback squads (18 players each) --------------------------------

func _build_nordvik() -> TeamData:
	var team := TeamData.new()
	team.team_name = "FC Nordvik"
	team.team_color = Color(0.05, 0.13, 0.25)
	team.secondary_color = Color(0.29, 0.56, 0.89)
	team.gk_color = Color(0.12, 0.78, 0.42)
	team.formation_override = "4-4-2"
	team.squad = [
		_player(1, "Mads Dahl", "GK", 82.0, 180.0, 0.32, 0.12, 0.50, 1.30, 95.0, 0.80, 0.85, 0.30, 0.50, 0.88),
		_player(3, "Erik Lund", "LB", 76.0, 215.0, 0.22, 0.12, 0.35, 1.44, 105.0, 0.70, 0.62, 0.58, 0.65, 0.40),
		_player(5, "Halvard Brann", "CB", 90.0, 188.0, 0.32, 0.12, 0.50, 1.28, 98.0, 0.62, 0.76, 0.82, 0.52, 0.35, true),
		_player(4, "Sigurd Voss", "CB", 88.0, 192.0, 0.32, 0.12, 0.50, 1.30, 96.0, 0.65, 0.72, 0.75, 0.55, 0.35),
		_player(2, "Torben Hauge", "RB", 75.0, 214.0, 0.22, 0.12, 0.35, 1.45, 102.0, 0.72, 0.64, 0.60, 0.66, 0.40),
		_player(11, "Jonas Elv", "LM", 69.0, 230.0, 0.15, 0.12, 0.25, 1.52, 100.0, 0.75, 0.58, 0.62, 0.80, 0.45),
		_player(8, "Olav Strand", "CM", 74.0, 210.0, 0.22, 0.12, 0.35, 1.40, 112.0, 0.85, 0.74, 0.62, 0.75, 0.45),
		_player(6, "Niklas Borg", "DM", 80.0, 202.0, 0.30, 0.12, 0.48, 1.36, 108.0, 0.80, 0.80, 0.78, 0.68, 0.40),
		_player(7, "Rune Kval", "RM", 70.0, 226.0, 0.15, 0.12, 0.25, 1.50, 98.0, 0.74, 0.60, 0.65, 0.78, 0.45),
		_player(9, "Henrik Ask", "ST", 83.0, 222.0, 0.22, 0.12, 0.35, 1.50, 100.0, 0.70, 0.68, 0.85, 0.72, 0.45),
		_player(10, "Petter Naess", "ST", 72.0, 218.0, 0.16, 0.12, 0.26, 1.48, 96.0, 0.88, 0.82, 0.58, 0.84, 0.45),
		_player(12, "Emil Lind", "GK", 84.0, 178.0, 0.33, 0.12, 0.50, 1.28, 90.0, 0.65, 0.70, 0.40, 0.48, 0.75),
		_player(14, "Rasmus Holst", "CB", 87.0, 190.0, 0.32, 0.12, 0.50, 1.28, 92.0, 0.58, 0.65, 0.72, 0.50, 0.35),
		_player(15, "Joakim Berg", "RB", 74.0, 212.0, 0.22, 0.12, 0.35, 1.42, 95.0, 0.64, 0.60, 0.55, 0.62, 0.40),
		_player(16, "Stian Mork", "CM", 75.0, 206.0, 0.22, 0.12, 0.35, 1.38, 102.0, 0.72, 0.68, 0.60, 0.70, 0.45),
		_player(17, "Magnus Rygg", "AM", 70.0, 216.0, 0.16, 0.12, 0.26, 1.46, 92.0, 0.80, 0.70, 0.52, 0.76, 0.45),
		_player(18, "Vidar Krog", "ST", 85.0, 212.0, 0.24, 0.12, 0.38, 1.44, 94.0, 0.62, 0.62, 0.80, 0.65, 0.40),
		_player(19, "Andreas Solberg", "CB", 86.0, 186.0, 0.32, 0.12, 0.50, 1.26, 90.0, 0.55, 0.60, 0.70, 0.48, 0.35)
	]
	var lineup: Array[int] = []
	for i in range(11):
		lineup.append(i)
	team.lineup_indices = lineup
	return team


func _build_solano() -> TeamData:
	var team := TeamData.new()
	team.team_name = "CD Solano"
	team.team_color = Color(0.64, 0.11, 0.11)
	team.secondary_color = Color(0.95, 0.82, 0.22)
	team.gk_color = Color(0.10, 0.82, 0.88)
	team.formation_override = "4-3-3"
	team.squad = [
		_player(1, "Carlos Vega", "GK", 80.0, 180.0, 0.32, 0.12, 0.50, 1.28, 92.0, 0.78, 0.88, 0.25, 0.55, 0.90),
		_player(3, "Luis Ferrer", "LB", 73.0, 222.0, 0.20, 0.12, 0.32, 1.48, 106.0, 0.76, 0.66, 0.54, 0.72, 0.45),
		_player(5, "Mateo Ruiz", "CB", 86.0, 192.0, 0.30, 0.12, 0.48, 1.30, 96.0, 0.68, 0.74, 0.70, 0.60, 0.35, true),
		_player(4, "Diego Pons", "CB", 88.0, 188.0, 0.32, 0.12, 0.50, 1.28, 95.0, 0.62, 0.70, 0.74, 0.56, 0.35),
		_player(2, "Andres Mora", "RB", 74.0, 220.0, 0.20, 0.12, 0.32, 1.47, 104.0, 0.74, 0.65, 0.55, 0.70, 0.45),
		_player(6, "Pablo Cano", "DM", 78.0, 204.0, 0.28, 0.12, 0.45, 1.38, 110.0, 0.82, 0.78, 0.74, 0.72, 0.40),
		_player(8, "Rafael Soto", "CM", 72.0, 214.0, 0.20, 0.12, 0.32, 1.44, 114.0, 0.86, 0.78, 0.58, 0.82, 0.45),
		_player(10, "Marco Reyes", "AM", 69.0, 220.0, 0.15, 0.12, 0.24, 1.50, 102.0, 0.94, 0.84, 0.52, 0.90, 0.45),
		_player(11, "Javier Tur", "LW", 67.0, 240.0, 0.15, 0.12, 0.24, 1.56, 100.0, 0.72, 0.55, 0.68, 0.86, 0.45),
		_player(9, "Bruno Tena", "ST", 81.0, 224.0, 0.20, 0.12, 0.34, 1.52, 102.0, 0.74, 0.72, 0.84, 0.78, 0.45),
		_player(7, "Ivan Blasco", "RW", 68.0, 238.0, 0.15, 0.12, 0.24, 1.54, 98.0, 0.75, 0.58, 0.65, 0.84, 0.45),
		_player(13, "Joaquin Giner", "GK", 81.0, 176.0, 0.33, 0.12, 0.50, 1.25, 90.0, 0.68, 0.72, 0.30, 0.50, 0.78),
		_player(14, "Felix Navarro", "CB", 85.0, 190.0, 0.32, 0.12, 0.50, 1.27, 92.0, 0.60, 0.66, 0.68, 0.54, 0.35),
		_player(15, "Santi Cordero", "LB", 72.0, 216.0, 0.21, 0.12, 0.34, 1.44, 98.0, 0.68, 0.62, 0.50, 0.68, 0.40),
		_player(16, "Alejandro Blesa", "CM", 71.0, 208.0, 0.21, 0.12, 0.34, 1.40, 104.0, 0.78, 0.70, 0.55, 0.76, 0.45),
		_player(17, "Dani Osorio", "RW", 66.0, 232.0, 0.15, 0.12, 0.25, 1.50, 94.0, 0.68, 0.52, 0.60, 0.78, 0.45),
		_player(18, "Alvaro Ribera", "ST", 82.0, 218.0, 0.22, 0.12, 0.35, 1.48, 96.0, 0.65, 0.64, 0.76, 0.70, 0.40),
		_player(19, "Mario Gil", "AM", 68.0, 214.0, 0.16, 0.12, 0.26, 1.45, 92.0, 0.82, 0.72, 0.48, 0.80, 0.45)
	]
	var lineup: Array[int] = []
	for i in range(11):
		lineup.append(i)
	team.lineup_indices = lineup
	return team


## Shared constructor for player builder.
func _player(
	shirt_number: int, player_name: String, position_role: String,
	mass: float, top_speed: float, acceleration_time: float, friction_time: float,
	turning_penalty: float, sprint_multiplier: float, stamina_max: float,
	vision: float, composure: float, aggression: float,
	close_control: float, reflexes: float, is_captain: bool = false
) -> PlayerData:
	var data := PlayerData.make_default(player_name, shirt_number, position_role)
	data.is_captain = is_captain
	data.mass = mass
	data.top_speed = top_speed
	data.acceleration_time = acceleration_time
	data.friction_time = friction_time
	data.turning_penalty = turning_penalty
	data.sprint_multiplier = sprint_multiplier
	data.stamina_max = stamina_max
	data.stamina_drain = 18.0
	data.stamina_recover = 9.0
	data.vision = vision
	data.composure = composure
	data.aggression = aggression
	data.formation_ball_weight = 0.35
	data.close_control = close_control
	data.reflexes = reflexes
	data.form = 6.5
	return data
