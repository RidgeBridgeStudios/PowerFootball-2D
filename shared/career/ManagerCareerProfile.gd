##
## ManagerCareerProfile
##
## The human manager's own career record: who they are, what they are good at,
## and everything that has happened to them across jobs and seasons.
##
## Deliberately NOT a second ManagerData. ManagerData is the per-club tactical
## brain the match layer binds to (ManagerDirector reads it every match), and
## the profile OWNS one of those — `tactical` — which it keeps in sync so the
## human manager's philosophy actually drives their team on the pitch. This
## resource adds the things only a playable career needs: attributes that grow,
## a job history, reputation tiers, and hiring eligibility.
##
## Depends on: ManagerData, ContractData, CareerDate.
## Exposes: the fields below, make_new(), attribute(), train_attribute(),
##          tier_name(), can_apply_to(), record_result(), sync_to_tactical().
##

class_name ManagerCareerProfile
extends Resource

## Reputation tiers gate which jobs will even consider an application.
enum Tier { NON_LEAGUE = 0, LOWER_LEAGUE = 1, ESTABLISHED = 2, TOP_FLIGHT = 3, CONTINENTAL = 4 }

const TIER_NAMES: Array[String] = [
	"Non-League", "Lower League", "Established", "Top Flight", "Continental"
]
## Minimum manager reputation to sit in each tier.
const TIER_THRESHOLDS: Array[float] = [0.0, 0.20, 0.40, 0.62, 0.82]

enum Background { NONE = 0, LOWER_LEAGUE_PLAYER = 1, TOP_FLIGHT_PLAYER = 2, INTERNATIONAL = 3 }

const BACKGROUND_NAMES: Array[String] = [
	"No Playing Experience", "Lower League Player", "Top Flight Player", "Full International"
]

enum Philosophy { POSSESSION = 0, DIRECT = 1, PRESSING = 2, COUNTER = 3, BALANCED = 4 }

const PHILOSOPHY_NAMES: Array[String] = [
	"Possession", "Direct", "Pressing", "Counter-Attack", "Balanced"
]

## Attribute keys. Stored in one dictionary rather than ten @export floats so
## the training/growth code can iterate them generically.
const ATTRIBUTE_KEYS: Array[StringName] = [
	&"tactical_knowledge", &"man_management", &"motivation", &"discipline",
	&"judging_players", &"youth_development", &"tactical_adaptability",
	&"media_handling", &"pressing_philosophy", &"attacking_tendency",
]

const ATTRIBUTE_LABELS: Dictionary = {
	&"tactical_knowledge": "Tactical Knowledge",
	&"man_management": "Man Management",
	&"motivation": "Motivation",
	&"discipline": "Discipline",
	&"judging_players": "Judging Players",
	&"youth_development": "Youth Development",
	&"tactical_adaptability": "Tactical Adaptability",
	&"media_handling": "Media Handling",
	&"pressing_philosophy": "Pressing Philosophy",
	&"attacking_tendency": "Attacking Tendency",
}

## Experience needed to raise one attribute by one point of 20.
const XP_PER_ATTRIBUTE_POINT: float = 100.0

@export var manager_name: String = "New Manager"
@export var nationality: String = "English"
@export var date_of_birth: String = "1985-01-01"
@export var background: Background = Background.NONE
@export var philosophy: Philosophy = Philosophy.BALANCED
@export var preferred_formation: String = "4-4-2"

@export_range(0.0, 1.0) var reputation: float = 0.15
## How favourably the press frames this manager. Feeds PressOffice tone and
## board patience during a bad run.
@export_range(0.0, 1.0) var press_standing: float = 0.5

## StringName -> float, each 1.0 - 20.0 on the FM scale.
@export var attributes: Dictionary = {}
## StringName -> float, accumulated experience toward the next point.
@export var attribute_xp: Dictionary = {}

@export var current_club: String = ""
@export var contract: ContractData = null
@export var unemployed_since: CareerDate = null

## Career totals across every job.
@export var matches_managed: int = 0
@export var wins: int = 0
@export var draws: int = 0
@export var losses: int = 0
@export var trophies_won: int = 0
@export var times_sacked: int = 0
@export var promotions: int = 0
@export var relegations: int = 0

