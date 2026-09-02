##
## GoalNet
##
## Realistic soccer goal rendering and dynamic spring-mass net physics.
##
## Visuals:
##   - 3D-shaded cylindrical upright posts on the goal line with bevels and caps.
##   - Top crossbar at z = 60.0 with 3D metallic styling.
##   - Rear metal tension stanchions / frame bars with cast turf drop shadows.
##   - Multi-plane net mesh (top roof, upper/lower sides, back net) with fine cords.
##   - Ambient occlusion depth shadow inside the goal mouth.
##   - Two-layer rendering: back net and turf shadow at z_index = -8 (behind entities),
##     front posts and crossbar at z_index = 5 (above entities entering the goal).
##
## Physics:
##   - 2D spring-mass lattice simulating dynamic net bulges, ripples, and wave damping.
##   - Soft aerodynamic and elastic cushioning drag decelerating shots in the net.
##   - Post / frame rebound integration.
##
## Depends on: Pseudo3DBall, CollisionLayers.
## Exposes: bind_ball(ball), reset_net(), trigger_impact(hit_local_y, impulse)
##

class_name GoalNet
extends Node2D

## Team defending this goal (0 = Left goal / Team A, 1 = Right goal / Team B).
@export var defending_team: int = 0:
	set(value):
		defending_team = value
		_update_direction()
		if is_inside_tree():
			_init_lattice()
			_queue_redraw_all()

## Height of the goal mouth opening in pixels.
@export var goal_mouth_height: float = 200.0:
	set(value):
		goal_mouth_height = value
		if is_inside_tree():
			_init_lattice()
			_queue_redraw_all()

## Depth of the goal net behind the goal line in pixels.
@export var goal_depth: float = 64.0:
	set(value):
		goal_depth = value
		if is_inside_tree():
			_init_lattice()
			_queue_redraw_all()

## Visual crossbar height in pseudo-3D pixels.
@export var crossbar_height: float = 60.0

## Radius of the cylindrical goalposts.
@export var post_radius: float = 6.0

## Elastic spring stiffness restoring net vertices to rest position.
@export var net_stiffness: float = 140.0

## Damping coefficient dissipating net oscillation waves.
@export var net_damping: float = 7.5

## Deceleration drag applied to balls cushioned in the net (px/s²).
@export var net_cushion_drag: float = 480.0

# Colors
const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.32)
const NET_CORD_COLOR: Color = Color(0.92, 0.95, 0.98, 0.68)
const NET_BORDER_COLOR: Color = Color(0.95, 0.97, 1.0, 0.85)
const FRAME_COLOR: Color = Color(0.85, 0.88, 0.92, 0.95)
const POST_BASE_COLOR: Color = Color(0.72, 0.75, 0.80, 1.0)
const POST_BODY_COLOR: Color = Color(0.98, 0.98, 1.0, 1.0)
const POST_HIGHLIGHT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)

# Lattice resolution
const LATTICE_COLS: int = 5
const LATTICE_ROWS: int = 9

# Dynamic net lattice storage (flattened arrays for zero dynamic allocations)
var _base_positions: Array[Vector2] = []
var _offsets: Array[Vector2] = []
var _velocities: Array[Vector2] = []
var _lattice_count: int = 0

# Direction multiplier along X (-1.0 for Left Goal, 1.0 for Right Goal)
var _direction: float = -1.0

var _ball: Pseudo3DBall = null
var _net_back_layer: Node2D = null
var _net_front_layer: Node2D = null
var _is_animating: bool = false


func _ready() -> void:
	_update_direction()
	_setup_render_layers()
	_init_lattice()
	_queue_redraw_all()


func bind_ball(ball_node: Pseudo3DBall) -> void:
	_ball = ball_node


func reset_net() -> void:
	for i: int in range(_lattice_count):
		_offsets[i] = Vector2.ZERO
		_velocities[i] = Vector2.ZERO
	_is_animating = false
	_queue_redraw_all()


func trigger_impact(hit_local_y: float, impulse: Vector2) -> void:
	var half_mouth: float = goal_mouth_height * 0.5
	var norm_y: float = clampf((hit_local_y + half_mouth) / goal_mouth_height, 0.0, 1.0)
	var target_row: float = norm_y * float(LATTICE_ROWS - 1)

	for c: int in range(LATTICE_COLS):
		for r: int in range(LATTICE_ROWS):
			var idx: int = c * LATTICE_ROWS + r
			var row_diff: float = absf(float(r) - target_row)
			var influence: float = clampf(1.0 - (row_diff / 3.0), 0.0, 1.0)
			if influence > 0.0:
				var col_factor: float = float(c + 1) / float(LATTICE_COLS)
				_velocities[idx] += impulse * influence * col_factor * 0.15
	_is_animating = true


