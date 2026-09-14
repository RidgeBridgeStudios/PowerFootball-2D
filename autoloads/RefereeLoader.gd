##
## RefereeLoader (Autoload singleton)
##
## Owns the live referee pool. Loads custom referees from
## user://custom_referees.json if the file exists, otherwise loads from
## packaged res://data/referees.json, and falls back to built-in programmatic
## referees if neither file is present. CareerManager draws a referee from here
## for each simulated match rather than constructing a RefereeData itself.
##
## Depends on: RefereeData.
## Exposes: referee_pool, get_referee(index), get_random_referee(), save_referees()
##

extends Node

const CUSTOM_REFEREES_PATH: String = "user://custom_referees.json"
const DEFAULT_REFEREES_PATH: String = "res://data/referees.json"

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


## Returns the official for a specific fixture, assigning one if this matchup
## has not been seen before.
##
## Deterministic by design: the same two clubs always draw the same referee for
## a given appointment count, because the pick is seeded from the matchup key
## rather than from a live random stream. Without that, KickOffMenu, the
## pre-game screen and the career fixture card would each roll a DIFFERENT
## official for the very same match and disagree about who was refereeing it.
##
## Weighted by experience like get_random_referee(), but with a penalty for
## officials who have already taken this fixture several times, so a league
## does not end up with one referee permanently attached to one derby.
##
## (This was called by KickOffMenu, PreGameScreen and the career layer before
## it existed — every one of those call sites was a runtime crash.)
func get_or_assign_referee(home_team_name: String, away_team_name: String) -> RefereeData:
	if referee_pool.is_empty():
		return RefereeData.make_default("Unnamed Referee", "Unknown")

	var key: String = RefereeData.make_matchup_key(home_team_name, away_team_name)

	var best: RefereeData = null
	var best_score: float = -1.0
	for i: int in range(referee_pool.size()):
		var ref: RefereeData = referee_pool[i]
		# Stable per (matchup, referee) pseudo-random component.
		var mixed: int = absi(hash(key + "|" + ref.referee_name))
		var jitter: float = float(mixed % 1000) / 1000.0

		var prior: int = 0
		if ref.matchup_history.has(key):
			prior = int((ref.matchup_history[key] as Dictionary).get("matches", 0))

		# Experience raises the odds; repeat appointments lower them.
		var score: float = float(ref.experience) * (0.55 + jitter * 0.9)
		score /= 1.0 + float(prior) * 0.75
		if score > best_score:
			best_score = score
			best = ref

	if best == null:
		best = referee_pool[0]
	# Touching the history here means the NEXT appointment for this fixture is
	# biased away from the same official, which is what spreads them out.
	best.get_or_create_matchup(key)
	return best


