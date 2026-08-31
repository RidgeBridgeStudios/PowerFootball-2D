
import re

with open("autoloads/MatchWorldModel.gd", "r") as f:
    content = f.read()

# Add _turnover_predicted
content = re.sub(
    r"var possessor_index: int = NO_INDEX\n",
    "var possessor_index: int = NO_INDEX\nvar _turnover_predicted: bool = false\n",
    content
)

# Add logic in _physics_process
turnover_logic = """	possessor_index = _resolve_possessor_index()

	# Anticipatory Turnover
	if ball_node != null and is_instance_valid(ball_node) and possessor_index != NO_INDEX and ball_node.possessor == null:
		var poss_team: int = player_teams[possessor_index]
		var b_vel: Vector2 = ball_node.velocity
		if b_vel.length() > 50.0:
			var best_tti: float = 999.0
			var best_team: int = -1
			for i: int in range(TOTAL_PLAYERS):
				if player_teams[i] != -1:
					var p_pos: Vector2 = p_pos_x[i] * Vector2.RIGHT + p_pos_y[i] * Vector2.DOWN
					# Approximation since we cannot use UtilityMath easily without importing or calling it statically
					var dist: float = p_pos.distance_to(ball_node.global_position)
					# Assuming speed 350.0 max
					var tti: float = dist / 350.0
					if tti < best_tti:
						best_tti = tti
						best_team = player_teams[i]
			
			if best_team != poss_team and best_tti <= 0.3:
				if not _turnover_predicted:
					_turnover_predicted = true
					GameEvents.anticipatory_turnover_predicted.emit(best_team)
			elif best_team == poss_team:
				_turnover_predicted = false
	elif ball_node != null and ball_node.possessor != null:
		_turnover_predicted = false"""

content = content.replace("	possessor_index = _resolve_possessor_index()", turnover_logic)

with open("autoloads/MatchWorldModel.gd", "w") as f:
    f.write(content)

