##
## TeamData
##
## Pure data container for one team: name, colour, and the squad of PlayerData
## resources that make it up. Saveable as a .tres resource. No logic — DataLoader
## owns building the default league, PlayerFactory owns applying a squad member
## onto a spawned player.
##
## Depends on: PlayerData.
## Exposes: the fields below.
##

class_name TeamData
extends Resource

@export var team_name: String = ""
@export var team_color: Color = Color.WHITE
@export var secondary_color: Color = Color.WHITE
@export var gk_color: Color = Color(0.12, 0.78, 0.42, 1.0)
@export var squad: Array[PlayerData] = []

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


