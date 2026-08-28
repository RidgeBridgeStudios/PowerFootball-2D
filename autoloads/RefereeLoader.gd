##
## RefereeLoader (Autoload singleton)
##
## Owns the live referee pool. Loads custom referees from
## user://custom_referees.json if the file exists, otherwise builds the six
## built-in referees. PitchScene draws a referee from here at match start
## rather than constructing a RefereeData itself, so a future referee editor
## only has to change what is written to user://custom_referees.json.
##
## Depends on: RefereeData.
## Exposes: referee_pool, get_referee(index), get_random_referee(), save_referees()
##

extends Node

const CUSTOM_REFEREES_PATH: String = "user://custom_referees.json"

var referee_pool: Array[RefereeData] = []


func _ready() -> void:
	_load_referees()


func get_referee(index: int) -> RefereeData:
	if index < 0 or index >= referee_pool.size():
		push_warning("RefereeLoader.get_referee: index %d out of bounds." % index)
		return null
	return referee_pool[index]


## Weighted random pick: referees with higher experience officiate more
## matches, so they are proportionally more likely to be assigned.
func get_random_referee() -> RefereeData:
	if referee_pool.is_empty():
		return RefereeData.make_default("Unnamed Referee", "Unknown")

	var total_weight: float = 0.0
	for ref: RefereeData in referee_pool:
		total_weight += float(ref.experience)

	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for ref: RefereeData in referee_pool:
		cumulative += float(ref.experience)
		if roll <= cumulative:
			return ref

	return referee_pool[-1]


## Writes the live referee pool (including career stats) to
## user://custom_referees.json so progress survives between sessions.
func save_referees() -> void:
	var referees: Array = []
	for ref: RefereeData in referee_pool:
		referees.append({
			"name": ref.referee_name,
			"nationality": ref.nationality,
			"experience": ref.experience,
			"strictness": ref.strictness,
			"consistency": ref.consistency,
			"composure": ref.composure,
			"unprofessionalism": ref.unprofessionalism,
			"incoherence": ref.incoherence,
			"reputation": ref.reputation,
			"matches_officiated": ref.matches_officiated,
			"fouls_awarded": ref.fouls_awarded,
			"penalties_awarded": ref.penalties_awarded,
			"red_cards_issued": ref.red_cards_issued,
			"matchup_history": ref.matchup_history,
		})

	var file := FileAccess.open(CUSTOM_REFEREES_PATH, FileAccess.WRITE)
	if file == null:
		push_error("RefereeLoader: could not open %s for writing (%s)." % [CUSTOM_REFEREES_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"referees": referees}, "\t"))


func _load_referees() -> void:
	if FileAccess.file_exists(CUSTOM_REFEREES_PATH):
		if _parse_json_referees(CUSTOM_REFEREES_PATH):
			return
	_build_default_referees()


## Parses a JSON referee file into `referee_pool`. Parses into a local var
## first so a malformed file can never leave `referee_pool` half-overwritten.
## Returns false on any error (and pushes an error naming the path) —
## `_load_referees()` falls back to the built-in referee pool when this
## returns false.
func _parse_json_referees(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("RefereeLoader: could not open %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false

	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("referees"):
		push_error("RefereeLoader: %s is missing a \"referees\" key." % path)
		return false

	var pool: Array[RefereeData] = []
	for referee_dict: Variant in parsed["referees"]:
		if typeof(referee_dict) != TYPE_DICTIONARY:
			push_error("RefereeLoader: malformed referee entry in %s." % path)
			return false
		pool.append(_referee_from_dict(referee_dict))

	referee_pool = pool
	return true


func _referee_from_dict(referee_dict: Dictionary) -> RefereeData:
	var data := RefereeData.make_default(
		referee_dict.get("name", ""),
		referee_dict.get("nationality", "")
	)
	data.experience = referee_dict.get("experience", data.experience)
	data.strictness = referee_dict.get("strictness", data.strictness)
	data.consistency = referee_dict.get("consistency", data.consistency)
	data.composure = referee_dict.get("composure", data.composure)
	data.unprofessionalism = referee_dict.get("unprofessionalism", data.unprofessionalism)
	data.incoherence = referee_dict.get("incoherence", data.incoherence)
	data.reputation = referee_dict.get("reputation", data.reputation)
	data.matches_officiated = referee_dict.get("matches_officiated", data.matches_officiated)
	data.fouls_awarded = referee_dict.get("fouls_awarded", data.fouls_awarded)
	data.penalties_awarded = referee_dict.get("penalties_awarded", data.penalties_awarded)
	data.red_cards_issued = referee_dict.get("red_cards_issued", data.red_cards_issued)
	data.matchup_history = referee_dict.get("matchup_history", data.matchup_history)
	return data


## --- Built-in referee pool ------------------------------------------------------

func _build_default_referees() -> void:
	referee_pool = [
		_referee("Domagoj Vrban", "Dalmatian", 34, 0.72, 0.80, 0.85, 0.05, 0.10, 0.88),
		_referee("Kjetil Ørnseth", "Nordlandic", 11, 0.35, 0.40, 0.30, 0.20, 0.70, 0.42),
		_referee("Tomás Errecarte", "Platense", 22, 0.55, 0.65, 0.60, 0.50, 0.30, 0.55),
		_referee("Ingrid Vaarmo", "Nordlandic", 41, 0.90, 0.88, 0.92, 0.02, 0.05, 0.95),
		_referee("Arjun Dharmaraj", "Subcontinental", 18, 0.48, 0.55, 0.70, 0.15, 0.45, 0.60),
		_referee("Petru Bálint", "Carpathian", 9, 0.62, 0.30, 0.45, 0.35, 0.60, 0.38),
	]


## Shared constructor for the six built-in referees.
func _referee(
	referee_name: String, nationality: String, experience: int,
	strictness: float, consistency: float, composure: float,
	unprofessionalism: float, incoherence: float, reputation: float
) -> RefereeData:
	var data := RefereeData.make_default(referee_name, nationality)
	data.experience = experience
	data.strictness = strictness
	data.consistency = consistency
	data.composure = composure
	data.unprofessionalism = unprofessionalism
	data.incoherence = incoherence
	data.reputation = reputation
	return data
