##
## YouthAcademy
##
## Generates the annual youth intake and manages the development squad.
##
## An intake is the club's one guaranteed source of free talent, so its quality
## has to be a real consequence of decisions made months earlier: youth
## facilities, the manager's youth_development attribute, and the club's own
## reputation all shift both the SIZE of the cohort and the potential ceilings
## rolled for it.
##
## Crucially the ceilings are hidden. An intake arrives with wide scouting
## bands and the manager has to decide who to keep on incomplete information —
## which is the entire point of a youth system.
##
## Depends on: PlayerData, PlayerCareerState, TeamData, BoardState, CareerDate,
##             PlayerDevelopmentEngine, NationDatabase.
## Exposes: generate_intake(), intake_report(), promote_to_first_team(),
##          release_youth().
##

class_name YouthAcademy
extends RefCounted

const MIN_INTAKE: int = 3
const MAX_INTAKE: int = 8
## Youth players arrive between these ages.
const INTAKE_MIN_AGE: int = 15
const INTAKE_MAX_AGE: int = 18

const FIRST_NAMES: Array[String] = [
	"Aksel", "Bo", "Caspar", "Dario", "Emil", "Felix", "Gustav", "Halvor",
	"Ivar", "Jonas", "Kai", "Lars", "Mikkel", "Nico", "Otto", "Pelle",
	"Quinn", "Rasmus", "Stig", "Tobias", "Ulrik", "Viktor", "Wilmer", "Yannick",
	"Andrei", "Bruno", "Cesar", "Diego", "Enzo", "Fabio", "Gino", "Hugo",
	"Iker", "Javier", "Kiko", "Luca", "Marco", "Nuno", "Oriol", "Paulo",
]

const LAST_NAMES: Array[String] = [
	"Aaberg", "Berg", "Dahl", "Ek", "Fjell", "Gran", "Holm", "Iversen",
	"Jenssen", "Krog", "Lund", "Moen", "Nyborg", "Osland", "Prang", "Rud",
	"Sand", "Torp", "Ulven", "Vik", "Wold", "Ytre",
	"Alvarez", "Bravo", "Costa", "Duarte", "Esteban", "Ferrer", "Gil", "Herrera",
	"Iglesias", "Jimenez", "Lozano", "Mendes", "Navarro", "Ortega", "Pena", "Quiroga",
]

const INTAKE_ROLES: Array[String] = [
	"GK", "CB", "CB", "LB", "RB", "DM", "CM", "CM", "AM", "LW", "RW", "ST", "ST"
]


## Rolls a fresh cohort for one club. Returns the new PlayerData entries; the
## caller is responsible for appending them to the squad and creating the
## matching PlayerCareerState (see CareerManager._run_youth_intake).
static func generate_intake(
	club: TeamData,
	board: BoardState,
	manager_youth_attribute: float,
	today: CareerDate,
	rng: RandomNumberGenerator
) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	if club == null:
		return out

	var facility_mult: float = board.facility_multiplier(board.youth_facilities) if board != null else 1.0
	# Cohort size: facilities and reputation decide how many bodies come
	# through; the manager's youth development decides how good they are.
	var quality_bias: float = clampf(
		facility_mult * 0.45 + club.reputation * 0.30 + clampf(manager_youth_attribute / 20.0, 0.0, 1.0) * 0.25,
		0.1, 1.2
	)
	var count: int = clampi(
		MIN_INTAKE + int(round(float(MAX_INTAKE - MIN_INTAKE) * clampf(quality_bias - 0.2, 0.0, 1.0))),
		MIN_INTAKE, MAX_INTAKE
	)

	var used_numbers: Array[int] = []
	for p: PlayerData in club.squad:
		used_numbers.append(p.shirt_number)

	for i: int in range(count):
		var role: String = INTAKE_ROLES[rng.randi_range(0, INTAKE_ROLES.size() - 1)]
		var full_name: String = "%s %s" % [
			FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)],
			LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]
		]
		var age: int = rng.randi_range(INTAKE_MIN_AGE, INTAKE_MAX_AGE)
		var shirt: int = _next_free_number(used_numbers, rng)
		used_numbers.append(shirt)

		var data: PlayerData = PlayerData.make_default(full_name, shirt, role)
		data.nationality = club.squad[0].nationality if not club.squad.is_empty() else "Norwegian"
		data.date_of_birth = CareerDate.make(
			today.year - age, rng.randi_range(1, 12), rng.randi_range(1, 28)
		).to_iso()
		var prim_lang: String = NationDatabase.get_primary_language_for_nation(data.nationality)
		data.spoken_languages = [
			{"language": prim_lang, "proficiency": 1.0, "level": "Native"}
		]

		# Youth arrive deliberately raw. The interesting number is the hidden
		# ceiling, not what they can do today.
		_apply_youth_baseline(data, quality_bias, rng)

		data.wage_weekly = rng.randi_range(400, 1400)
		data.contract_years = 3
		data.squad_status = "Prospect"
		data.morale = 0.80
		data.form = 6.5
		data.player_reputation = 0.05
		data.market_value = data.calculate_market_value()
		out.append(data)

	return out


