##
## PlayerData
##
## Pure data container for one player: identity, physical tuning, and brain
## personality. Saveable as a .tres resource so a squad can be authored and
## edited without touching a scene. PlayerFactory is what turns an instance of
## this into a live HeavyPlayerController — this resource never touches a Node.
##
## Depends on: nothing.
## Exposes: the fields below and make_default().
##

class_name PlayerData
extends Resource

## --- Identity ----------------------------------------------------------------

@export var player_name: String = ""
@export var shirt_number: int = 0
## "GK", "CB", "LB", "RB", "DM", "CM", "AM", "LW", "RW", "ST"
@export var position_role: String = ""

## --- Physical identity — maps 1:1 onto HeavyPlayerController exports ---------

@export var mass: float = 75.0
@export var top_speed: float = 210.0
@export var acceleration_time: float = 0.65
@export var friction_time: float = 0.35
@export var turning_penalty: float = 0.75
@export var sprint_multiplier: float = 1.45

## --- Stamina -------------------------------------------------------------------

@export var stamina_max: float = 100.0
@export var stamina_drain: float = 18.0
@export var stamina_recover: float = 9.0

## --- Brain personality — maps 1:1 onto PlayerBrain exports --------------------

@export_range(0.0, 1.0) var vision: float = 0.75
@export_range(0.0, 1.0) var composure: float = 0.60
@export_range(0.0, 1.0) var aggression: float = 0.80
@export_range(0.0, 1.0) var formation_ball_weight: float = 0.35

## --- Live form and career stats — read by the pre-game screen and pause menu ---

## Per-match rolling form (0.0 - 10.0). Persists across matches; decays
## slightly each match a player does not feature. Default 6.5 = neutral form.
@export var form: float = 6.5

## Career goals and assists — incremented by PitchScene after each match.
@export var career_goals: int = 0
@export var career_assists: int = 0

## Match rating assigned at end of the last match (0.0 - 10.0). 0.0 = did not play.
@export var last_match_rating: float = 0.0

## Whether this player is marked as unavailable (injured/suspended) for
## the next match. The pre-game screen reads this and greys out the card.
@export var is_unavailable: bool = false


static func make_default(player_name: String, shirt_number: int, position_role: String) -> PlayerData:
	var d := PlayerData.new()
	d.player_name = player_name
	d.shirt_number = shirt_number
	d.position_role = position_role
	return d