func _update_direction() -> void:
	_direction = -1.0 if defending_team == 0 else 1.0


func _setup_render_layers() -> void:
	if _net_back_layer == null:
		_net_back_layer = Node2D.new()
		_net_back_layer.name = "NetBackLayer"
		_net_back_layer.z_index = -8
		_net_back_layer.draw.connect(_draw_back_net)
		add_child(_net_back_layer)

	if _net_front_layer == null:
		_net_front_layer = Node2D.new()
		_net_front_layer.name = "NetFrontLayer"
		_net_front_layer.z_index = 5
		_net_front_layer.draw.connect(_draw_front_posts)
		add_child(_net_front_layer)


func _init_lattice() -> void:
	_lattice_count = LATTICE_COLS * LATTICE_ROWS
	_base_positions.clear()
	_offsets.clear()
	_velocities.clear()

	_base_positions.resize(_lattice_count)
	_offsets.resize(_lattice_count)
	_velocities.resize(_lattice_count)

	var half_mouth: float = goal_mouth_height * 0.5
	for c: int in range(LATTICE_COLS):
		var u: float = float(c) / float(LATTICE_COLS - 1)
		var lx: float = _direction * u * goal_depth
		for r: int in range(LATTICE_ROWS):
			var v: float = float(r) / float(LATTICE_ROWS - 1)
			var ly: float = -half_mouth + v * goal_mouth_height
			var idx: int = c * LATTICE_ROWS + r
			_base_positions[idx] = Vector2(lx, ly)
			_offsets[idx] = Vector2.ZERO
			_velocities[idx] = Vector2.ZERO


func _physics_process(delta: float) -> void:
	_process_ball_interaction(delta)
	_step_lattice_physics(delta)


func _process_ball_interaction(delta: float) -> void:
	if _ball == null or not is_instance_valid(_ball):
		return

	var ball_local: Vector2 = to_local(_ball.global_position)
	var half_mouth: float = goal_mouth_height * 0.5
	var back_x: float = _direction * goal_depth

	# Check if ball is inside the goal mouth volume
	var is_inside_x: bool = false
	if _direction < 0.0:
		is_inside_x = (ball_local.x <= 8.0 and ball_local.x >= back_x - 16.0)
	else:
		is_inside_x = (ball_local.x >= -8.0 and ball_local.x <= back_x + 16.0)

	var is_inside_y: bool = (absf(ball_local.y) <= half_mouth + 12.0)

	if is_inside_x and is_inside_y:
		# 1. Soft net cushioning drag: decelerate velocity smoothly in ground and z axis
		var drag_amount: float = net_cushion_drag * delta
		_ball.velocity = _ball.velocity.move_toward(Vector2.ZERO, drag_amount)
		if _ball.position_z > 0.0:
			_ball.velocity_z *= clampf(1.0 - 4.5 * delta, 0.0, 1.0)

		# 2. Net back boundary soft cushion / prevent tunneling
		if _direction < 0.0:
			if ball_local.x < back_x + 6.0:
				_ball.global_position.x = to_global(Vector2(back_x + 6.0, ball_local.y)).x
				if _ball.velocity.x < 0.0:
					_ball.velocity.x = -_ball.velocity.x * 0.12
		else:
			if ball_local.x > back_x - 6.0:
				_ball.global_position.x = to_global(Vector2(back_x - 6.0, ball_local.y)).x
				if _ball.velocity.x > 0.0:
					_ball.velocity.x = -_ball.velocity.x * 0.12

		# 3. Dynamic mesh displacement: push nearby lattice vertices in ball travel direction
		var ball_speed: float = _ball.velocity.length()
		if ball_speed > 15.0 or absf(ball_local.x - back_x) < 24.0:
			var push_dir: Vector2 = _ball.velocity.normalized() if ball_speed > 1.0 else Vector2(_direction, 0.0)
			var push_mag: float = clampf(ball_speed * 0.06 + 2.0, 2.0, 22.0)
			var norm_y: float = clampf((ball_local.y + half_mouth) / goal_mouth_height, 0.0, 1.0)
			var target_r: float = norm_y * float(LATTICE_ROWS - 1)

			for c: int in range(LATTICE_COLS):
				var depth_weight: float = float(c + 1) / float(LATTICE_COLS)
				for r: int in range(LATTICE_ROWS):
					var idx: int = c * LATTICE_ROWS + r
					var dist_r: float = absf(float(r) - target_r)
					var weight: float = clampf(1.0 - (dist_r / 2.5), 0.0, 1.0)
					if weight > 0.0:
						_velocities[idx] += push_dir * push_mag * weight * depth_weight * delta * 60.0
						_is_animating = true