static func _next_free_number(used: Array[int], rng: RandomNumberGenerator) -> int:
	for _attempt: int in range(40):
		var n: int = rng.randi_range(20, 60)
		if not used.has(n):
			return n
	# Fall back to the first genuinely free number rather than colliding.
	for n2: int in range(20, 100):
		if not used.has(n2):
			return n2
	return 99


## Youth start well below first-team level across the board, with the spread
## driven by the academy's quality bias.
static func _apply_youth_baseline(data: PlayerData, quality_bias: float, rng: RandomNumberGenerator) -> void:
	var tier: float = clampf(quality_bias + rng.randf_range(-0.25, 0.25), 0.05, 1.2)

	data.top_speed = clampf(178.0 + tier * 32.0 + rng.randf_range(-10.0, 10.0), 160.0, 250.0)
	data.stamina_max = clampf(72.0 + tier * 22.0 + rng.randf_range(-6.0, 6.0), 60.0, 120.0)
	data.mass = clampf(64.0 + rng.randf_range(0.0, 22.0), 58.0, 96.0)
	data.vision = clampf(0.30 + tier * 0.28 + rng.randf_range(-0.08, 0.08), 0.10, 0.85)
	data.composure = clampf(0.25 + tier * 0.25 + rng.randf_range(-0.08, 0.08), 0.10, 0.85)
	data.close_control = clampf(0.32 + tier * 0.30 + rng.randf_range(-0.08, 0.08), 0.10, 0.88)
	data.aggression = clampf(0.35 + rng.randf_range(0.0, 0.45), 0.10, 0.95)
	data.reflexes = clampf(0.30 + tier * 0.35 + rng.randf_range(-0.10, 0.10), 0.10, 0.90)

	# Character is rolled independently of ability — the most talented youth
	# in an intake is often not the one with the temperament to use it.
	data.determination = clampf(rng.randf_range(0.25, 0.95), 0.05, 0.99)
	data.professionalism = clampf(rng.randf_range(0.25, 0.95), 0.05, 0.99)
	data.ambition = clampf(rng.randf_range(0.35, 0.95), 0.05, 0.99)
	data.work_rate = clampf(rng.randf_range(0.35, 0.90), 0.05, 0.99)
	data.temperament = clampf(rng.randf_range(0.25, 0.90), 0.05, 0.99)
	data.loyalty = clampf(rng.randf_range(0.40, 0.95), 0.05, 0.99)
	data.leadership = clampf(rng.randf_range(0.10, 0.60), 0.05, 0.99)
	data.adaptability = clampf(rng.randf_range(0.30, 0.90), 0.05, 0.99)

	data.apply_role_defaults(data.position_role)


## The head-of-youth's write-up, shown in the inbox when an intake lands. The
## verdict is deliberately fuzzy — it reports the SCOUT'S read, not the truth.
static func intake_report(
	club_name: String,
	cohort: Array[PlayerData],
	states: Array[PlayerCareerState],
	judging_quality: float
) -> String:
	if cohort.is_empty():
		return "This year's %s youth intake produced nobody worth mentioning." % club_name

	var best_index: int = 0
	var best_potential: int = 0
	for i: int in range(states.size()):
		if states[i].potential_ability > best_potential:
			best_potential = states[i].potential_ability
			best_index = i

	var lines: Array[String] = []
	lines.append("%d young players have come through at %s this year." % [cohort.size(), club_name])

	if best_index < cohort.size():
		var star: PlayerData = cohort[best_index]
		var headroom: int = best_potential - star.calculate_overall_rating()
		var verdict: String = "one to keep an eye on"
		if headroom >= YouthAcademy._wonderkid_headroom() and judging_quality >= 0.55:
			verdict = "the best prospect I have seen here in years"
		elif headroom >= 12:
			verdict = "a genuine first-team prospect in time"
		elif headroom < 6:
			verdict = "honest, but unlikely to trouble the first team"
		lines.append("%s (%s) is %s." % [star.player_name, star.position_role, verdict])

	if judging_quality < 0.45:
		lines.append("Our youth coaching is thin, so treat these assessments with caution.")
	return " ".join(lines)


static func _wonderkid_headroom() -> int:
	return ScoutingNetwork.WONDERKID_MIN_HEADROOM
