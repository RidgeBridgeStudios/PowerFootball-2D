##
## ManagerData
##
## Pure data container for one manager: identity, tactical philosophy, squad
## and signing preferences, personality traits, and career stats. Saveable as
## a .tres resource so a manager can be authored and edited without touching a
## scene, the same way PlayerData is. QuickSimEngine and PressOffice are what
## turn an instance of this into match behaviour and press quotes — this
## resource never touches a Node.
##
## current_team matches TeamData.team_name of the team this manager manages.
## No reference to TeamData itself is kept — data independence is mandatory.
##
## Depends on: nothing.
## Exposes: the fields below, has_trait(), get_win_rate(), get_goal_difference(),
##          make_default().
##

class_name ManagerData
extends Resource

## --- Identity ------------------------------------------------------------

@export var manager_name: String = ""
@export var nationality: String = ""
@export var secondary_nationality: String = ""
## ISO "YYYY-MM-DD"
@export var date_of_birth: String = "1975-01-01"
## Array of Dictionaries: [{"language": "Nordlandic", "proficiency": 1.0, "level": "Native"}, ...]
@export var spoken_languages: Array[Dictionary] = []
## 1-100. Higher = more settled tactical system, more media confidence.
@export var experience: int = 30
## Matches TeamData.team_name of the team this manager manages.
## Empty string means the manager is available for hire.
@export var current_team: String = ""

## --- Reputation, Security & Contract -----------------------------------------

## 0.0 = rookie coach, 1.0 = legendary tactician
@export_range(0.0, 1.0) var reputation: float = 0.50
## 0.0 = on brink of sacking, 1.0 = untouchable idol
@export_range(0.0, 1.0) var board_confidence: float = 0.65
@export var contract_years: int = 2
@export var salary_weekly: int = 25000
## Respect/temperament towards match officials (0.0 = combative critic, 1.0 = respectful diplomat)
@export_range(0.0, 1.0) var referee_respect: float = 0.60

## --- Tactical philosophy ---------------------------------------------------

## 0 = deep compact block, 1 = aggressive high line.
## Shifts formation-anchor Y values up the pitch.
@export_range(0.0, 1.0) var defensive_line: float = 0.5
## 0 = patient possession build-up (low formation_ball_weight),
## 1 = direct / counter-attack (high formation_ball_weight).
@export_range(0.0, 1.0) var tempo: float = 0.5
## 0 = narrow shape, 1 = wide shape.
## Scales formation-anchor X spread by this.
@export_range(0.0, 1.0) var width: float = 0.5
## 0 = passive mid-block, 1 = relentless gegenpressing.
## Raises aggression_attribute and shortens decision_interval on all players.
@export_range(0.0, 1.0) var pressing_intensity: float = 0.5
## 0 = avoids contact, 1 = seeks it. Adds a secondary boost to aggression_attribute.
@export_range(0.0, 1.0) var physicality: float = 0.5

## The formation applied at kick-off and whenever the scoreline is level.
@export var preferred_formation: String = "4-4-2"
## Shifted to when losing and time is running out.
@export var attacking_formation: String = "4-3-3"
## Shifted to when protecting a lead late in the match.
@export var defensive_formation: String = "4-4-2"

## --- Squad philosophy ------------------------------------------------------

## How much the manager trusts youth (0 = never plays U21, 1 = embraces them).
@export_range(0.0, 1.0) var youth_trust: float = 0.5
## How much the manager values loyalty over form when picking a lineup.
## 0 = pure meritocracy, 1 = always plays established favourites.
@export_range(0.0, 1.0) var loyalty_bias: float = 0.5
## How harshly the manager reacts to a player's poor performance.
## 0 = patient, 1 = immediately dropped.
@export_range(0.0, 1.0) var form_sensitivity: float = 0.5

## --- Signing philosophy (career mode transfer logic) -----------------------

@export var preferred_min_age: int = 20
@export var preferred_max_age: int = 30
## 0 = budget-conscious, 1 = willing to pay premium for quality.
@export_range(0.0, 1.0) var budget_flexibility: float = 0.5
## Preferred physical build. Governs which PlayerData mass values this manager
## rates highly in transfer scouting.
@export var preferred_mass_min: float = 65.0
@export var preferred_mass_max: float = 90.0
## The player attribute the manager prizes most when scouting.
## Valid values: "vision", "composure", "aggression", "none".
@export var prized_attribute: String = "none"
## Playstyle tag the manager recruits toward.
## Valid values: "technical", "physical", "pace", "aerial", "engine", "none".
@export var preferred_playstyle: String = "none"