## Writes the live referee pool (including career stats) to
## user://custom_referees.json so progress survives between sessions.
func save_referees() -> void:
	var referees: Array = []
	for ref: RefereeData in referee_pool:
		referees.append({
			"name": ref.referee_name,
			"nationality": ref.nationality,
			"secondary_nationality": ref.secondary_nationality,
			"date_of_birth": ref.date_of_birth,
			"spoken_languages": ref.spoken_languages,
			"experience": ref.experience,
			"strictness": ref.strictness,
			"consistency": ref.consistency,
			"composure": ref.composure,
			"unprofessionalism": ref.unprofessionalism,
			"incoherence": ref.incoherence,
			"reputation": ref.reputation,
			"respect_rating": ref.respect_rating,
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
	if FileAccess.file_exists(DEFAULT_REFEREES_PATH):
		if _parse_json_referees(DEFAULT_REFEREES_PATH):
			return
	_build_default_referees()


## Parses a JSON referee file into `referee_pool`.
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
	var name_str: String = referee_dict.get("referee_name", referee_dict.get("name", ""))
	if name_str == "" and referee_dict.has("first_name"):
		name_str = "%s %s" % [referee_dict.get("first_name", ""), referee_dict.get("last_name", "")]

	var data := RefereeData.make_default(
		name_str,
		referee_dict.get("nationality", "Unknown")
	)
	data.experience = int(referee_dict.get("experience", data.experience))
	data.strictness = float(referee_dict.get("strictness", data.strictness))
	data.consistency = float(referee_dict.get("consistency", data.consistency))
	data.composure = float(referee_dict.get("composure", data.composure))
	data.unprofessionalism = float(referee_dict.get("unprofessionalism", data.unprofessionalism))
	data.incoherence = float(referee_dict.get("incoherence", data.incoherence))
	data.reputation = float(referee_dict.get("reputation", data.reputation))
	data.respect_rating = float(referee_dict.get("respect_rating", data.respect_rating))

	data.matches_officiated = int(referee_dict.get("matches_officiated", data.matches_officiated))
	data.fouls_awarded = int(referee_dict.get("fouls_awarded", data.fouls_awarded))
	data.penalties_awarded = int(referee_dict.get("penalties_awarded", data.penalties_awarded))
	data.red_cards_issued = int(referee_dict.get("red_cards_issued", data.red_cards_issued))
	data.secondary_nationality = str(referee_dict.get("secondary_nationality", data.secondary_nationality))
	data.date_of_birth = str(referee_dict.get("date_of_birth", data.date_of_birth))

	var raw_langs: Variant = referee_dict.get("spoken_languages", [])
	var parsed_langs: Array[Dictionary] = []
	if typeof(raw_langs) == TYPE_ARRAY:
		for l_item: Variant in (raw_langs as Array):
			if typeof(l_item) == TYPE_DICTIONARY:
				parsed_langs.append(l_item as Dictionary)
	if not parsed_langs.is_empty():
		data.spoken_languages = parsed_langs
	else:
		var prim_lang: String = NationDatabase.get_primary_language_for_nation(data.nationality)
		data.spoken_languages = [
			{"language": prim_lang, "proficiency": 1.0, "level": "Native"},
			{"language": "English", "proficiency": 0.85, "level": "Fluent"}
		]

	var raw_history: Variant = referee_dict.get("matchup_history", {})
	if typeof(raw_history) == TYPE_DICTIONARY:
		data.matchup_history = raw_history.duplicate()

	return data


## --- Built-in referee pool ------------------------------------------------------

func _build_default_referees() -> void:
	referee_pool = [
		_referee("Domagoj Vrban", "Croatian", 34, 0.72, 0.85, 0.88, 0.04, 0.08, 0.90, 0.92),
		_referee("Ingrid Vaarmo", "Norwegian", 42, 0.88, 0.94, 0.96, 0.01, 0.03, 0.98, 0.96),
		_referee("Kjetil Ørnseth", "Norwegian", 12, 0.32, 0.42, 0.35, 0.18, 0.65, 0.40, 0.38),
		_referee("Tomás Errecarte", "Argentine", 24, 0.65, 0.58, 0.48, 0.42, 0.35, 0.62, 0.55),
		_referee("Arjun Dharmaraj", "English", 20, 0.50, 0.68, 0.78, 0.10, 0.30, 0.68, 0.70),
		_referee("Petru Bálint", "Romanian", 11, 0.82, 0.35, 0.42, 0.30, 0.55, 0.45, 0.42),
		_referee("Jean-Luc Vaneck", "French", 38, 0.24, 0.78, 0.82, 0.08, 0.15, 0.82, 0.85),
		_referee("Kenzo Takahashi", "Japanese", 29, 0.78, 0.90, 0.86, 0.02, 0.06, 0.85, 0.88)
	]


## Shared constructor for the built-in referees.
func _referee(
	referee_name: String, nationality: String, experience: int,
	strictness: float, consistency: float, composure: float,
	unprofessionalism: float, incoherence: float, reputation: float,
	respect_rating: float = 0.50
) -> RefereeData:
	var data := RefereeData.make_default(referee_name, nationality)
	data.experience = experience
	data.strictness = strictness
	data.consistency = consistency
	data.composure = composure
	data.unprofessionalism = unprofessionalism
	data.incoherence = incoherence
	data.reputation = reputation
	data.respect_rating = respect_rating
	return data
