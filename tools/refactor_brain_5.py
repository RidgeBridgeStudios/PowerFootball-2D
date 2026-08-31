
import re

with open("entities/player/PlayerBrain.gd", "r") as f:
    content = f.read()

old_eval = """	# Fallback utility floor: if the ball carrier has zero viable offensive options,
	# force a desperation clearance rather than freezing in possession.
	if ctx.is_possessor:
		var max_offensive: float = maxf(s_pass, maxf(s_dribble, s_shoot))
		if max_offensive <= 0.05:
			best_action = &"PanicClear"
			best_score = 1.0

	return best_action"""

new_eval = """	if ctx.is_possessor:
		var world: MatchWorldModel = MatchWorldModel.instance
		var b_pos: Vector2 = player.global_position
		var opp_goal: Vector2 = pitch_boundary.get_goal_centre(1 - player.team)
		var c_x: int = clampi(int((b_pos.x + 640.0) / 106.6666), 0, 11)
		var c_y: int = clampi(int((b_pos.y + 360.0) / 90.0), 0, 7)
		var is_zone14: bool = world.is_zone_14(c_x, c_y, player.team)
		var b_threat: int = world.get_bresenham_threat(b_pos, opp_goal, player.team)
		
		# 1. SHOOT
		if is_zone14 and b_threat < 200:
			return &"AttemptShoot"
		
		# 2. THROUGH-BALL & 3. OPEN RETAIN PASS
		# Evaluated in _find_best_pass_target which returns a score.
		if s_pass > 0.5:
			return &"Pass"
			
		# 4. DRIBBLE INTO SPACE
		var best_adj_threat: int = 9999
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx: int = c_x + dx
				var ny: int = c_y + dy
				if nx >= 0 and nx < 12 and ny >= 0 and ny < 8:
					var idx: int = ny * 12 + nx
					var threat: int = world.grid_away[idx] if player.team == 0 else world.grid_home[idx]
					if threat < best_adj_threat:
						best_adj_threat = threat
		if best_adj_threat < 50:
			return &"AttemptDribble"
			
		# 5. DESPERATION CLEAR
		if ctx.pressure > 0.85:
			return &"PanicClear"
			
		# If none trigger, use best scored action (retain)
		var max_offensive: float = maxf(s_pass, maxf(s_dribble, s_shoot))
		if max_offensive <= 0.05:
			return &"PanicClear"
			
	return best_action"""

content = content.replace(old_eval, new_eval)

with open("entities/player/PlayerBrain.gd", "w") as f:
    f.write(content)

