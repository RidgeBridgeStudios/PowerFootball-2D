##
## PlayerCareerState
##
## Everything about one player that only exists between matches. PlayerData
## stays the authored/match-facing resource (attributes, physics tuning, form,
## morale); this holds the career layer's own bookkeeping so the career can be
## deep without bloating the resource the match engine binds to 22 times.
##
## Keyed in CareerSaveData by the synthesized team*1000+squad_index id that
## MatchStatsTracker and QuickSimEngine already use (there is no
## PlayerData.player_id, and squad_index is the only stable identity).
##
## Depends on: ContractData, RelationshipData, CareerDate, PlayerData.
## Exposes: the fields below, make_for(), condition_label(), is_available(),
##          tick_recovery(), apply_training_load(), record_appearance(),
##          relationship_with(), potential_remaining().
##

class_name PlayerCareerState
extends Resource

enum InjuryKind { NONE = 0, KNOCK = 1, STRAIN = 2, MUSCLE_TEAR = 3, LIGAMENT = 4, FRACTURE = 5 }

const INJURY_NAMES: Array[String] = [
	"Fit", "Knock", "Strain", "Muscle Tear", "Ligament Damage", "Fracture"
]
## Typical lay-off in days for each kind, before durability modifiers.
const INJURY_BASE_DAYS: Array[int] = [0, 4, 12, 35, 90, 130]

## PES Master League-style development archetype. Assigned once at career
## start / youth intake and read by PlayerDevelopmentEngine to shape both the
## growth curve and the post-peak decline curve — see growth_multiplier()
## and apply_seasonal_ageing() for what each archetype actually does.
enum DevelopmentArchetype { NORMAL = 0, EARLY_PEAK = 1, LATE_BLOOMER = 2, EVERGREEN = 3 }

const ARCHETYPE_NAMES: Array[String] = [
	"Normal", "Early Peak", "Late Bloomer", "Evergreen"
]

## Matchday condition arrow (PES-style short-term momentum), distinct from the
## long-run `condition`/`sharpness` fatigue fields above. Read at kickoff by
## MoraleEngine.apply_to_match_player() to nudge that match's physical
## attributes, and shown on the squad screen next to each name.
enum ConditionArrow { ICE_COLD = 0, FALLING = 1, STEADY = 2, RISING = 3, RED_HOT = 4 }

const ARROW_NAMES: Array[String] = [
	"Ice Cold", "Falling", "Steady", "Rising", "Red Hot"
]
const ARROW_GLYPHS: Array[String] = ["▼▼", "▼", "—", "▲", "▲▲"]
## Per-arrow attribute multiplier applied to that match's top_speed/stamina,
## and inversely to acceleration_time. Asymmetric on purpose, matching the
## rest of the career layer's convention that bad news bites harder than good
## news helps (see MoraleEngine's MORALE_TO_MOOD_DOWN/UP split).
const ARROW_ATTRIBUTE_MULTIPLIER: Array[float] = [0.85, 0.92, 1.0, 1.05, 1.12]

## How many of the most recent match ratings feed the condition arrow.
const FORM_WINDOW: int = 5

## Manager relationship keys live OUTSIDE the 0-21999 player_key space (§2.3)
const MANAGER_RELATIONSHIP_KEY_BASE: int = RelationshipData.MANAGER_RELATIONSHIP_KEY_BASE

static func manager_relationship_key(league_team_index: int) -> int:
	return RelationshipData.manager_relationship_key(league_team_index)

@export var player_key: int = -1
@export var display_name: String = ""
@export var squad_index: int = -1
@export var team_index: int = -1

## --- Physical state -----------------------------------------------------------
## 0.0 = exhausted, 1.0 = fully fresh. Drains with minutes and training load.
@export_range(0.0, 1.0) var condition: float = 1.0
## Match sharpness — separate from condition. A fit player who has not played
## is fresh but blunt.
@export_range(0.0, 1.0) var sharpness: float = 0.6
@export var injury: InjuryKind = InjuryKind.NONE
@export var injury_days_remaining: int = 0
@export var injury_return_date: CareerDate = null
## Career-long injury susceptibility, raised by each serious injury.
@export_range(0.0, 1.0) var injury_proneness: float = 0.25

