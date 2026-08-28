##
## PlayerFactory
##
## Applies a PlayerData resource onto a spawned HeavyPlayerController. A static
## helper rather than an autoload: it has no state and no lifecycle of its own,
## it is simply the one place that knows how PlayerData fields map onto the
## controller and brain exports.
##
## Depends on: PlayerData, HeavyPlayerController, PlayerBrain.
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
