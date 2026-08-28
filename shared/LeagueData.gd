##
## LeagueData
##
## Pure data container for a set of teams. Saveable as a .tres resource. This is
## the top-level shape DataLoader loads at startup, either from a user-supplied
## JSON file or from the built-in placeholder league.
##
## Depends on: TeamData.
## Exposes: the fields below.
##

class_name LeagueData
extends Resource

@export var league_name: String = ""
@export var teams: Array[TeamData] = []
