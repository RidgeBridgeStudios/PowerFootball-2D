##
## DatabaseManager
##
## Autoload singleton managing SQLite database access via godot-sqlite GDExtension.
## Encapsulates storage lifecycle (res:// template to user:// copy), strict game
## mode separation ('men' vs 'women'), competition routing (domestic leagues vs
## tournament_participants cups), and typed Resource instantiation (PlayerData, TeamData).
##
## Depends on: PlayerData, TeamData.
## Exposes: global DatabaseManager singleton queries and lifecycle methods.
##

extends Node

signal game_mode_changed(new_mode: String)
signal database_opened(db_path: String)
signal database_closed()

const DB_FILENAME: String = "powerfootball_master.db"
const TEMPLATE_DB_PATH: String = "res://data/" + DB_FILENAME
const USER_DB_PATH: String = "user://" + DB_FILENAME

const MODE_MEN: String = "men"
const MODE_WOMEN: String = "women"

var current_game_mode: String = MODE_MEN
var is_connected_to_db: bool = false
var _db: Object = null


func _ready() -> void:
	initialize_database()


func get_database_path() -> String:
	return USER_DB_PATH


## Initializes database by ensuring writable user:// copy and connecting via godot-sqlite.
func initialize_database(force_copy: bool = false) -> bool:
	if not DirAccess.dir_exists_absolute("user://"):
		DirAccess.make_dir_recursive_absolute("user://")

	var user_file_exists: bool = FileAccess.file_exists(USER_DB_PATH)

	# Smart cache synchronization in debug/editor builds
	if not force_copy and user_file_exists and OS.is_debug_build():
		if FileAccess.file_exists(TEMPLATE_DB_PATH):
			var template_time: int = FileAccess.get_modified_time(TEMPLATE_DB_PATH)
			var user_time: int = FileAccess.get_modified_time(USER_DB_PATH)
			var t_file: FileAccess = FileAccess.open(TEMPLATE_DB_PATH, FileAccess.READ)
			var u_file: FileAccess = FileAccess.open(USER_DB_PATH, FileAccess.READ)
			var t_size: int = t_file.get_length() if t_file != null else 0
			var u_size: int = u_file.get_length() if u_file != null else 0
			if t_file != null:
				t_file.close()
			if u_file != null:
				u_file.close()

			if t_size != u_size or template_time > user_time:
				print("DatabaseManager: Stale user:// database detected in debug build (%d bytes vs %d bytes). Re-syncing database..." % [u_size, t_size])
				force_copy = true

	if force_copy and is_connected_to_db:
		close_database()

	if force_copy or not user_file_exists:
		if FileAccess.file_exists(TEMPLATE_DB_PATH):
			if FileAccess.file_exists(USER_DB_PATH + "-wal"):
				DirAccess.remove_absolute(USER_DB_PATH + "-wal")
			if FileAccess.file_exists(USER_DB_PATH + "-shm"):
				DirAccess.remove_absolute(USER_DB_PATH + "-shm")
			var err: int = DirAccess.copy_absolute(TEMPLATE_DB_PATH, USER_DB_PATH)
			if err != OK:
				push_error("DatabaseManager: Failed to copy %s to %s: %s" % [TEMPLATE_DB_PATH, USER_DB_PATH, error_string(err)])
				return false
			print("DatabaseManager: Synchronized master database to %s" % USER_DB_PATH)
		else:
			if not user_file_exists:
				push_warning("DatabaseManager: Template database not found at %s. Empty database will be initialized at %s" % [TEMPLATE_DB_PATH, USER_DB_PATH])

	if ClassDB.can_instantiate(&"SQLite"):
		_db = ClassDB.instantiate(&"SQLite")
	elif ClassDB.class_exists(&"SQLite"):
		_db = ClassDB.instantiate(&"SQLite")

	if _db == null:
		push_warning("DatabaseManager: GDExtension 'SQLite' class is not loaded or available in ClassDB.")
		return false

	_db.set(&"path", USER_DB_PATH)
	var success: bool = bool(_db.call(&"open_db"))
	if not success:
		var err_msg: String = str(_db.get(&"error_message"))
		push_error("DatabaseManager: Failed to open SQLite database at %s: %s" % [USER_DB_PATH, err_msg])
		return false

	is_connected_to_db = true
	_db.call(&"query", "PRAGMA foreign_keys = ON;")
	_db.call(&"query", "PRAGMA journal_mode = WAL;")
	_db.call(&"query", "PRAGMA synchronous = NORMAL;")
	database_opened.emit(USER_DB_PATH)
	return true


