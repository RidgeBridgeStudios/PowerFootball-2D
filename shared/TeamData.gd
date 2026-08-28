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
