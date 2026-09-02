##
## StaffData
##
## Pure data container for one backroom staff member (Assistant Manager, Head Physio,
## Tactical Analyst, Fitness Coach, Chief Scout): identity, role, nationality,
## spoken languages, date of birth, and coaching/medical attributes.
## Saveable as a .tres resource.
##
## Depends on: NationDatabase.
## Exposes: staff_name, role, team_name, nationality, secondary_nationality,
##          date_of_birth, spoken_languages, get_age, get_age_detail_string,
##          speaks_language, get_language_level, make_default.
##

class_name StaffData
extends Resource

## --- Identity ----------------------------------------------------------------

@export var staff_name: String = ""
## "Assistant Manager", "Head Physio", "Tactical Analyst", "Fitness Coach", "Chief Scout"
@export var role: String = "Assistant Manager"
@export var team_name: String = ""
@export var nationality: String = ""
@export var secondary_nationality: String = ""
## ISO "YYYY-MM-DD"
@export var date_of_birth: String = "1982-01-01"
## Array of Dictionaries: [{"language": "English", "proficiency": 1.0, "level": "Native"}, ...]
@export var spoken_languages: Array[Dictionary] = []

## --- Attributes --------------------------------------------------------------

## 1-100 career experience
@export var experience: int = 20
## Coaching capability (0.0 to 1.0)
@export_range(0.0, 1.0) var coaching: float = 0.70
## Judging player ability / potential (0.0 to 1.0)
@export_range(0.0, 1.0) var judging_ability: float = 0.70
## Medical / recovery capability (0.0 to 1.0)
@export_range(0.0, 1.0) var physiotherapy: float = 0.70
## Tactical analysis capability (0.0 to 1.0)
@export_range(0.0, 1.0) var tactical_knowledge: float = 0.70

## --- Contract ----------------------------------------------------------------

@export var salary_weekly: int = 6000
@export var contract_years: int = 2


## Calculates current age in full completed years from date_of_birth.
func get_age(ref_year: int = 2026, ref_month: int = 9, ref_day: int = 1) -> int:
	if date_of_birth == "":
		return 40
	var parts: PackedStringArray = date_of_birth.split("-")
	if parts.size() < 3:
		return 40
	var b_year: int = parts[0].to_int()
	var b_month: int = parts[1].to_int()
	var b_day: int = parts[2].to_int()
	var age: int = ref_year - b_year
	if ref_month < b_month or (ref_month == b_month and ref_day < b_day):
		age -= 1
	return maxi(22, age)


## Formats age and date of birth: e.g. "44 yrs (28/07/1982)".
func get_age_detail_string(ref_year: int = 2026, ref_month: int = 9, ref_day: int = 1) -> String:
	var age: int = get_age(ref_year, ref_month, ref_day)
	if date_of_birth == "":
		return "%d yrs" % age
	var parts: PackedStringArray = date_of_birth.split("-")
	if parts.size() == 3:
		return "%d yrs (%s/%s/%s)" % [age, parts[2], parts[1], parts[0]]
	return "%d yrs (%s)" % [age, date_of_birth]


## Checks if the staff member understands a given language at or above the threshold.
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


static func make_default(p_name: String, p_role: String, p_nationality: String) -> StaffData:
	var s := StaffData.new()
	s.staff_name = p_name
	s.role = p_role
	s.nationality = p_nationality
	var prim_lang: String = NationDatabase.get_primary_language_for_nation(p_nationality)
	s.spoken_languages = [
		{"language": prim_lang, "proficiency": 1.0, "level": "Native"},
		{"language": "English", "proficiency": 0.85, "level": "Fluent"}
	]
	return s
