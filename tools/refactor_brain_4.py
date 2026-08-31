
import re

with open("entities/player/PlayerBrain.gd", "r") as f:
    content = f.read()

# Sacchi force
old_intent = "var raw_intent: Vector2 = (seek_force + sep_force + spring_force + assist_force + line_lateral_force).limit_length(1.0)"
new_intent = """	var sacchi_force: Vector2 = Vector2.ZERO
	if role == Role.OUTFIELD_DEFENDER or role == Role.OUTFIELD_MIDFIELDER or role == Role.OUTFIELD_ATTACKER:
		var world: MatchWorldModel = MatchWorldModel.instance
		if world != null:
			var com_x: float = world.team_com_x[player.team]
			var att_x: float = world.team_att_x[player.team]
			var def_x: float = world.team_def_x[player.team]
			var L_team: float = absf(att_x - def_x)
			if L_team > 340.0:
				var K_sacchi: float = 0.0025
				var p_x: float = player.global_position.x
				var f_mag: float = -K_sacchi * ((L_team - 340.0) * (L_team - 340.0)) * signf(p_x - com_x)
				# 0.25 scale for 10px stretch, limit max to 1.0
				f_mag = clampf(f_mag / 100.0, -1.0, 1.0)
				sacchi_force = Vector2(f_mag, 0.0)

	var raw_intent: Vector2 = (seek_force + sep_force + spring_force + assist_force + line_lateral_force + sacchi_force).limit_length(1.0)"""

content = content.replace(old_intent, new_intent)

with open("entities/player/PlayerBrain.gd", "w") as f:
    f.write(content)

