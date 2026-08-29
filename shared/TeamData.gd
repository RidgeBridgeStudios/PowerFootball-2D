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
@export var squad: Array[PlayerData] = []

## Active formation string for this match, chosen via the pre-game screen or
## the pause menu. Empty string = use the manager's preferred_formation.
@export var formation_override: String = ""

## Substitutions used this match (max 3, enforced by PauseMenu).
@export var substitutions_made: int = 0

## Indices into `squad` for the 11 players currently in the starting lineup.
## Length must always be 11 when set. Populated by TeamManagementData.apply_to_team().
@export var lineup_indices: Array[int] = []