func _step_lattice_physics(delta: float) -> void:
	if not _is_animating:
		return

	var max_offset_sq: float = 0.0

	for c: int in range(LATTICE_COLS):
		for r: int in range(LATTICE_ROWS):
			var idx: int = c * LATTICE_ROWS + r

			# Fixed anchors: front mouth edges do not displace
			if c == 0 and (r == 0 or r == LATTICE_ROWS - 1):
				_offsets[idx] = Vector2.ZERO
				_velocities[idx] = Vector2.ZERO
				continue

			var offset: Vector2 = _offsets[idx]
			var vel: Vector2 = _velocities[idx]

			# Restoring spring force toward base position
			var spring_force: Vector2 = -offset * net_stiffness - vel * net_damping

			# Neighbor tension coupling across rows
			if r > 0:
				var top_idx: int = idx - 1
				spring_force += (_offsets[top_idx] - offset) * (net_stiffness * 0.25)
			if r < LATTICE_ROWS - 1:
				var btm_idx: int = idx + 1
				spring_force += (_offsets[btm_idx] - offset) * (net_stiffness * 0.25)

			# Neighbor tension coupling across columns
			if c > 0:
				var left_idx: int = idx - LATTICE_ROWS
				spring_force += (_offsets[left_idx] - offset) * (net_stiffness * 0.20)
			if c < LATTICE_COLS - 1:
				var right_idx: int = idx + LATTICE_ROWS
				spring_force += (_offsets[right_idx] - offset) * (net_stiffness * 0.20)

			vel += spring_force * delta
			offset += vel * delta

			# Clamp maximum displacement to prevent extreme deformation
			var dist_sq: float = offset.length_squared()
			if dist_sq > 900.0:
				offset = offset.normalized() * 30.0
				vel *= 0.5
				dist_sq = 900.0

			_offsets[idx] = offset
			_velocities[idx] = vel

			if dist_sq > max_offset_sq:
				max_offset_sq = dist_sq

	if max_offset_sq > 0.04:
		_queue_redraw_all()
	else:
		_is_animating = false
		for i: int in range(_lattice_count):
			_offsets[i] = Vector2.ZERO
			_velocities[i] = Vector2.ZERO
		_queue_redraw_all()


func _queue_redraw_all() -> void:
	if _net_back_layer != null:
		_net_back_layer.queue_redraw()
	if _net_front_layer != null:
		_net_front_layer.queue_redraw()


func _get_point(c: int, r: int) -> Vector2:
	var idx: int = c * LATTICE_ROWS + r
	if idx < 0 or idx >= _lattice_count:
		return Vector2.ZERO
	return _base_positions[idx] + _offsets[idx]


# --- Drawing Routines ---

