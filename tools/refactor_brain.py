
import re

with open("entities/player/PlayerBrain.gd", "r") as f:
    content = f.read()

content = content.replace("COVER_SHADOW,  ##", "COVER_SUPPORT, ##\n\tCOVER_SHADOW,  ##")

def_duty_old = """	var someone_closer: bool = false
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var other: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(other) or other == player:
			continue
		if world.player_teams[i] != player.team:
			continue
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain == null or other_brain.role != Role.OUTFIELD_DEFENDER:
			continue
		var other_dist_sq: float = world.player_positions[i].distance_squared_to(carrier.global_position)
		# Tie-break on player_index so an exact distance tie still resolves to
		# a single presser instead of both defenders claiming the duty.
		if other_dist_sq < my_dist_sq or (is_equal_approx(other_dist_sq, my_dist_sq) and i < player_index):
			someone_closer = true
			break

	if not someone_closer:
		return DefensiveDuty.TRIGGER_PRESS
	if my_dist <= COVER_SHADOW_RADIUS:
		return DefensiveDuty.COVER_SHADOW"""

def_duty_new = """	var closer_count: int = 0
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var other: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(other) or other == player:
			continue
		if world.player_teams[i] != player.team:
			continue
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain == null or other_brain.role != Role.OUTFIELD_DEFENDER:
			continue
		var other_dist_sq: float = world.player_positions[i].distance_squared_to(carrier.global_position)
		if other_dist_sq < my_dist_sq or (is_equal_approx(other_dist_sq, my_dist_sq) and i < player_index):
			closer_count += 1

	var my_dist: float = sqrt(my_dist_sq)
	if closer_count == 0:
		return DefensiveDuty.TRIGGER_PRESS
	elif closer_count == 1 and my_dist <= COVER_SHADOW_RADIUS:
		return DefensiveDuty.COVER_SUPPORT
	elif closer_count == 2 and my_dist <= COVER_SHADOW_RADIUS:
		return DefensiveDuty.COVER_SHADOW"""

content = content.replace(def_duty_old, def_duty_new)

with open("entities/player/PlayerBrain.gd", "w") as f:
    f.write(content)

