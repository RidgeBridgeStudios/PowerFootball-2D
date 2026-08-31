
import re

with open("entities/player/PlayerBrain.gd", "r") as f:
    content = f.read()

old_outfield = """		Role.OUTFIELD_DEFENDER:
			if has_ball:
				var safe_pos: Vector2 = dynamic_anchor
				safe_pos = safe_pos.lerp(ball_pos, 0.08)
				return _evaluate_off_ball_target(safe_pos)
			else:
				if current_duty == DefensiveDuty.COVER_SHADOW:
					var world_press: MatchWorldModel = MatchWorldModel.instance
					if world_press != null and is_instance_valid(world_press.press_trigger_carrier):
						return clamp_to_playable_area(_cover_shadow_target(world_press.press_trigger_carrier))

				var line_anchor: Vector2 = dynamic_anchor
				var world: MatchWorldModel = MatchWorldModel.instance
				if world != null:
					line_anchor.x = lerpf(
						line_anchor.x, world.defensive_line_x[player.team], DEFENSIVE_LINE_DEPTH_WEIGHT)

				var threat: HeavyPlayerController = _find_nearest_threatening_opponent()
				if threat != null:
					var threat_pos: Vector2 = threat.global_position.lerp(line_anchor, 0.45)
					return clamp_to_playable_area(threat_pos)
				return _evaluate_off_ball_target(line_anchor)"""

new_outfield = """		Role.OUTFIELD_DEFENDER:
			if has_ball:
				var safe_pos: Vector2 = dynamic_anchor
				if absf(formation_anchor.y) > 120.0:
					var is_rb: bool = formation_anchor.y > 0.0
					var is_lb: bool = formation_anchor.y < 0.0
					var opposite_advanced: bool = false
					var world: MatchWorldModel = MatchWorldModel.instance
					if world != null:
						for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
							if world.player_teams[i] == player.team and world.player_nodes[i] != player:
								var px: float = world.p_pos_x[i]
								var py: float = world.p_pos_y[i]
								var advanced_x: float = px * _get_attack_sign()
								if advanced_x > 0.0 and absf(py) > 180.0:
									if (is_lb and py > 0.0) or (is_rb and py < 0.0):
										opposite_advanced = true
										break
					if opposite_advanced:
						var clamped_y: float = clampf(safe_pos.y, -180.0, 180.0)
						safe_pos = Vector2(safe_pos.x, clamped_y)
						return clamp_to_playable_area(safe_pos)
					safe_pos = safe_pos.lerp(ball_pos, 0.08)
					return _evaluate_off_ball_target(safe_pos)
				else:
					safe_pos = safe_pos.lerp(ball_pos, 0.08)
					var target: Vector2 = _evaluate_off_ball_target(safe_pos)
					if pitch_boundary != null:
						var max_adv: float = pitch_boundary.get_centre_spot().x - 60.0 * _get_attack_sign()
						if _get_attack_sign() > 0.0:
							target.x = minf(target.x, max_adv)
						else:
							target.x = maxf(target.x, max_adv)
					return clamp_to_playable_area(target)
			else:
				var world: MatchWorldModel = MatchWorldModel.instance
				if current_duty == DefensiveDuty.COVER_SUPPORT:
					if world != null and is_instance_valid(world.press_trigger_carrier):
						var carrier_pos: Vector2 = world.press_trigger_carrier.global_position
						var opp_goal: Vector2 = pitch_boundary.get_goal_centre(player.team)
						var btg_axis: Vector2 = (opp_goal - carrier_pos).normalized()
						var sup_pos: Vector2 = carrier_pos + btg_axis * 50.0
						return clamp_to_playable_area(sup_pos)
				if current_duty == DefensiveDuty.COVER_SHADOW:
					if world != null and is_instance_valid(world.press_trigger_carrier):
						var cx: int = clampi(int((player.global_position.x + MatchWorldModel.TACTICAL_OFFSET_X) / MatchWorldModel.TACTICAL_CELL_W), 0, MatchWorldModel.TACTICAL_GRID_WIDTH - 1)
						var cy: int = clampi(int((player.global_position.y + MatchWorldModel.TACTICAL_OFFSET_Y) / MatchWorldModel.TACTICAL_CELL_H), 0, MatchWorldModel.TACTICAL_GRID_HEIGHT - 1)
						var best_threat: int = -1
						var best_cell: Vector2 = player.global_position
						for dy: int in range(-1, 2):
							for dx: int in range(-1, 2):
								var nx: int = cx + dx
								var ny: int = cy + dy
								if nx >= 0 and nx < MatchWorldModel.TACTICAL_GRID_WIDTH and ny >= 0 and ny < MatchWorldModel.TACTICAL_GRID_HEIGHT:
									var idx: int = ny * MatchWorldModel.TACTICAL_GRID_WIDTH + nx
									var threat: int = world.grid_away[idx] if player.team == 0 else world.grid_home[idx]
									if threat > best_threat:
										best_threat = threat
										best_cell = Vector2(float(nx) * MatchWorldModel.TACTICAL_CELL_W - MatchWorldModel.TACTICAL_OFFSET_X + MatchWorldModel.TACTICAL_CELL_W * 0.5, float(ny) * MatchWorldModel.TACTICAL_CELL_H - MatchWorldModel.TACTICAL_OFFSET_Y + MatchWorldModel.TACTICAL_CELL_H * 0.5)
						return clamp_to_playable_area(best_cell)
				
				var line_anchor: Vector2 = dynamic_anchor
				if world != null:
					line_anchor.x = lerpf(line_anchor.x, world.defensive_line_x[player.team], DEFENSIVE_LINE_DEPTH_WEIGHT)

				var threat: HeavyPlayerController = _find_nearest_threatening_opponent()
				if threat != null:
					var threat_pos: Vector2 = threat.global_position.lerp(line_anchor, 0.45)
					return clamp_to_playable_area(threat_pos)
				return _evaluate_off_ball_target(line_anchor)"""

content = content.replace(old_outfield, new_outfield)

with open("entities/player/PlayerBrain.gd", "w") as f:
    f.write(content)

