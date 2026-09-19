##
## PlayerData
##
## Pure data container for one player: identity, physical profile, and
## personality. Saveable as a .tres resource so a squad can be authored and
## edited without touching a scene. The quick-sim match layer reads an instance
## of this directly — this resource never touches a Node.
##
## Depends on: nothing.
## Exposes: the fields below and make_default().
##

class_name PlayerData
extends Resource

## --- Identity ----------------------------------------------------------------

@export var player_id: int = 0
@export var player_name: String = ""
@export var first_name: String = ""
@export var last_name: String = ""
@export var shirt_number: int = 0
## "GK", "CB", "LB", "RB", "DM", "CM", "AM", "LW", "RW", "ST"
@export var position_role: String = ""
@export var is_captain: bool = false
@export var nationality: String = ""
@export var secondary_nationality: String = ""
## ISO "YYYY-MM-DD"
@export var date_of_birth: String = "2000-01-01"
@export var gender: String = "men"
@export var height_cm: int = 180
@export var weight_kg: float = 75.0
@export var image_url: String = ""
## Array of Dictionaries: [{"language": "Nordlandic", "proficiency": 1.0, "level": "Native"}, ...]
@export var spoken_languages: Array[Dictionary] = []

## --- Physical identity — read by quick-sim ratings and player development ----

@export var mass: float = 75.0
@export var top_speed: float = 210.0
## FM2D compromise: baseline acceleration time reduced to 0.22s for snappier takeoff without feeling weightless.
@export var acceleration_time: float = 0.22
## FM2D compromise: friction time reduced to 0.12s for crisp stopping distance while preserving natural roll-out.
@export var friction_time: float = 0.12
## FM2D compromise: turning penalty reduced to 0.35 so turns feel responsive while full reversals still bleed momentum.
@export var turning_penalty: float = 0.35
@export var sprint_multiplier: float = 1.45

## --- Stamina -------------------------------------------------------------------

@export var stamina_max: float = 100.0
@export var stamina_drain: float = 18.0
@export var stamina_recover: float = 9.0

## --- Personality — drives quick-sim ratings, scouting, and progression --------

@export_range(0.0, 1.0) var vision: float = 0.75
@export_range(0.0, 1.0) var composure: float = 0.60
@export_range(0.0, 1.0) var aggression: float = 0.80
@export_range(0.0, 1.0) var formation_ball_weight: float = 0.35

## Close-ball control: higher keeps the ball tighter during dribbling.
@export_range(0.0, 1.0) var close_control: float = 0.65

## Goalkeeper reaction speed: 0.0 = sluggish, 1.0 = elite reactions. Feeds the
## dive-commitment error model — a keeper with low reflexes dives the wrong way
## more often when facing a shot.
@export_range(0.0, 1.0) var reflexes: float = 0.6

## --- Football Manager Mental Attributes & Personality -------------------------

@export_range(0.0, 1.0) var determination: float = 0.65
@export_range(0.0, 1.0) var work_rate: float = 0.65
@export_range(0.0, 1.0) var leadership: float = 0.50
@export_range(0.0, 1.0) var temperament: float = 0.60
@export_range(0.0, 1.0) var professionalism: float = 0.65
@export_range(0.0, 1.0) var ambition: float = 0.60
@export_range(0.0, 1.0) var loyalty: float = 0.60
@export_range(0.0, 1.0) var adaptability: float = 0.55

## Player trait bitmask
@export_flags(
	"DeepRunner:1",
	"WallSplitter:2",
	"PressureImmune:4",
	"HotHeadedTackler:8",
	"Talisman:16",
	"LockerRoomCancer:32",
	"CaptainMaterial:64",
	"StreetBaller:128",
	"PrideGlory:256",
	"VeteranLeader:512",
	"DeadBallSpecialist:1024",
	"NightOwl:2048",
	"IronMan:4096"
) var traits: int = 0

## Player fame / reputation (0.0 = unknown rookie, 1.0 = world superstar).
@export_range(0.0, 1.0) var player_reputation: float = 0.50

## --- Career Contract & Economics ---------------------------------------------

@export var wage_weekly: int = 15000
@export var contract_years: int = 3
@export var release_clause: int = 0
## "Star Player", "Important", "Regular Starter", "Rotation", "Squad Player", "Prospect"
@export var squad_status: String = "Regular Starter"
@export_range(0.0, 1.0) var morale: float = 0.70
@export var market_value: int = 2500000