## Closes active SQLite connection.
func close_database() -> void:
	if _db != null and is_connected_to_db:
		_db.call(&"close_db")
		is_connected_to_db = false
		database_closed.emit()


## Sets active game mode ('men' or 'women') enforcing game mode query isolation.
func set_game_mode(mode: String) -> void:
	var clean_mode: String = mode.to_lower().strip_edges()
	if clean_mode != MODE_MEN and clean_mode != MODE_WOMEN:
		push_error("DatabaseManager: Invalid game mode '%s'. Must be 'men' or 'women'." % mode)
		return
	if current_game_mode != clean_mode:
		current_game_mode = clean_mode
		game_mode_changed.emit(current_game_mode)


func get_game_mode() -> String:
	return current_game_mode


func _resolve_gender(gender_override: String) -> String:
	if gender_override != "":
		return gender_override.to_lower().strip_edges()
	return current_game_mode


## Executes raw SQL query with optional bindings and returns typed rows.
func query(sql: String, params: Array = []) -> Array[Dictionary]:
	if not is_connected_to_db or _db == null:
		push_warning("DatabaseManager: Cannot execute query; database not open.")
		return []

	var ok: bool = false
	if params.is_empty():
		ok = bool(_db.call(&"query", sql))
	else:
		ok = bool(_db.call(&"query_with_bindings", sql, params))

	if not ok:
		var err_msg: String = str(_db.get(&"error_message"))
		push_error("DatabaseManager: Query failed: %s | Error: %s" % [sql, err_msg])
		return []

	var raw: Variant = _db.get(&"query_result")
	var rows: Array[Dictionary] = []
	if raw is Array:
		for row: Variant in raw:
			if row is Dictionary:
				rows.append(row)
	return rows


## Executes DDL/DML statement (INSERT, UPDATE, DELETE, PRAGMA).
func execute(sql: String, params: Array = []) -> bool:
	if not is_connected_to_db or _db == null:
		push_warning("DatabaseManager: Cannot execute statement; database not open.")
		return false

	var ok: bool = false
	if params.is_empty():
		ok = bool(_db.call(&"query", sql))
	else:
		ok = bool(_db.call(&"query_with_bindings", sql, params))

	if not ok:
		var err_msg: String = str(_db.get(&"error_message"))
		push_error("DatabaseManager: Statement execution failed: %s | Error: %s" % [sql, err_msg])
		return false
	return true


