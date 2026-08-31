
import re

with open("autoloads/MatchWorldModel.gd", "r") as f:
    content = f.read()

bad_indent = """		if node == null or not is_instance_valid(node):
			continue
				player_positions[i] = node.global_position
		player_velocities[i] = node.velocity"""

good_indent = """		if node == null or not is_instance_valid(node):
			continue
		player_positions[i] = node.global_position
		player_velocities[i] = node.velocity"""

content = content.replace(bad_indent, good_indent)

# Also fix the duplicate def line calc I injected earlier:
bad_calc = """	_update_defensive_lines(delta)
	for t: int in range(2):
			var count: float = 0.0
			var sum_x: float = 0.0"""

# Wait, the earlier regex replacement added it to `_update_defensive_lines(delta)`... but maybe the indentation was wrong? Let us check.