## One entry per job held: {club, from_iso, to_iso, played, won, drawn, lost, outcome}
@export var job_history: Array[Dictionary] = []
## One entry per completed season: {year, club, position, points, competition}
@export var season_history: Array[Dictionary] = []

## The ManagerData the match layer actually binds to for this manager's club.
## Kept in sync by sync_to_tactical() whenever philosophy or attributes change.
@export var tactical: ManagerData = null


static func make_new(
	p_name: String,
	p_nationality: String,
	p_background: Background,
	p_philosophy: Philosophy,
	p_formation: String
) -> ManagerCareerProfile:
	var m := ManagerCareerProfile.new()
	m.manager_name = p_name
	m.nationality = p_nationality
	m.background = p_background
	m.philosophy = p_philosophy
	m.preferred_formation = p_formation

	# Playing background is the starting-attribute seed AND the starting
	# reputation floor: an ex-international walks into the game already known.
	var base: float = 7.0
	match p_background:
		Background.LOWER_LEAGUE_PLAYER:
			base = 8.0
			m.reputation = 0.22
		Background.TOP_FLIGHT_PLAYER:
			base = 9.0
			m.reputation = 0.38
		Background.INTERNATIONAL:
			base = 10.0
			m.reputation = 0.52
		_:
			base = 7.0
			m.reputation = 0.12

	for key: StringName in ATTRIBUTE_KEYS:
		m.attributes[key] = base
		m.attribute_xp[key] = 0.0

	# Philosophy shifts the starting spread — a pressing coach begins with more
	# pressing know-how and less patience for a possession game.
	match p_philosophy:
		Philosophy.POSSESSION:
			m.attributes[&"tactical_knowledge"] = base + 2.0
			m.attributes[&"pressing_philosophy"] = base - 1.0
			m.attributes[&"attacking_tendency"] = base + 1.0
		Philosophy.DIRECT:
			m.attributes[&"attacking_tendency"] = base + 2.0
			m.attributes[&"tactical_knowledge"] = base - 1.0
		Philosophy.PRESSING:
			m.attributes[&"pressing_philosophy"] = base + 3.0
			m.attributes[&"motivation"] = base + 1.0
			m.attributes[&"discipline"] = base - 1.0
		Philosophy.COUNTER:
			m.attributes[&"tactical_adaptability"] = base + 2.0
			m.attributes[&"discipline"] = base + 1.0
			m.attributes[&"attacking_tendency"] = base - 1.0
		_:
			m.attributes[&"tactical_adaptability"] = base + 1.0

	m.tactical = ManagerData.make_default(p_name, p_nationality)
	m.sync_to_tactical()
	return m


func attribute(key: StringName) -> float:
	return float(attributes.get(key, 7.0))


func set_attribute(key: StringName, value: float) -> void:
	attributes[key] = clampf(value, 1.0, 20.0)


## Adds experience toward one attribute, promoting whole points as they are
## earned. Growth slows as an attribute approaches 20 — the last two points
## cost four times what the first ones did.
func train_attribute(key: StringName, xp: float) -> bool:
	var current: float = attribute(key)
	var resistance: float = 1.0 + pow(clampf((current - 10.0) / 10.0, 0.0, 1.0), 2.0) * 3.0
	var gained: float = float(attribute_xp.get(key, 0.0)) + xp / resistance
	var promoted: bool = false
	while gained >= XP_PER_ATTRIBUTE_POINT and current < 20.0:
		gained -= XP_PER_ATTRIBUTE_POINT
		current += 1.0
		promoted = true
	attribute_xp[key] = gained
	set_attribute(key, current)
	if promoted:
		sync_to_tactical()
	return promoted


func tier() -> Tier:
	var t: Tier = Tier.NON_LEAGUE
	for i: int in range(TIER_THRESHOLDS.size()):
		if reputation >= TIER_THRESHOLDS[i]:
			t = i as Tier
	return t


func tier_name() -> String:
	return TIER_NAMES[clampi(int(tier()), 0, TIER_NAMES.size() - 1)]


func background_name() -> String:
	return BACKGROUND_NAMES[clampi(int(background), 0, BACKGROUND_NAMES.size() - 1)]


