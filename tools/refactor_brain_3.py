
import re

with open("entities/player/PlayerBrain.gd", "r") as f:
    content = f.read()

old_pass = """		# Hot path: bare float, allocates nothing (see PassUtilityScorer docs).
		var score: float
		if player != null and player.role_config != null:
			score = PassUtilityScorer.score_pass(
				distance,
				facing_dot,
				forward_dot,
				min_opp_dist,
				effective_pressure,
				player.role_config.pass_weight_distance,
				player.role_config.pass_weight_angle,
				player.role_config.pass_weight_pressure,
				player.role_config.pass_weight_advancement
			)
		else:
			score = PassUtilityScorer.score_pass(
				distance, facing_dot, forward_dot, min_opp_dist, effective_pressure)

		if score > best_score:
			best_score = score
			best_target = candidate"""

new_pass = """		# Hot path: bare float, allocates nothing (see PassUtilityScorer docs).
		var score: float
		if player != null and player.role_config != null:
			score = PassUtilityScorer.score_pass(
				distance,
				facing_dot,
				forward_dot,
				min_opp_dist,
				effective_pressure,
				player.role_config.pass_weight_distance,
				player.role_config.pass_weight_angle,
				player.role_config.pass_weight_pressure,
				player.role_config.pass_weight_advancement
			)
		else:
			score = PassUtilityScorer.score_pass(
				distance, facing_dot, forward_dot, min_opp_dist, effective_pressure)

		var t_ij: float = 1.0
		if trust_sys != null:
			t_ij = trust_sys.get_trust(TrustSystem.player_key(candidate))
		var form_multiplier: float = 1.0
		var c_mood: MoodSystem = candidate.get_mood()
		if c_mood != null:
			if c_mood.current_tier == MoodSystem.Tier.SLUMP:
				form_multiplier = 0.75
			elif c_mood.current_tier == MoodSystem.Tier.STREAK:
				form_multiplier = 1.25
		
		score = score * t_ij * form_multiplier
		
		# Through-ball logic
		var p_recv: Vector2 = candidate_pos
		var v_recv: Vector2 = candidate.velocity
		var t_intercept: float = UtilityMath.solve_pass_intercept(ball_pos, p_recv, v_recv, 520.0, 1.5)
		var t_defender: float = 999.0
		var nearest_def_pos: Vector2 = Vector2.ZERO
		for j: int in range(MatchWorldModel.TOTAL_PLAYERS):
			if world.player_teams[j] != player.team and world.player_teams[j] != -1:
				var d_pos: Vector2 = world.player_positions[j]
				var d_vel: Vector2 = world.player_velocities[j]
				var td: float = UtilityMath.solve_pass_intercept(ball_pos, d_pos, d_vel, 520.0, 1.5)
				if td < t_defender:
					t_defender = td
					nearest_def_pos = d_pos
		if t_intercept < t_defender - 0.35:
			# Is behind defensive line?
			var def_x: float = world.defensive_line_x[1 - player.team]
			var is_behind: bool = false
			if _get_attack_sign() > 0.0:
				if p_recv.x > def_x: is_behind = true
			else:
				if p_recv.x < def_x: is_behind = true
			if is_behind:
				score += 5.0

		if score > best_score:
			best_score = score
			best_target = candidate"""

content = content.replace(old_pass, new_pass)

with open("entities/player/PlayerBrain.gd", "w") as f:
    f.write(content)