## --- Development ---------------------------------------------------------------
## Hidden ceiling this player can reach, on the same 1-99 scale as
## PlayerData.calculate_overall_rating(). Never shown directly — the scouting
## layer only ever exposes a range around it.
@export var potential_ability: int = 65
## Accumulated development progress toward the next overall point.
@export var development_xp: float = 0.0
@export var is_youth_player: bool = false
@export var archetype: DevelopmentArchetype = DevelopmentArchetype.NORMAL
## Most recent match ratings, oldest first, capped at FORM_WINDOW entries.
## Drives condition_arrow() — separate from the season-long `average_rating`.
@export var recent_ratings: Array[float] = []

## --- Season record -------------------------------------------------------------
@export var appearances: int = 0
@export var minutes_played: int = 0
@export var goals_this_season: int = 0
@export var assists_this_season: int = 0
@export var average_rating: float = 0.0
@export var yellow_cards_season: int = 0
@export var red_cards_season: int = 0
## Matches still to serve from an accumulated-card or red-card ban.
@export var suspension_matches: int = 0

## --- Career layer social state --------------------------------------------------
@export var contract: ContractData = null
## How much this player trusts the MANAGER specifically (0..1).
@export_range(0.0, 1.0) var manager_trust: float = 0.5
## player_key -> RelationshipData toward that teammate.
@export var relationships: Dictionary = {}
## Unresolved grievances, e.g. &"playing_time", &"transfer_request".
@export var grievances: Array[StringName] = []
@export var transfer_listed: bool = false
@export var loan_listed: bool = false
@export var in_u23_squad: bool = false
@export var wants_new_contract: bool = false
@export var has_requested_transfer: bool = false
## Playing-time promise the manager made, and when it must be honoured by.
@export var promised_status: int = -1
@export var promise_review_date: CareerDate = null


static func make_for(
	player: PlayerData,
	p_team_index: int,
	p_squad_index: int,
	p_potential: int,
	today: CareerDate,
	rng: RandomNumberGenerator = null
) -> PlayerCareerState:
	var s := PlayerCareerState.new()
	s.team_index = p_team_index
	s.squad_index = p_squad_index
	s.player_key = p_team_index * 1000 + p_squad_index
	s.display_name = player.player_name
	s.potential_ability = p_potential
	s.contract = ContractData.make_default(
		"", player.wage_weekly, maxi(player.contract_years, 1), today
	)
	s.contract.promised_status = ContractData.status_from_name(player.squad_status)
	# A professional starts more durable than a careless one.
	s.injury_proneness = clampf(0.38 - player.professionalism * 0.20, 0.05, 0.6)
	if player.has_trait(4096): # IronMan
		s.injury_proneness = clampf(s.injury_proneness * 0.5, 0.03, 0.4)
	s.archetype = _roll_archetype(player, rng)
	return s


## Weighted archetype roll. IronMan players skew toward EVERGREEN (durability
## reads as longevity), and high-ambition/high-determination characters skew
## toward LATE_BLOOMER (their headroom keeps paying off later) — otherwise the
## four archetypes are close to evenly spread. Falls back to a name-hash pick
## when no rng is supplied, so a caller that cannot spare one still gets a
## deterministic, non-uniform result rather than always NORMAL.
static func _roll_archetype(player: PlayerData, rng: RandomNumberGenerator) -> DevelopmentArchetype:
	var roll: float
	if rng != null:
		roll = rng.randf()
	else:
		roll = float(hash(player.player_name) % 1000) / 1000.0
	if player.has_trait(4096) and roll < 0.40: # IronMan
		return DevelopmentArchetype.EVERGREEN
	var late_bloom_bias: float = (player.ambition + player.determination) * 0.5
	if late_bloom_bias >= 0.75 and roll < 0.30:
		return DevelopmentArchetype.LATE_BLOOMER
	if roll < 0.28:
		return DevelopmentArchetype.EARLY_PEAK
	if roll < 0.50:
		return DevelopmentArchetype.LATE_BLOOMER
	if roll < 0.68:
		return DevelopmentArchetype.EVERGREEN
	return DevelopmentArchetype.NORMAL


