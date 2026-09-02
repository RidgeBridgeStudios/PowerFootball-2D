##
## ScoutReport
##
## What this club currently knows about one player it does not own. Scouting is
## modelled as uncertainty reduction, not a boolean unlock: a fresh target's
## attributes are only known as a RANGE, and assigning a scout narrows that
## range over time toward the true value.
##
## knowledge 0.0 -> the UI shows "?" and a wide band.
## knowledge 1.0 -> exact values, and potential is pinned down.
##
## The band half-width is (1 - knowledge) * MAX_UNCERTAINTY, scaled by the
## scout's judging_ability, so a poor scout never fully resolves a player.
##
## Depends on: CareerDate, PlayerData, StaffData.
## Exposes: the fields below, observed_range(), display_value(),
##          potential_range(), advance(), stage_name(), recommendation().
##

class_name ScoutReport
extends Resource

enum Stage { IDENTIFIED = 0, SCOUTED = 1, APPROACHED = 2, BID_MADE = 3, SIGNED = 4, REJECTED = 5 }

const STAGE_NAMES: Array[String] = [
	"Identified", "Scouted", "Approached", "Bid Made", "Signed", "Rejected"
]

## Widest half-width, in overall-rating points, at zero knowledge.
const MAX_UNCERTAINTY: float = 14.0
## Knowledge gained per scouting day at a scout judging_ability of 1.0.
const BASE_DAILY_KNOWLEDGE: float = 0.035
## No scout ever resolves a player past this without them actually signing.
const KNOWLEDGE_CEILING: float = 0.97

@export var target_team_index: int = -1
@export var target_squad_index: int = -1
@export var target_name: String = ""
@export var target_club: String = ""
@export var target_position: String = ""
@export_range(0.0, 1.0) var knowledge: float = 0.0
@export var stage: Stage = Stage.IDENTIFIED
@export var assigned_scout_name: String = ""
@export var first_seen: CareerDate = null
@export var last_updated: CareerDate = null
## Cached true values at report time so the UI does not need the live PlayerData
## to render a band, and so a report can go stale realistically.
@export var true_overall: int = 50
@export var true_potential: int = 60
## Scout's written verdict, regenerated as knowledge crosses thresholds.
@export var verdict: String = ""
## Deterministic per-report bias so a band does not shimmer frame to frame.
## Range -1..1, multiplied by the current half-width.
@export_range(-1.0, 1.0) var estimate_bias: float = 0.0


static func make(
	p_team_index: int,
	p_squad_index: int,
	p_name: String,
	p_club: String,
	p_position: String,
	p_overall: int,
	p_potential: int,
	today: CareerDate,
	bias: float
) -> ScoutReport:
	var r := ScoutReport.new()
	r.target_team_index = p_team_index
	r.target_squad_index = p_squad_index
	r.target_name = p_name
	r.target_club = p_club
	r.target_position = p_position
	r.true_overall = p_overall
	r.true_potential = p_potential
	r.first_seen = today.copy() if today != null else null
	r.last_updated = today.copy() if today != null else null
	r.estimate_bias = clampf(bias, -1.0, 1.0)
	return r


func target_key() -> int:
	return target_team_index * 1000 + target_squad_index


## Half-width of the uncertainty band at the current knowledge level.
func uncertainty() -> float:
	return MAX_UNCERTAINTY * (1.0 - clampf(knowledge, 0.0, 1.0))


## The [low, high] band this club believes the player's overall sits in.
## Centred on the true value plus a fixed per-report bias, so two clubs
## scouting the same player can disagree.
func observed_range() -> Vector2i:
	var half: float = uncertainty()
	var centre: float = float(true_overall) + estimate_bias * half * 0.5
	return Vector2i(
		int(round(clampf(centre - half, 1.0, 99.0))),
		int(round(clampf(centre + half, 1.0, 99.0)))
	)


func potential_range() -> Vector2i:
	# Potential is inherently harder to read than current ability: the band
	# stays 1.6x wider at any knowledge level, and never fully closes.
	var half: float = uncertainty() * 1.6 + 2.0
	var centre: float = float(true_potential) + estimate_bias * half * 0.5
	return Vector2i(
		int(round(clampf(centre - half, 1.0, 99.0))),
		int(round(clampf(centre + half, 1.0, 99.0)))
	)


## What the squad/transfer UI prints for the overall column.
func display_value() -> String:
	if knowledge >= KNOWLEDGE_CEILING:
		return str(true_overall)
	if knowledge < 0.12:
		return "?"
	var band: Vector2i = observed_range()
	if band.x == band.y:
		return str(band.x)
	return "%d-%d" % [band.x, band.y]


func display_potential() -> String:
	if knowledge < 0.2:
		return "?"
	var band: Vector2i = potential_range()
	return "%d-%d" % [band.x, band.y]


## One day of scouting attention. judging_ability comes from the assigned
## scout's StaffData; a report with no scout assigned does not advance.
func advance(judging_ability: float, today: CareerDate) -> void:
	if assigned_scout_name == "":
		return
	var gain: float = BASE_DAILY_KNOWLEDGE * clampf(judging_ability, 0.1, 1.0)
	knowledge = clampf(knowledge + gain, 0.0, KNOWLEDGE_CEILING)
	last_updated = today.copy() if today != null else last_updated
	if stage == Stage.IDENTIFIED and knowledge >= 0.5:
		stage = Stage.SCOUTED
	_refresh_verdict()


func _refresh_verdict() -> void:
	var band: Vector2i = observed_range()
	var mid: float = float(band.x + band.y) * 0.5
	var confidence: String = "a rough first look"
	if knowledge >= 0.85:
		confidence = "an exhaustive assessment"
	elif knowledge >= 0.55:
		confidence = "a solid body of work"
	elif knowledge >= 0.3:
		confidence = "a handful of viewings"

	var judgement: String = "squad depth at best"
	if mid >= 78.0:
		judgement = "a genuine difference-maker"
	elif mid >= 70.0:
		judgement = "a clear first-team upgrade"
	elif mid >= 62.0:
		judgement = "a useful rotation option"

	var upside: String = ""
	var pot: Vector2i = potential_range()
	if float(pot.y) - mid >= 10.0:
		upside = " There is real room to grow here."
	verdict = "On %s, we rate %s as %s.%s" % [confidence, target_name, judgement, upside]


func stage_name() -> String:
	return STAGE_NAMES[clampi(int(stage), 0, STAGE_NAMES.size() - 1)]


## Whether the club knows enough to responsibly bid. Bidding blind is allowed
## but the negotiation AI punishes it via a worse valuation read.
func is_bid_ready() -> bool:
	return knowledge >= 0.45