## --- Personality traits -----------------------------------------------------
##
## HotHead (1)         — blunt press, escalates pressing after the 2nd conceded goal.
## Loyalist (2)         — never blames players in press; loyalty_bias reads as 1.0 (future feature tag).
## Pragmatist (4)       — dry press; shifts to defensive_formation at +1 instead of +2.
## Visionary (8)        — talks systems in press; midfield formation_ball_weight +0.10 (cap 0.75).
## Disciplinarian (16)  — accountable press; composure_attribute floor of 0.40.
## MindGames (32)       — undermines opponents pre-match; no in-match effect.
## Sentimental (64)     — nostalgic press; no in-match effect.
## MediaSavvy (128)     — polished, on-message press; no in-match effect.
## Volatile (256)       — unpredictable press tone; randomises _live_pressing +-0.15 after a shift.
## Idealist (512)       — never changes tactical stance; attacking/defensive formation locked to preferred.
@export_flags(
	"HotHead:1",
	"Loyalist:2",
	"Pragmatist:4",
	"Visionary:8",
	"Disciplinarian:16",
	"MindGames:32",
	"Sentimental:64",
	"MediaSavvy:128",
	"Volatile:256",
	"Idealist:512"
) var traits: int = 0


func has_trait(bit: int) -> bool:
	return (traits & bit) != 0


## --- Career stats ------------------------------------------------------------
## Not @export: written back by QuickSimEngine after a simulated match
## and persisted through ManagerLoader.save_managers(), the same split PlayerData
## uses between authored fields and runtime-accumulated ones.

var matches_managed: int = 0
var wins: int = 0
var draws: int = 0
var losses: int = 0
var goals_scored: int = 0
var goals_conceded: int = 0


func get_win_rate() -> float:
	if matches_managed == 0:
		return 0.0
	return float(wins) / float(matches_managed)


func get_goal_difference() -> int:
	return goals_scored - goals_conceded


static func make_default(p_name: String, p_nationality: String) -> ManagerData:
	var m := ManagerData.new()
	m.manager_name = p_name
	m.nationality = p_nationality
	var prim_lang: String = NationDatabase.get_primary_language_for_nation(p_nationality)
	m.spoken_languages = [
		{"language": prim_lang, "proficiency": 1.0, "level": "Native"},
		{"language": "English", "proficiency": 0.85, "level": "Fluent"}
	]
	return m


func update_board_confidence(delta: float) -> void:
	board_confidence = clampf(board_confidence + delta, 0.0, 1.0)


func update_reputation(delta: float) -> void:
	reputation = clampf(reputation + delta, 0.05, 0.99)


## Calculates current age in full completed years from date_of_birth.
func get_age(ref_year: int = 2026, ref_month: int = 9, ref_day: int = 1) -> int:
	if date_of_birth == "":
		return 45
	var parts: PackedStringArray = date_of_birth.split("-")
	if parts.size() < 3:
		return 45
	var b_year: int = parts[0].to_int()
	var b_month: int = parts[1].to_int()
	var b_day: int = parts[2].to_int()
	var age: int = ref_year - b_year
	if ref_month < b_month or (ref_month == b_month and ref_day < b_day):
		age -= 1
	return maxi(25, age)


## Formats age and date of birth: e.g. "52 yrs (12/08/1974)".
func get_age_detail_string(ref_year: int = 2026, ref_month: int = 9, ref_day: int = 1) -> String:
	var age: int = get_age(ref_year, ref_month, ref_day)
	if date_of_birth == "":
		return "%d yrs" % age
	var parts: PackedStringArray = date_of_birth.split("-")
	if parts.size() == 3:
		return "%d yrs (%s/%s/%s)" % [age, parts[2], parts[1], parts[0]]
	return "%d yrs (%s)" % [age, date_of_birth]


## Checks if the manager understands a given language at or above the threshold.
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