func archetype_label() -> String:
	return ARCHETYPE_NAMES[clampi(int(archetype), 0, ARCHETYPE_NAMES.size() - 1)]


func condition_label() -> String:
	if condition >= 0.92:
		return "Peak"
	if condition >= 0.78:
		return "Fit"
	if condition >= 0.62:
		return "Tired"
	if condition >= 0.42:
		return "Jaded"
	return "Exhausted"


func injury_name() -> String:
	return INJURY_NAMES[clampi(int(injury), 0, INJURY_NAMES.size() - 1)]


func is_injured() -> bool:
	return injury != InjuryKind.NONE and injury_days_remaining > 0


func is_suspended() -> bool:
	return suspension_matches > 0


func is_available() -> bool:
	return not is_injured() and not is_suspended()


func availability_label() -> String:
	if is_injured():
		return "%s — %d days" % [injury_name(), injury_days_remaining]
	if is_suspended():
		return "Suspended — %d match%s" % [suspension_matches, "" if suspension_matches == 1 else "es"]
	return "Available"


## One day of rest/recovery. physio_quality shortens lay-offs; condition
## recovers faster the further below full it has fallen. facility_mult is the
## club's medical facility tier multiplier (BoardState.facility_multiplier()
## of medical_facility) — a state-of-the-art medical centre on top of a good
## physio compounds, exactly like training_facilities already does for
## PlayerDevelopmentEngine.apply_daily_training().
func tick_recovery(physio_quality: float, rest_factor: float, facility_mult: float = 1.0) -> bool:
	var healed: bool = false
	if is_injured():
		# A good physio can shave up to ~40% off a lay-off; a top-tier medical
		# facility adds further on top.
		var heal_rate: float = (1.0 + clampf(physio_quality, 0.0, 1.0) * 0.65) * clampf(facility_mult, 0.5, 1.5)
		injury_days_remaining = maxi(injury_days_remaining - int(round(heal_rate)), 0)
		if injury_days_remaining <= 0:
			injury = InjuryKind.NONE
			injury_return_date = null
			# Coming back from injury, a player is fit but badly undercooked.
			condition = 0.72
			sharpness = 0.28
			healed = true
		return healed

	var deficit: float = 1.0 - condition
	condition = clampf(condition + deficit * 0.28 * clampf(rest_factor, 0.0, 1.5) + 0.02, 0.0, 1.0)
	# Sharpness bleeds away without matches, however fresh the legs are.
	sharpness = clampf(sharpness - 0.008, 0.0, 1.0)
	return false


## Applies one training day's physical load.
func apply_training_load(intensity: float) -> void:
	if is_injured():
		return
	condition = clampf(condition - intensity * 0.075, 0.05, 1.0)
	# Training keeps players sharp, but never as sharp as playing.
	sharpness = clampf(sharpness + intensity * 0.020, 0.0, 0.85)


func begin_injury(kind: InjuryKind, today: CareerDate, rng: RandomNumberGenerator) -> void:
	injury = kind
	var base: int = INJURY_BASE_DAYS[clampi(int(kind), 0, INJURY_BASE_DAYS.size() - 1)]
	# +/- 35% variance so two identical injuries do not have identical lay-offs.
	var varied: float = float(base) * rng.randf_range(0.65, 1.35)
	# The injury-prone get longer lay-offs as well as more of them.
	varied *= 1.0 + injury_proneness * 0.5
	injury_days_remaining = maxi(int(round(varied)), 1)
	injury_return_date = today.advanced_by(injury_days_remaining) if today != null else null
	condition = clampf(condition * 0.55, 0.05, 1.0)
	sharpness = clampf(sharpness * 0.5, 0.0, 1.0)
	# Serious injuries leave a player more fragile for good.
	if int(kind) >= int(InjuryKind.MUSCLE_TEAR):
		injury_proneness = clampf(injury_proneness + 0.07, 0.0, 1.0)