func _draw_back_net() -> void:
	var half_mouth: float = goal_mouth_height * 0.5
	var back_x: float = _direction * goal_depth

	# 1. Turf Ambient Occlusion Shadow inside the goal
	var shadow_poly: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -half_mouth),
		Vector2(back_x, -half_mouth),
		Vector2(back_x, half_mouth),
		Vector2(0.0, half_mouth)
	])
	_net_back_layer.draw_colored_polygon(shadow_poly, SHADOW_COLOR)

	# 2. Rear support tension stanchion shadows on turf
	var stanchion_shadow_top: Vector2 = Vector2(back_x * 1.25, -half_mouth - 12.0)
	var stanchion_shadow_btm: Vector2 = Vector2(back_x * 1.25, half_mouth + 12.0)
	_net_back_layer.draw_line(Vector2(0.0, -half_mouth), stanchion_shadow_top, Color(0.0, 0.0, 0.0, 0.22), 3.0)
	_net_back_layer.draw_line(Vector2(0.0, half_mouth), stanchion_shadow_btm, Color(0.0, 0.0, 0.0, 0.22), 3.0)

	# 3. Rear ground frame bar along turf
	_net_back_layer.draw_line(Vector2(0.0, -half_mouth), Vector2(back_x, -half_mouth), FRAME_COLOR, 3.0)
	_net_back_layer.draw_line(Vector2(back_x, -half_mouth), Vector2(back_x, half_mouth), FRAME_COLOR, 3.5)
	_net_back_layer.draw_line(Vector2(back_x, half_mouth), Vector2(0.0, half_mouth), FRAME_COLOR, 3.0)

	# 4. Metal tension stanchions angled back
	_net_back_layer.draw_line(Vector2(0.0, -half_mouth), Vector2(back_x, -half_mouth), FRAME_COLOR, 2.5)
	_net_back_layer.draw_line(Vector2(0.0, half_mouth), Vector2(back_x, half_mouth), FRAME_COLOR, 2.5)

	# 5. Back & Side Net Diamond Mesh
	if _lattice_count == 0:
		return

	# Horizontal cords connecting columns across each row
	for r: int in range(LATTICE_ROWS):
		for c: int in range(LATTICE_COLS - 1):
			var p_h1: Vector2 = _get_point(c, r)
			var p_h2: Vector2 = _get_point(c + 1, r)
			var is_border: bool = (r == 0 or r == LATTICE_ROWS - 1)
			_net_back_layer.draw_line(p_h1, p_h2, NET_BORDER_COLOR if is_border else NET_CORD_COLOR, 1.5 if is_border else 1.0)

	# Vertical / cross cords connecting rows down each column
	for c: int in range(LATTICE_COLS):
		for r: int in range(LATTICE_ROWS - 1):
			var p_v1: Vector2 = _get_point(c, r)
			var p_v2: Vector2 = _get_point(c, r + 1)
			var is_back_or_front: bool = (c == 0 or c == LATTICE_COLS - 1)
			_net_back_layer.draw_line(p_v1, p_v2, NET_BORDER_COLOR if is_back_or_front else NET_CORD_COLOR, 1.5 if is_back_or_front else 1.0)

	# Diagonal cross mesh pattern for hexagonal / diamond netting look
	for c: int in range(LATTICE_COLS - 1):
		for r: int in range(LATTICE_ROWS - 1):
			var p_tl: Vector2 = _get_point(c, r)
			var p_br: Vector2 = _get_point(c + 1, r + 1)
			_net_back_layer.draw_line(p_tl, p_br, Color(NET_CORD_COLOR.r, NET_CORD_COLOR.g, NET_CORD_COLOR.b, 0.40), 0.9)


func _draw_front_posts() -> void:
	var half_mouth: float = goal_mouth_height * 0.5

	# Top rear horizontal tension bar
	var back_top: Vector2 = _get_point(LATTICE_COLS - 1, 0)
	var back_btm: Vector2 = _get_point(LATTICE_COLS - 1, LATTICE_ROWS - 1)
	_net_front_layer.draw_line(back_top, back_btm, FRAME_COLOR, 2.5)

	# Front Crossbar along the goal line at mouth entrance
	var top_post_pos: Vector2 = Vector2(0.0, -half_mouth)
	var btm_post_pos: Vector2 = Vector2(0.0, half_mouth)

	# Crossbar shadow / base
	_net_front_layer.draw_line(top_post_pos, btm_post_pos, POST_BASE_COLOR, post_radius * 2.0 + 1.0)
	# Crossbar white glossy body
	_net_front_layer.draw_line(top_post_pos, btm_post_pos, POST_BODY_COLOR, post_radius * 2.0 - 1.0)
	# Crossbar 3D highlight
	var hl_offset_x: float = -_direction * 1.2
	_net_front_layer.draw_line(top_post_pos + Vector2(hl_offset_x, 0.0), btm_post_pos + Vector2(hl_offset_x, 0.0), POST_HIGHLIGHT_COLOR, 1.2)

	# 3D Cylindrical Goalposts (Top and Bottom)
	_draw_3d_post(_net_front_layer, top_post_pos)
	_draw_3d_post(_net_front_layer, btm_post_pos)


func _draw_3d_post(canvas: Node2D, pos: Vector2) -> void:
	# Post ground drop shadow
	canvas.draw_circle(pos + Vector2(2.0, 2.0), post_radius + 1.5, Color(0.0, 0.0, 0.0, 0.35))
	# Post outer bevel
	canvas.draw_circle(pos, post_radius + 1.0, POST_BASE_COLOR)
	# Post white core
	canvas.draw_circle(pos, post_radius, POST_BODY_COLOR)
	# Post top specular highlight
	canvas.draw_circle(pos + Vector2(-_direction * 1.2, -1.2), post_radius * 0.45, POST_HIGHLIGHT_COLOR)