## --- Live form and career stats — read by the pre-game screen and pause menu ---

## Per-match rolling form (0.0 - 10.0). Persists across matches; decays
## slightly each match a player does not feature. Default 6.5 = neutral form.
@export var form: float = 6.5

## Career goals and assists — accumulated by accumulate_match_stats() each match.
@export var career_goals: int = 0
@export var career_assists: int = 0

## Career Moneyball & advanced analytics metrics
@export var career_xg: float = 0.0
@export var career_xa: float = 0.0
@export var career_xt_delta: float = 0.0
@export var career_progressive_passes: int = 0
@export var career_progressive_carries: int = 0
@export var career_packing_count: int = 0
@export var career_vaep: float = 0.0
@export var career_tackles_won: int = 0
@export var career_interceptions: int = 0
@export var career_clean_sheets: int = 0
@export var career_psxg_prevented: float = 0.0
@export var career_touches: int = 0

## Match rating assigned at end of the last match (0.0 - 10.0). 0.0 = did not play.
@export var last_match_rating: float = 0.0
@export var last_match_touches: int = 0

## Whether this player is marked as unavailable (injured/suspended) for
## the next match. The pre-game screen reads this and greys out the card.
@export var is_unavailable: bool = false

## --- Transient per-match card counts -------------------------------------------
## Reset to 0 by the pre-pivot match layer, archived under legacy/. Not persisted —
## RefereeData.red_cards_issued is the career stat.
var yellow_cards_this_match: int = 0
var red_cards_this_match: int = 0


## Accumulates end-of-match stats from PlayerMatchEvents into career totals.
func accumulate_match_stats(events: PlayerRatingCalculator.PlayerMatchEvents) -> void:
	career_goals += events.goals
	career_assists += events.assists
	career_xg += events.xg
	career_xa += events.xa
	career_xt_delta += events.xt_delta
	career_progressive_passes += events.progressive_passes
	career_progressive_carries += events.progressive_carries
	career_packing_count += events.packing_count
	career_vaep += events.vaep
	career_tackles_won += events.tackles_won
	career_interceptions += events.interceptions
	career_psxg_prevented += events.goals_prevented
	career_touches += events.get_touches()
	last_match_touches = events.get_touches()
	if events.kept_clean_sheet:
		career_clean_sheets += 1



static func from_db_row(row: Dictionary) -> PlayerData:
	var d := PlayerData.new()
	var pid: Variant = row.get("player_id")
	if pid != null:
		d.player_id = int(pid)
	var pname: Variant = row.get("player_name")
	if pname != null:
		d.player_name = str(pname)
	var fname: Variant = row.get("first_name")
	if fname != null:
		d.first_name = str(fname)
	var lname: Variant = row.get("last_name")
	if lname != null:
		d.last_name = str(lname)

	var pos: Variant = row.get("position_role")
	if pos == null:
		pos = row.get("position_name")
	if pos != null:
		d.position_role = str(pos)
	else:
		d.position_role = "CM"

	var nat: Variant = row.get("nationality")
	if nat != null:
		d.nationality = str(nat)
	var dob: Variant = row.get("date_of_birth")
	if dob != null:
		d.date_of_birth = str(dob)
	var gen: Variant = row.get("gender")
	if gen != null:
		d.gender = str(gen)
	var h: Variant = row.get("height_cm")
	if h != null:
		d.height_cm = int(h)
	var w: Variant = row.get("weight_kg")
	if w != null:
		d.weight_kg = float(w)
	var img: Variant = row.get("image_url")
	if img != null:
		d.image_url = str(img)

	var num: Variant = row.get("jersey_number")
	if num == null:
		num = row.get("shirt_number")
	if num != null:
		d.shirt_number = int(num)

	if row.has("mass") and row["mass"] != null:
		d.mass = float(row["mass"])
	if row.has("top_speed") and row["top_speed"] != null:
		d.top_speed = float(row["top_speed"])
	if row.has("stamina_max") and row["stamina_max"] != null:
		d.stamina_max = float(row["stamina_max"])
	if row.has("vision") and row["vision"] != null:
		d.vision = float(row["vision"])
	if row.has("composure") and row["composure"] != null:
		d.composure = float(row["composure"])
	if row.has("aggression") and row["aggression"] != null:
		d.aggression = float(row["aggression"])
	if row.has("close_control") and row["close_control"] != null:
		d.close_control = float(row["close_control"])
	if row.has("reflexes") and row["reflexes"] != null:
		d.reflexes = float(row["reflexes"])
	if row.has("determination") and row["determination"] != null:
		d.determination = float(row["determination"])
	if row.has("work_rate") and row["work_rate"] != null:
		d.work_rate = float(row["work_rate"])

	if d.mass <= 0.0:
		d.mass = 75.0
	if d.top_speed <= 0.0:
		d.top_speed = 210.0
	if d.stamina_max <= 0.0:
		d.stamina_max = 100.0
	if d.date_of_birth == "":
		d.date_of_birth = "2000-01-01"
	if d.nationality == "":
		d.nationality = "English"
	if d.spoken_languages.is_empty():
		var prim_lang: String = NationDatabase.get_primary_language_for_nation(d.nationality)
		d.spoken_languages = [
			{"language": prim_lang, "proficiency": 1.0, "level": "Native"},
			{"language": "English", "proficiency": 0.85, "level": "Fluent"}
		]
	if d.wage_weekly <= 0:
		d.wage_weekly = 15000
	if d.contract_years <= 0:
		d.contract_years = 3

	d.apply_role_defaults(d.position_role)
	return d


