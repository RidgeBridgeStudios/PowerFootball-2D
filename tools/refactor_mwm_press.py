
import re

with open("autoloads/MatchWorldModel.gd", "r") as f:
    content = f.read()

old_press = """	if forward_dot < -PASS_FORWARD_DOT_TOLERANCE:
		trigger = PressTrigger.BACKWARD_PASS
	elif forward_dot <= PASS_FORWARD_DOT_TOLERANCE:
		trigger = PressTrigger.SQUARE_PASS
	if trigger == PressTrigger.NONE:
		return"""

new_press = """	if forward_dot < -PASS_FORWARD_DOT_TOLERANCE:
		trigger = PressTrigger.BACKWARD_PASS
	elif forward_dot <= PASS_FORWARD_DOT_TOLERANCE:
		trigger = PressTrigger.SQUARE_PASS
	elif _speed < 200.0: # slow pass or airborne pass
		trigger = PressTrigger.BACKWARD_PASS # reusing trigger type since it just activates press
	if trigger == PressTrigger.NONE:
		return"""

content = content.replace(old_press, new_press)

with open("autoloads/MatchWorldModel.gd", "w") as f:
    f.write(content)

