##
## TeamData
##
## Pure data container for one team: name, colour, and the squad of PlayerData
## resources that make it up. Saveable as a .tres resource. No logic — DataLoader
## owns building the default league, and the quick-sim match layer reads squad
## members straight off this container.
##
## Depends on: PlayerData.
## Exposes: the fields below.
##

class_name TeamData
extends Resource

@export var team_id: int = 0
@export var team_name: String = ""
@export var venue_id: int = 0
@export var league_id: int = 0
@export var short_code: String = ""
@export var founded_year: int = 1900
@export var official_website: String = ""
@export var logo_url: String = ""
@export var wikipedia_extract: String = ""
@export var wikidata_qid: String = ""
@export var gender: String = "men"
@export var team_color: Color = Color.WHITE
@export var secondary_color: Color = Color.WHITE
@export var gk_color: Color = Color(0.12, 0.78, 0.42, 1.0)
@export var squad: Array[PlayerData] = []
@export var staff: Array[StaffData] = []

## Active formation string for this match, chosen via the pre-game screen or
## the pause menu. Empty string = use the manager's preferred_formation.
@export var formation_override: String = ""

## Substitutions used this match (max 3, enforced by PauseMenu).
@export var substitutions_made: int = 0

## Indices into `squad` for the 11 players currently in the starting lineup.
## Length must always be 11 when set. Populated by TeamManagementData.apply_to_team().
@export var lineup_indices: Array[int] = []

## Tactical role overrides per starting XI lineup slot (slot 0..10 -> role string, e.g. "CAM", "CDM").
@export var role_overrides: Dictionary = {}

## Squad index of designated team captain (-1 = default/unchanged).
@export var captain_index: int = -1

## --- Club Stature, Reputation & Finances -------------------------------------

## 0.0 = lower tier minnow, 1.0 = world football titan
@export_range(0.0, 1.0) var reputation: float = 0.50
## "Continental Giant", "Top Flight Heavyweight", "Mid-Table Regular", "Relegation Battler", "Lower League Underdog"
@export var stature: String = "Mid-Table Regular"
@export var transfer_budget: int = 10000000
@export var wage_budget_weekly: int = 250000

## Facility levels, 1 (dilapidated) to 5 (state of the art).
@export_range(1, 5) var training_facilities: int = 3
@export_range(1, 5) var youth_facilities: int = 3
@export_range(1, 5) var medical_facilities: int = 3


static func from_db_row(row: Dictionary) -> TeamData:
	var t := TeamData.new()
	var tid: Variant = row.get("team_id")
	if tid != null:
		t.team_id = int(tid)
	var tname: Variant = row.get("name")
	if tname == null:
		tname = row.get("team_name")
	if tname != null:
		t.team_name = str(tname)
	var vid: Variant = row.get("venue_id")
	if vid != null:
		t.venue_id = int(vid)
	var lid: Variant = row.get("league_id")
	if lid != null:
		t.league_id = int(lid)
	var scode: Variant = row.get("short_code")
	if scode != null:
		t.short_code = str(scode)
	var fyear: Variant = row.get("founded_year")
	if fyear != null:
		t.founded_year = int(fyear)
	var web: Variant = row.get("official_website")
	if web != null:
		t.official_website = str(web)
	var logo: Variant = row.get("logo_url")
	if logo != null:
		t.logo_url = str(logo)
	var wiki: Variant = row.get("wikipedia_extract")
	if wiki != null:
		t.wikipedia_extract = str(wiki)
	var qid: Variant = row.get("wikidata_qid")
	if qid != null:
		t.wikidata_qid = str(qid)
	var gen: Variant = row.get("gender")
	if gen != null:
		t.gender = str(gen)

	var h: int = absi(hash(t.team_name))
	var hue: float = float(h % 360) / 360.0
	var sat: float = 0.65 + float((h / 360) % 30) / 100.0
	var val: float = 0.70 + float((h / 10800) % 25) / 100.0
	t.team_color = Color.from_hsv(hue, sat, val)
	t.secondary_color = Color.WHITE if t.team_color.get_luminance() < 0.5 else Color(0.1, 0.1, 0.1)
	var rep: Variant = row.get("reputation")
	if rep != null:
		t.reputation = float(rep)
	else:
		t.reputation = 0.50
	var stat: Variant = row.get("stature")
	if stat != null and str(stat) != "":
		t.stature = str(stat)
	else:
		t.stature = t.get_stature_from_reputation()
	var tb: Variant = row.get("transfer_budget")
	if tb != null:
		t.transfer_budget = int(tb)
	else:
		t.transfer_budget = 10000000
	var wb: Variant = row.get("wage_budget_weekly")
	if wb != null:
		t.wage_budget_weekly = int(wb)
	else:
		t.wage_budget_weekly = 250000
	var tf: Variant = row.get("training_facilities")
	if tf != null:
		t.training_facilities = clampi(int(tf), 1, 5)
	var yf: Variant = row.get("youth_facilities")
	if yf != null:
		t.youth_facilities = clampi(int(yf), 1, 5)
	var mf: Variant = row.get("medical_facilities")
	if mf != null:
		t.medical_facilities = clampi(int(mf), 1, 5)
	return t


## Calculates the sum of weekly wages across the entire squad.
func get_weekly_payroll() -> int:
	var total: int = 0
	for p: PlayerData in squad:
		total += p.wage_weekly
	return total


## Resolves stature tier string from numeric reputation.
func get_stature_from_reputation() -> String:
	if reputation >= 0.85:
		return "Continental Giant"
	elif reputation >= 0.70:
		return "Top Flight Heavyweight"
	elif reputation >= 0.45:
		return "Mid-Table Regular"
	elif reputation >= 0.25:
		return "Relegation Battler"
	return "Lower League Underdog"


## Adjusts reputation and updates the categorical stature tier.
func update_reputation(delta: float) -> void:
	reputation = clampf(reputation + delta, 0.05, 0.99)
	stature = get_stature_from_reputation()


## Finds the first staff member matching the specified role (e.g. "Assistant Manager", "Head Physio").
func get_staff_by_role(role_name: String) -> StaffData:
	for s: StaffData in staff:
		if s.role.nocasecmp_to(role_name) == 0:
			return s
	return null



