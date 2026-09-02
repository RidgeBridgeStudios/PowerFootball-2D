##
## TeamManagementData
##
## Transient (not saved) working copy of a team's lineup for the pre-game
## screen and pause menu. Holds the current 11-man lineup, the bench order,
## the chosen formation, and pending substitutions.
## Call apply_to_team() to push all changes into the live TeamData so
## PitchScene can read them at match start.
##
## Depends on: TeamData, PlayerData, ManagerData.
## Exposes: from_team(), swap(), reshuffle(), apply_to_team().
##

class_name TeamManagementData
extends RefCounted

## The TeamData this management session is editing.
var team: TeamData = null
## Which ManagerData governs this team.
var manager: ManagerData = null

## 11 indices into team.squad representing the current starting XI.
## Ordered: index 0 = GK, 1-4 = defenders (L->R), 5-7 = midfielders (L->R),
## 8-10 = attackers (L->R). The pre-game screen reorders this when the user
## drags a player to a different slot.
var lineup: Array[int] = []

## Remaining squad indices not in lineup - the bench, ordered by position role.
var bench: Array[int] = []

## The chosen formation string (e.g. "4-3-3").
var formation: String = ""

## Substitutions already committed (max 3 per match; only relevant in pause menu).
var substitutions_used: int = 0

## Tactical role overrides per starting XI lineup slot (slot 0..10 -> role string, e.g. "CAM", "CDM").
var role_overrides: Dictionary = {}

## Custom per-slot PlayerRoleConfig instances edited via tactics inspector.
var custom_role_configs: Dictionary = {}

## Lineup slot index of designated team captain.
var captain_slot: int = -1


static func from_team(t: TeamData, m: ManagerData) -> TeamManagementData:
	var d := TeamManagementData.new()
	d.team = t
	d.manager = m
	d.formation = m.preferred_formation if t.formation_override == "" else t.formation_override
	d.substitutions_used = t.substitutions_made
	d.role_overrides = t.role_overrides.duplicate()

	if t.lineup_indices.size() == 11:
		d.lineup = t.lineup_indices.duplicate()
	else:
		# Build a default lineup: first 11 players in the squad.
		d.lineup = []
		for i in range(mini(11, t.squad.size())):
			d.lineup.append(i)

	d.bench = []
	for i in range(t.squad.size()):
		if not d.lineup.has(i):
			d.bench.append(i)

	# Determine captain slot
	if t.captain_index >= 0 and d.lineup.has(t.captain_index):
		d.captain_slot = d.lineup.find(t.captain_index)
	else:
		for slot in range(d.lineup.size()):
			var sq_idx: int = d.lineup[slot]
			if sq_idx >= 0 and sq_idx < t.squad.size() and t.squad[sq_idx].is_captain:
				d.captain_slot = slot
				break
		if d.captain_slot == -1 and not d.lineup.is_empty():
			d.captain_slot = 0

	return d



## Swap a starter (by lineup slot index) with a bench player (by bench slot index).
## Returns false if the swap is invalid (same player, substitutions exhausted in
## a match context, or player is unavailable).
func swap(lineup_slot: int, bench_slot: int, is_in_match: bool) -> bool:
	if is_in_match and substitutions_used >= 3:
		return false
	if lineup_slot < 0 or lineup_slot >= lineup.size():
		return false
	if bench_slot < 0 or bench_slot >= bench.size():
		return false

	var out_idx: int = lineup[lineup_slot]
	var in_idx: int = bench[bench_slot]

	if team.squad[in_idx].is_unavailable:
		return false

	lineup[lineup_slot] = in_idx
	bench[bench_slot] = out_idx

	if is_in_match:
		substitutions_used += 1
	return true


## Move a player between lineup slots (positional reshuffle, not a substitution).
func reshuffle(slot_a: int, slot_b: int) -> bool:
	if slot_a < 0 or slot_a >= lineup.size() or slot_b < 0 or slot_b >= lineup.size():
		return false
	var tmp: int = lineup[slot_a]
	lineup[slot_a] = lineup[slot_b]
	lineup[slot_b] = tmp

	if captain_slot == slot_a:
		captain_slot = slot_b
	elif captain_slot == slot_b:
		captain_slot = slot_a
	return true


## Returns the active tactical role for a lineup slot (role override or formation default).
func get_slot_role(slot: int) -> String:
	if role_overrides.has(slot):
		return str(role_overrides[slot])
	var layout: Array[Dictionary] = FormationLibrary.get_formation(formation)
	if slot >= 0 and slot < layout.size():
		return str(layout[slot].get("role", "CM"))
	return "CM"


## Sets an individual role override for a specific lineup slot.
func set_slot_role(slot: int, role: String) -> void:
	if slot >= 0 and slot < lineup.size():
		role_overrides[slot] = role


## Returns custom PlayerRoleConfig assigned to a slot, if any.
func get_slot_role_config(slot: int) -> PlayerRoleConfig:
	if custom_role_configs.has(slot):
		return custom_role_configs[slot] as PlayerRoleConfig
	return null


## Stores a custom PlayerRoleConfig instance for a slot.
func set_slot_role_config(slot: int, config: PlayerRoleConfig) -> void:
	if slot >= 0 and slot < lineup.size():
		custom_role_configs[slot] = config


## Designates a starting lineup slot as team captain.
func set_captain(slot: int) -> void:
	if slot >= 0 and slot < lineup.size():
		captain_slot = slot
		var cap_squad_idx: int = lineup[slot]
		for i in range(team.squad.size()):
			team.squad[i].is_captain = (i == cap_squad_idx)


## Push the working copy back into the live TeamData.
func apply_to_team() -> void:
	team.lineup_indices = lineup.duplicate()
	team.formation_override = formation
	team.substitutions_made = substitutions_used
	team.role_overrides = role_overrides.duplicate()
	if captain_slot >= 0 and captain_slot < lineup.size():
		team.captain_index = lineup[captain_slot]
		for i in range(team.squad.size()):
			team.squad[i].is_captain = (i == team.captain_index)

