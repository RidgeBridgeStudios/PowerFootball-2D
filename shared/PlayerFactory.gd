##
## PlayerFactory
##
## Applies a PlayerData resource onto a spawned HeavyPlayerController. A static
## helper rather than an autoload: it has no state and no lifecycle of its own,
## it is simply the one place that knows how PlayerData fields map onto the
## controller and brain exports.
##
## Depends on: PlayerData, HeavyPlayerController, PlayerBrain, MoodSystem,
##             TrustSystem, DataLoader, TeamData, ManagerLoader, ManagerData.
## Exposes: apply(player, data, anchor)
##

class_name PlayerFactory
extends RefCounted


static func apply(player: HeavyPlayerController, data: PlayerData, anchor: Vector2) -> void:
	if data == null:
		push_warning("PlayerFactory.apply: no PlayerData given for %s, leaving Inspector values in place." % player.name)
		return

	player.player_mass = data.mass
	player.top_speed = data.top_speed
	player.acceleration_time = data.acceleration_time
	player.friction_time = data.friction_time
	player.turning_penalty_factor = data.turning_penalty
	player.sprint_multiplier = data.sprint_multiplier
	player.stamina_max = data.stamina_max
	player.stamina_drain_rate = data.stamina_drain
	player.stamina_recover_rate = data.stamina_recover

	# The exported values above are inert until the acceleration/friction
	# constants are recomputed from them — see HeavyPlayerController's own
	# warning on _recalculate_movement_curve().
	player._recalculate_movement_curve()
	player.stamina = player.stamina_max

	if player.brain != null:
		player.brain.vision_attribute = data.vision
		player.brain.composure_attribute = data.composure
		player.brain.aggression_attribute = data.aggression
		player.brain.formation_ball_weight = data.formation_ball_weight
		player.brain.formation_anchor = anchor

	player.set_meta(&"player_data", data)

	# Attach or reset the mood system. One MoodSystem child per controller — if
	# one already exists from a previous match, reset it rather than duplicating.
	var mood: MoodSystem = player.get_node_or_null("MoodSystem") as MoodSystem
	if mood == null:
		mood = MoodSystem.new()
		mood.name = "MoodSystem"
		player.add_child(mood)
	else:
		mood.reset()

	# Attach or reset the trust system the same way — one TrustSystem child per
	# controller, holding this player's own trust-in-teammate memory.
	var trust: TrustSystem = player.get_node_or_null("TrustSystem") as TrustSystem
	if trust == null:
		trust = TrustSystem.new()
		trust.name = "TrustSystem"
		player.add_child(trust)
	else:
		trust.reset()

	# Manager coaching bonus — prized_attribute gives a small lift to every
	# player on the squad. +0.05, clamped to 1.0. This is intentionally small:
	# a coaching edge, not a talent rewrite.
	var team_name: String = ""
	if DataLoader.league != null:
		var team_data: TeamData = DataLoader.get_match_team(player.team)
		if team_data != null:
			team_name = team_data.team_name
	var manager: ManagerData = ManagerLoader.get_manager_for_team(team_name)
	if manager != null and player.brain != null:
		match manager.prized_attribute:
			"vision":
				player.brain.vision_attribute = minf(
					player.brain.vision_attribute + 0.05, 1.0)
			"composure":
				player.brain.composure_attribute = minf(
					player.brain.composure_attribute + 0.05, 1.0)
			"aggression":
				player.brain.aggression_attribute = minf(
					player.brain.aggression_attribute + 0.05, 1.0)