func record_appearance(minutes: int, rating: float, scored: int, assisted: int) -> void:
	appearances += 1
	minutes_played += minutes
	goals_this_season += scored
	assists_this_season += assisted
	if rating > 0.0:
		# Running mean across appearances.
		average_rating = ((average_rating * float(appearances - 1)) + rating) / float(appearances)
		record_form_sample(rating)
	var load: float = float(minutes) / 90.0
	condition = clampf(condition - load * 0.30, 0.05, 1.0)
	sharpness = clampf(sharpness + load * 0.16, 0.0, 1.0)


## Pushes one match rating into the short rolling window condition_arrow()
## reads. Kept separate from record_appearance() so a caller with a rating
## but no full appearance (unlikely, but keeps the two concerns apart) can
## still feed the arrow.
func record_form_sample(rating: float) -> void:
	recent_ratings.append(rating)
	while recent_ratings.size() > FORM_WINDOW:
		recent_ratings.remove_at(0)


## PES-style momentum read: recent ratings trending up/down plus current
## sharpness. Distinct from average_rating (season-long) and from morale
## (off-pitch happiness) — this is purely "have they been good lately".
func condition_arrow() -> ConditionArrow:
	if recent_ratings.is_empty():
		return ConditionArrow.STEADY
	var sum: float = 0.0
	for r: float in recent_ratings:
		sum += r
	var avg_recent: float = sum / float(recent_ratings.size())
	var momentum: float = avg_recent - 6.5
	if recent_ratings.size() >= 2:
		# Reward an improving trend within the window, not just a high mean.
		momentum += (recent_ratings[recent_ratings.size() - 1] - recent_ratings[0]) * 0.4
	momentum += (sharpness - 0.6) * 1.5
	if momentum >= 1.4:
		return ConditionArrow.RED_HOT
	if momentum >= 0.5:
		return ConditionArrow.RISING
	if momentum <= -1.4:
		return ConditionArrow.ICE_COLD
	if momentum <= -0.5:
		return ConditionArrow.FALLING
	return ConditionArrow.STEADY


func condition_arrow_label() -> String:
	return ARROW_NAMES[clampi(int(condition_arrow()), 0, ARROW_NAMES.size() - 1)]


func condition_arrow_glyph() -> String:
	return ARROW_GLYPHS[clampi(int(condition_arrow()), 0, ARROW_GLYPHS.size() - 1)]


## Multiplier MoraleEngine.apply_to_match_player() applies to that match's
## top_speed/stamina_max (and inversely to acceleration_time) at kickoff.
func condition_arrow_attribute_multiplier() -> float:
	return ARROW_ATTRIBUTE_MULTIPLIER[clampi(int(condition_arrow()), 0, ARROW_ATTRIBUTE_MULTIPLIER.size() - 1)]


## Share of the team's available minutes this player has actually had.
func minutes_share(team_matches_played: int) -> float:
	if team_matches_played <= 0:
		return 0.0
	return clampf(float(minutes_played) / (float(team_matches_played) * 90.0), 0.0, 1.0)


func relationship_with(other_key: int, ordinal: int) -> RelationshipData:
	var existing: RelationshipData = relationships.get(other_key, null) as RelationshipData
	if existing != null:
		return existing
	var fresh: RelationshipData = RelationshipData.neutral(ordinal)
	if RelationshipData.is_manager_key(other_key):
		fresh.trust = manager_trust
	relationships[other_key] = fresh
	return fresh


## Returns the RelationshipData edge toward the manager of the given team.
func manager_relationship(league_team_index: int, ordinal: int) -> RelationshipData:
	return relationship_with(RelationshipData.manager_relationship_key(league_team_index), ordinal)


## Adjusts trust with the manager, updating both the RelationshipData edge
## and the synchronized manager_trust scalar.
func adjust_manager_trust(delta: float, reason: String, league_team_index: int, ordinal: int) -> void:
	var rel: RelationshipData = manager_relationship(league_team_index, ordinal)
	rel.adjust_trust(delta, reason, ordinal)
	manager_trust = rel.trust


func potential_remaining(current_overall: int) -> int:
	return maxi(potential_ability - current_overall, 0)


func reset_season_record() -> void:
	appearances = 0
	minutes_played = 0
	goals_this_season = 0
	assists_this_season = 0
	average_rating = 0.0
	yellow_cards_season = 0
	red_cards_season = 0