static func make_default(player_name: String, shirt_number: int, position_role: String) -> PlayerData:
	var d := PlayerData.new()
	d.player_name = player_name
	d.shirt_number = shirt_number
	d.position_role = position_role
	d.nationality = "Norwegian"
	d.date_of_birth = "2001-05-15"
	d.spoken_languages = [
		{"language": "Norwegian", "proficiency": 1.0, "level": "Native"},
		{"language": "English", "proficiency": 0.75, "level": "Fluent"}
	]
	d.apply_role_defaults(position_role)
	return d


## Applies FM2D compromise physics defaults based on position archetype.
func apply_role_defaults(role: String) -> void:
	match role.to_upper():
		"LW", "RW", "AM", "LM", "RM", "CAM", "LAM", "RAM":
			# Wingers / attacking mids: agile acceleration (0.15s) and low turning penalty (0.25) for 1v1 take-ons.
			acceleration_time = 0.15
			turning_penalty = 0.25
		"CB", "DM", "CDM", "GK":
			# Centre-backs / defensive mids / goalkeeper: heavier acceleration (0.32s) and higher penalty (0.50) to anchor defence.
			acceleration_time = 0.32
			turning_penalty = 0.50
		_:
			# Central mids / strikers / fullbacks / default: balanced baseline compromise (0.22s accel, 0.35 turning penalty).
			acceleration_time = 0.22
			turning_penalty = 0.35


func has_trait(bit: int) -> bool:
	return (traits & bit) != 0


## Calculates composite overall rating (1..99) weighted by positional archetype.
func calculate_overall_rating() -> int:
	var physical_score: float = (
		(top_speed - 170.0) / 90.0 * 0.35 +
		(0.38 - acceleration_time) / 0.26 * 0.35 +
		(stamina_max - 75.0) / 50.0 * 0.30
	)
	var mental_score: float = (
		determination * 0.25 +
		composure * 0.25 +
		vision * 0.20 +
		work_rate * 0.15 +
		temperament * 0.15
	)
	var technical_score: float = close_control

	var raw_rating: float = 50.0
	match position_role.to_upper():
		"GK":
			raw_rating = reflexes * 50.0 + composure * 25.0 + vision * 15.0 + physical_score * 10.0
		"CB":
			raw_rating = physical_score * 35.0 + aggression * 25.0 + determination * 20.0 + composure * 20.0
		"LB", "RB":
			raw_rating = physical_score * 40.0 + work_rate * 25.0 + technical_score * 20.0 + vision * 15.0
		"DM", "CDM":
			raw_rating = work_rate * 30.0 + physical_score * 25.0 + composure * 25.0 + vision * 20.0
		"CM":
			raw_rating = vision * 30.0 + technical_score * 25.0 + work_rate * 25.0 + composure * 20.0
		"AM", "CAM", "LM", "RM", "LW", "RW":
			raw_rating = technical_score * 35.0 + vision * 25.0 + physical_score * 25.0 + composure * 15.0
		"ST":
			raw_rating = technical_score * 35.0 + physical_score * 30.0 + composure * 20.0 + determination * 15.0
		_:
			raw_rating = physical_score * 30.0 + mental_score * 40.0 + technical_score * 30.0

	var ovr: int = int(round(clampf(45.0 + raw_rating * 0.52, 45.0, 99.0)))
	return ovr