## Recipe 1: Fetches squad roster and instantiates typed PlayerData Resource objects.
func fetch_squad_roster(team_id: int, gender_override: String = "") -> Array[PlayerData]:
	var gender: String = _resolve_gender(gender_override)
	var sql: String = (
		"SELECT p.player_id, p.player_name, p.first_name, p.last_name, "
		+ "p.position_role, p.nationality, p.date_of_birth, p.height_cm, p.weight_kg, "
		+ "p.image_url, p.gender, "
		+ "p.mass, p.top_speed, p.stamina_max, p.vision, p.composure, "
		+ "p.aggression, p.close_control, p.reflexes, p.determination, p.work_rate, "
		+ "MAX(c.jersey_number) AS jersey_number, COALESCE(c.position_name, p.position_role) AS position_name "
		+ "FROM players p "
		+ "JOIN contracts c ON p.player_id = c.player_id "
		+ "LEFT JOIN seasons s ON c.season_id = s.season_id "
		+ "WHERE c.team_id = ? AND p.gender = ? "
		+ "AND (s.is_current = 1 OR s.is_current IS NULL) "
		+ "GROUP BY p.player_id "
		+ "ORDER BY (CASE WHEN p.position_role = 'GK' THEN 0 ELSE 1 END), p.player_name ASC;"
	)
	var rows: Array[Dictionary] = query(sql, [team_id, gender])
	if rows.is_empty():
		var fallback_sql: String = (
			"SELECT p.player_id, p.player_name, p.first_name, p.last_name, "
			+ "p.position_role, p.nationality, p.date_of_birth, p.height_cm, p.weight_kg, "
			+ "p.image_url, p.gender, "
			+ "p.mass, p.top_speed, p.stamina_max, p.vision, p.composure, "
			+ "p.aggression, p.close_control, p.reflexes, p.determination, p.work_rate, "
			+ "MAX(c.jersey_number) AS jersey_number, COALESCE(c.position_name, p.position_role) AS position_name "
			+ "FROM players p "
			+ "JOIN contracts c ON p.player_id = c.player_id "
			+ "WHERE c.team_id = ? AND p.gender = ? "
			+ "GROUP BY p.player_id "
			+ "ORDER BY (CASE WHEN p.position_role = 'GK' THEN 0 ELSE 1 END), p.player_name ASC;"
		)
		rows = query(fallback_sql, [team_id, gender])

	var squad: Array[PlayerData] = []
	squad.resize(rows.size())
	for i: int in range(rows.size()):
		squad[i] = PlayerData.from_db_row(rows[i])
	return squad


## Recipe 2: Fetches tournament participants for cup / Champions League competitions.
func fetch_tournament_participants(competition_id: int, season_id: int) -> Array[Dictionary]:
	var sql: String = (
		"SELECT t.team_id, t.name, tp.seed_status, tp.stage_reached "
		+ "FROM tournament_participants tp "
		+ "JOIN teams t ON tp.team_id = t.team_id "
		+ "WHERE tp.season_id = ? AND tp.competition_id = ?;"
	)
	return query(sql, [season_id, competition_id])


## Fetches tournament participating teams as typed TeamData Resource objects.
func fetch_tournament_teams(competition_id: int, season_id: int) -> Array[TeamData]:
	var sql: String = (
		"SELECT t.* "
		+ "FROM tournament_participants tp "
		+ "JOIN teams t ON tp.team_id = t.team_id "
		+ "WHERE tp.season_id = ? AND tp.competition_id = ?;"
	)
	var rows: Array[Dictionary] = query(sql, [season_id, competition_id])
	var teams: Array[TeamData] = []
	teams.resize(rows.size())
	for i: int in range(rows.size()):
		teams[i] = TeamData.from_db_row(rows[i])
	return teams


## Fetches single team by team_id as typed TeamData.
func fetch_team(team_id: int) -> TeamData:
	var sql: String = "SELECT * FROM teams WHERE team_id = ? LIMIT 1;"
	var rows: Array[Dictionary] = query(sql, [team_id])
	if rows.is_empty():
		return null
	return TeamData.from_db_row(rows[0])


## Fetches all teams in a domestic league filtered by gender mode.
func fetch_teams_in_league(league_id: int, gender_override: String = "") -> Array[TeamData]:
	var gender: String = _resolve_gender(gender_override)
	var sql: String = "SELECT * FROM teams WHERE league_id = ? AND gender = ? ORDER BY name ASC;"
	var rows: Array[Dictionary] = query(sql, [league_id, gender])
	var teams: Array[TeamData] = []
	teams.resize(rows.size())
	for i: int in range(rows.size()):
		teams[i] = TeamData.from_db_row(rows[i])
	return teams