func philosophy_name() -> String:
	return PHILOSOPHY_NAMES[clampi(int(philosophy), 0, PHILOSOPHY_NAMES.size() - 1)]


## A club will interview this manager if its own reputation is not more than
## one tier above theirs. Being unemployed a long time widens the search.
func can_apply_to(club_reputation: float) -> bool:
	var headroom: float = 0.18
	return club_reputation <= reputation + headroom


func win_rate() -> float:
	if matches_managed == 0:
		return 0.0
	return float(wins) / float(matches_managed)


func record_result(goals_for: int, goals_against: int) -> void:
	matches_managed += 1
	if goals_for > goals_against:
		wins += 1
	elif goals_for < goals_against:
		losses += 1
	else:
		draws += 1


## Pushes philosophy and attributes down onto the ManagerData the match layer
## binds to, so the human manager's choices actually reach ManagerDirector and
## are not just profile decoration.
func sync_to_tactical() -> void:
	if tactical == null:
		tactical = ManagerData.make_default(manager_name, nationality)

	tactical.manager_name = manager_name
	tactical.nationality = nationality
	tactical.date_of_birth = date_of_birth
	tactical.current_team = current_club
	tactical.reputation = reputation
	tactical.preferred_formation = preferred_formation
	tactical.experience = int(round(clampf(reputation * 60.0 + float(matches_managed) * 0.15, 1.0, 100.0)))

	# Attributes are on a 1-20 FM scale; ManagerData's sliders are 0-1.
	var press_attr: float = attribute(&"pressing_philosophy") / 20.0
	var attack_attr: float = attribute(&"attacking_tendency") / 20.0
	var adapt_attr: float = attribute(&"tactical_adaptability") / 20.0

	match philosophy:
		Philosophy.POSSESSION:
			tactical.tempo = 0.30
			tactical.width = 0.62
			tactical.defensive_line = 0.62
		Philosophy.DIRECT:
			tactical.tempo = 0.82
			tactical.width = 0.55
			tactical.defensive_line = 0.48
		Philosophy.PRESSING:
			tactical.tempo = 0.68
			tactical.width = 0.60
			tactical.defensive_line = 0.78
		Philosophy.COUNTER:
			tactical.tempo = 0.72
			tactical.width = 0.42
			tactical.defensive_line = 0.28
		_:
			tactical.tempo = 0.50
			tactical.width = 0.50
			tactical.defensive_line = 0.50

	# The attribute sliders modulate the philosophy preset rather than
	# replacing it, so two pressing managers of different quality press
	# differently.
	tactical.pressing_intensity = clampf(tactical.tempo * 0.35 + press_attr * 0.75, 0.05, 1.0)
	tactical.physicality = clampf(0.30 + (1.0 - attack_attr) * 0.45, 0.05, 1.0)
	tactical.youth_trust = clampf(attribute(&"youth_development") / 20.0, 0.05, 1.0)
	tactical.form_sensitivity = clampf(attribute(&"discipline") / 20.0, 0.05, 1.0)
	tactical.loyalty_bias = clampf(attribute(&"man_management") / 25.0, 0.05, 1.0)

	# Adaptability decides whether this manager shifts shape at all mid-match:
	# a rigid coach reads as Idealist (512) to ManagerDirector, which collapses
	# both shift targets onto the preferred formation.
	if adapt_attr < 0.35:
		tactical.traits = tactical.traits | 512
		tactical.attacking_formation = preferred_formation
		tactical.defensive_formation = preferred_formation
	else:
		tactical.traits = tactical.traits & ~512
		tactical.attacking_formation = "4-3-3"
		tactical.defensive_formation = "5-3-2"

	# Media handling maps onto the press-voice traits PressOffice switches on.
	if attribute(&"media_handling") >= 14.0:
		tactical.traits = tactical.traits | 128
	else:
		tactical.traits = tactical.traits & ~128


func get_age(ref_year: int = 2026, ref_month: int = 9, ref_day: int = 1) -> int:
	var parts: PackedStringArray = date_of_birth.split("-")
	if parts.size() < 3:
		return 40
	var age: int = ref_year - parts[0].to_int()
	if ref_month < parts[1].to_int() or (ref_month == parts[1].to_int() and ref_day < parts[2].to_int()):
		age -= 1
	return maxi(21, age)
