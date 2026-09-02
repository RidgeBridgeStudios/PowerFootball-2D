##
## LeagueTableRow
##
## One club's standing in one competition's table. Kept as a Resource rather
## than the inner class ManagerModeHub used, so a table survives serialisation
## with the rest of the career save instead of being rebuilt from metadata.
##
## Depends on: nothing.
## Exposes: the fields below, record(), goal_difference(), form_string(),
##          sort_before().
##

class_name LeagueTableRow
extends Resource

## Most recent results, newest LAST. Capped at FORM_LENGTH.
const FORM_LENGTH: int = 10

@export var team_index: int = 0
@export var team_name: String = ""
@export var played: int = 0
@export var won: int = 0
@export var drawn: int = 0
@export var lost: int = 0
@export var goals_for: int = 0
@export var goals_against: int = 0
@export var points: int = 0
## "W"/"D"/"L" characters, newest last.
@export var form: Array[String] = []


func goal_difference() -> int:
	return goals_for - goals_against


func record(scored: int, conceded: int) -> void:
	played += 1
	goals_for += scored
	goals_against += conceded
	if scored > conceded:
		won += 1
		points += 3
		form.append("W")
	elif scored < conceded:
		lost += 1
		form.append("L")
	else:
		drawn += 1
		points += 1
		form.append("D")
	while form.size() > FORM_LENGTH:
		form.remove_at(0)


## Last five results, newest last, e.g. "WWDLW".
func form_string(length: int = 5) -> String:
	var out: String = ""
	var start: int = maxi(form.size() - length, 0)
	for i: int in range(start, form.size()):
		out += form[i]
	return out


## Points per game across the recent form window — the "are they actually any
## good right now" number the board's trajectory and the AI transfer market
## both read, rather than raw league position.
func form_factor() -> float:
	if form.is_empty():
		return 0.5
	var earned: int = 0
	var window: int = mini(form.size(), FORM_LENGTH)
	var start: int = form.size() - window
	for i: int in range(start, form.size()):
		if form[i] == "W":
			earned += 3
		elif form[i] == "D":
			earned += 1
	return clampf(float(earned) / (float(window) * 3.0), 0.0, 1.0)


## Standard football ordering: points, then goal difference, then goals scored,
## then name. Returns true when `self` should be listed above `other`.
func sort_before(other: LeagueTableRow) -> bool:
	if points != other.points:
		return points > other.points
	var gd: int = goal_difference()
	var other_gd: int = other.goal_difference()
	if gd != other_gd:
		return gd > other_gd
	if goals_for != other.goals_for:
		return goals_for > other.goals_for
	return team_name < other.team_name


static func make(p_index: int, p_name: String) -> LeagueTableRow:
	var r := LeagueTableRow.new()
	r.team_index = p_index
	r.team_name = p_name
	return r