## Alias for fetch_teams_in_league for standard API compatibility.
func get_teams_in_league(league_id: int, gender_override: String = "") -> Array[TeamData]:
	return fetch_teams_in_league(league_id, gender_override)


## Fetches all teams for the active gender mode.
func fetch_all_teams(gender_override: String = "") -> Array[TeamData]:
	var gender: String = _resolve_gender(gender_override)
	var sql: String = "SELECT * FROM teams WHERE gender = ? ORDER BY name ASC;"
	var rows: Array[Dictionary] = query(sql, [gender])
	var teams: Array[TeamData] = []
	teams.resize(rows.size())
	for i: int in range(rows.size()):
		teams[i] = TeamData.from_db_row(rows[i])
	return teams


## Fetches leagues filtered by gender and optional competition_type ('DOMESTIC_LEAGUE', 'CONTINENTAL_CUP', 'DOMESTIC_CUP').
func fetch_leagues(competition_type: String = "", gender_override: String = "") -> Array[Dictionary]:
	var gender: String = _resolve_gender(gender_override)
	var sql: String = "SELECT * FROM leagues WHERE gender = ? ORDER BY name ASC;"
	var params: Array = [gender]
	if competition_type != "":
		sql = "SELECT * FROM leagues WHERE competition_type = ? AND gender = ? ORDER BY name ASC;"
		params = [competition_type, gender]
	return query(sql, params)


## Fetches league record by league_id.
func fetch_league_by_id(league_id: int) -> Dictionary:
	var sql: String = "SELECT * FROM leagues WHERE league_id = ? LIMIT 1;"
	var rows: Array[Dictionary] = query(sql, [league_id])
	return rows[0] if not rows.is_empty() else {}


## Fetches active season record for a league.
func fetch_current_season(league_id: int) -> Dictionary:
	var sql: String = "SELECT * FROM seasons WHERE league_id = ? AND is_current = 1 LIMIT 1;"
	var rows: Array[Dictionary] = query(sql, [league_id])
	return rows[0] if not rows.is_empty() else {}


## Fetches venue metadata by venue_id.
func fetch_venue(venue_id: int) -> Dictionary:
	var sql: String = "SELECT * FROM venues WHERE venue_id = ? LIMIT 1;"
	var rows: Array[Dictionary] = query(sql, [venue_id])
	return rows[0] if not rows.is_empty() else {}


## Fetches head coach by team_id.
func fetch_coach(team_id: int) -> Dictionary:
	var sql: String = "SELECT * FROM coaches WHERE team_id = ? LIMIT 1;"
	var rows: Array[Dictionary] = query(sql, [team_id])
	return rows[0] if not rows.is_empty() else {}


## Fetches rival team IDs for a team.
func fetch_team_rivals(team_id: int) -> Array[int]:
	var sql: String = "SELECT rival_team_id FROM team_rivals WHERE team_id = ?;"
	var rows: Array[Dictionary] = query(sql, [team_id])
	var rivals: Array[int] = []
	for row: Dictionary in rows:
		rivals.append(int(row.get("rival_team_id", 0)))
	return rivals


## Fetches player by player_id as typed PlayerData Resource.
func fetch_player(player_id: int) -> PlayerData:
	var sql: String = "SELECT * FROM players WHERE player_id = ? LIMIT 1;"
	var rows: Array[Dictionary] = query(sql, [player_id])
	if rows.is_empty():
		return null
	return PlayerData.from_db_row(rows[0])


## Searches players by name and optional position filter, isolated by gender mode.
func search_players(query_name: String, position_filter: String = "", gender_override: String = "", limit: int = 50) -> Array[PlayerData]:
	var gender: String = _resolve_gender(gender_override)
	var sql: String = "SELECT * FROM players WHERE gender = ? AND player_name LIKE ?"
	var params: Array = [gender, "%" + query_name + "%"]
	if position_filter != "":
		sql += " AND position_role = ?"
		params.append(position_filter)
	sql += " ORDER BY player_name ASC LIMIT ?;"
	params.append(limit)

	var rows: Array[Dictionary] = query(sql, params)
	var players: Array[PlayerData] = []
	players.resize(rows.size())
	for i: int in range(rows.size()):
		players[i] = PlayerData.from_db_row(rows[i])
	return players