## Calculates star rating derivative score (0.0 to 1.0) combining reputation and overall ability.
func get_star_score() -> float:
	var ovr: float = float(calculate_overall_rating())
	return clampf((player_reputation * 0.55) + ((ovr / 100.0) * 0.45), 0.0, 1.0)


## Returns whether player reaches the Star tier threshold (star score >= 0.72).
func is_star() -> bool:
	return get_star_score() >= 0.72


## Evaluates mental attributes into Football Manager personality archetypes.
func get_personality_archetype() -> String:
	if professionalism >= 0.80 and determination >= 0.75:
		return "Model Professional"
	elif leadership >= 0.80 and determination >= 0.70:
		return "Born Leader"
	elif determination >= 0.80 and ambition >= 0.70:
		return "Resolute"
	elif ambition >= 0.80 and loyalty <= 0.35:
		return "Mercenary"
	elif temperament <= 0.35 and aggression >= 0.75:
		return "Temperamental"
	elif work_rate >= 0.80 and determination >= 0.70:
		return "Spirited"
	elif professionalism >= 0.75 and temperament >= 0.75:
		return "Fair Play Advocate"
	elif ambition >= 0.80:
		return "Ambitious"
	elif ambition <= 0.35 and loyalty >= 0.75:
		return "Loyal Servant"
	return "Balanced"


## Estimates market value based on overall rating, reputation, and contract length.
func calculate_market_value() -> int:
	var ovr: int = calculate_overall_rating()
	var base_val: float = 200000.0 * pow(1.08, float(ovr - 50))
	var rep_mult: float = lerp(0.6, 2.5, player_reputation)
	var contract_mult: float = 0.5 + float(contract_years) * 0.25
	return int(round(base_val * rep_mult * contract_mult))


## Calculates current age in full completed years from date_of_birth.
func get_age(ref_year: int = 2026, ref_month: int = 9, ref_day: int = 1) -> int:
	if date_of_birth == "":
		return 24
	var parts: PackedStringArray = date_of_birth.split("-")
	if parts.size() < 3:
		return 24
	var b_year: int = parts[0].to_int()
	var b_month: int = parts[1].to_int()
	var b_day: int = parts[2].to_int()
	var age: int = ref_year - b_year
	if ref_month < b_month or (ref_month == b_month and ref_day < b_day):
		age -= 1
	return maxi(15, age)


## Formats age and date of birth: e.g. "24 yrs (14/04/2002)".
func get_age_detail_string(ref_year: int = 2026, ref_month: int = 9, ref_day: int = 1) -> String:
	var age: int = get_age(ref_year, ref_month, ref_day)
	if date_of_birth == "":
		return "%d yrs" % age
	var parts: PackedStringArray = date_of_birth.split("-")
	if parts.size() == 3:
		return "%d yrs (%s/%s/%s)" % [age, parts[2], parts[1], parts[0]]
	return "%d yrs (%s)" % [age, date_of_birth]


## Checks if the player understands a given language at or above the threshold.
func speaks_language(lang_name: String, min_proficiency: float = 0.25) -> bool:
	for entry: Dictionary in spoken_languages:
		var l: String = str(entry.get("language", ""))
		var p: float = float(entry.get("proficiency", 0.0))
		if l.nocasecmp_to(lang_name) == 0 and p >= min_proficiency:
			return true
	return false


## Returns the Football Manager proficiency level string for a given language.
func get_language_level(lang_name: String) -> String:
	for entry: Dictionary in spoken_languages:
		var l: String = str(entry.get("language", ""))
		if l.nocasecmp_to(lang_name) == 0:
			return str(entry.get("level", "Basic"))
	return "None"


## Returns the numeric proficiency (0.0 to 1.0) for a given language.
func get_language_proficiency(lang_name: String) -> float:
	for entry: Dictionary in spoken_languages:
		var l: String = str(entry.get("language", ""))
		if l.nocasecmp_to(lang_name) == 0:
			return float(entry.get("proficiency", 0.0))
	return 0.0