## Searches teams by name or short code with optional league and gender filter.
func search_teams(query_text: String, league_id: int = -1, gender_override: String = "", limit: int = 60) -> Array[TeamData]:
	var gender: String = _resolve_gender(gender_override)
	var sql: String = "SELECT * FROM teams WHERE gender = ?"
	var params: Array = [gender]
	var trimmed: String = query_text.strip_edges()
	if not trimmed.is_empty():
		sql += " AND (name LIKE ? OR short_code LIKE ?)"
		var term: String = "%" + trimmed + "%"
		params.append(term)
		params.append(term)
	if league_id > 0:
		sql += " AND league_id = ?"
		params.append(league_id)
	sql += " ORDER BY name ASC LIMIT ?;"
	params.append(limit)

	var rows: Array[Dictionary] = query(sql, params)
	var teams: Array[TeamData] = []
	teams.resize(rows.size())
	for i: int in range(rows.size()):
		teams[i] = TeamData.from_db_row(rows[i])
	return teams


## Fetches teams in a competition (domestic league or tournament cup).
func fetch_teams_in_competition(competition_id: int, competition_type: String = "", gender_override: String = "") -> Array[TeamData]:
	var gender: String = _resolve_gender(gender_override)
	var teams: Array[TeamData] = []

	# Check domestic league first
	if competition_type == "DOMESTIC_LEAGUE" or competition_type.is_empty():
		teams = fetch_teams_in_league(competition_id, gender)
		if not teams.is_empty():
			return teams

	# Check tournament_participants for cup competitions
	var sql: String = (
		"SELECT t.* FROM teams t "
		+ "JOIN tournament_participants tp ON t.team_id = tp.team_id "
		+ "WHERE tp.competition_id = ? "
		+ "GROUP BY t.team_id ORDER BY t.name ASC;"
	)
	var rows: Array[Dictionary] = query(sql, [competition_id])
	teams.resize(rows.size())
	for i: int in range(rows.size()):
		teams[i] = TeamData.from_db_row(rows[i])

	if teams.is_empty() and competition_type != "DOMESTIC_LEAGUE":
		# Fallback check league_id in case it was tagged as cup in leagues table
		teams = fetch_teams_in_league(competition_id, gender)

	return teams


## Fetches all backroom staff assigned to a team from the staff table.
func fetch_staff_for_team(team_id: int) -> Array[Dictionary]:
	var sql: String = "SELECT * FROM staff WHERE team_id = ? ORDER BY staff_name ASC;"
	return query(sql, [team_id])


## Fetches referees from the database with optional search filtering by name or nationality.
func fetch_referees(search_text: String = "", limit: int = 150) -> Array[Dictionary]:
	var sql: String = "SELECT * FROM referees"
	var params: Array = []
	var trimmed: String = search_text.strip_edges()
	if not trimmed.is_empty():
		sql += " WHERE name LIKE ? OR nationality LIKE ?"
		var term: String = "%" + trimmed + "%"
		params.append(term)
		params.append(term)
	sql += " ORDER BY reputation DESC, experience DESC LIMIT ?;"
	params.append(limit)
	return query(sql, params)


## Fetches rival team information (team_id, name, short_code) for a club.
func fetch_team_rivals_info(team_id: int) -> Array[Dictionary]:
	var sql: String = (
		"SELECT t.team_id, t.name, t.short_code, t.stature, t.reputation "
		+ "FROM team_rivals tr "
		+ "JOIN teams t ON tr.rival_team_id = t.team_id "
		+ "WHERE tr.team_id = ? ORDER BY t.name ASC;"
	)
	return query(sql, [team_id])

