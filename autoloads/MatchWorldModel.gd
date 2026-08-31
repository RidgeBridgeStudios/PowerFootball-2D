##
## MatchWorldModel (Autoload singleton)
##
## The match's spatial cache. Every CPU brain used to answer "where is everyone?"
## with its own get_tree().get_nodes_in_group() scan — 22 brains × 7 scan sites ×
## 60 Hz. This node does that work once per physics frame into contiguous packed
## arrays, and everyone else reads an index.
##
## It runs at process_priority -100 so the cache is already refreshed before any
## PlayerBrain (0) decides or any HeavyPlayerController (100) moves. Reading a
## position from here is therefore always this frame's position, never last
## frame's.
##
## Registration is push-based: HeavyPlayerController._ready() claims the next
## free slot, so the model works with the declarative player layout in
## PitchScene.tscn without the pitch having to enumerate anything.
##
## Depends on: HeavyPlayerController, Pseudo3DBall. Nothing depends on this
## being loaded after another autoload, so it is declared first in project.godot.
## Exposes: instance, register_player(), register_ball(), unregister_all(),
##          player_nodes/player_positions/player_velocities/player_teams,
##          ball_position, ball_velocity, possessor_index,
##          get_opponents_of(), get_teammates_of(), nearest_opponent_dist_to(),
##          world_to_cell(), get_nearby_players(), get_nearby_opponents(),
##          get_nearby_teammates(), get_nearby_opponent_nodes(),
##          count_nearby_players(), count_nearby_opponents(), count_nearby_teammates(),
##          get_opponent_density(), get_teammate_density(),
##          is_passing_lane_open(), is_lane_blocked_by_opponent(),
##          get_passing_lane_min_distance(),
##          defensive_line_x — shared per-team defensive-line depth (world X),
##          recomputed every frame from ball position and carrier pressure
##          bind_boundary(), PressTrigger enum, press_trigger_active/type/
##          carrier/position — the pressing trigger detector (see "Pressing
##          trigger detection" below); GameEvents.press_trigger_changed is the
##          preferred way to consume it
##
## Pressing trigger detection: a small, cheap read of state this file already
## caches (plus one signal subscription for pass events) that answers "is
## there a football-relevant reason to press right now?" without any brain
## having to compute it itself. See the "--- Pressing trigger detection ---"
## section below for the five triggers and their thresholds. bind_boundary()
## is optional and mirrors PlayerBrain.bind_boundary() — the touchline
## trigger simply never fires if it is never called (e.g. Practice Arena).
##
## NOTE: class_name is intentionally absent. This script is registered as an
## autoload singleton — Godot 4.7+ rejects class_name declarations that shadow
## the autoload's injected global name. Access via MatchWorldModel.instance.
##
extends Node

## The live singleton. Assigned in _enter_tree() so it is available before any
## other node's _ready() runs.
static var instance: MatchWorldModel = null

## 11 per team — 10 outfield plus a goalkeeper. PitchScene.tscn declares exactly
## this many children under $Players; any other value silently truncates the
## cache and starves the missing slots of AI input.
const TOTAL_PLAYERS: int = 22

## Sentinel for "no player occupies this slot / no possessor".
const NO_INDEX: int = -1

## Default corridor width / clearance threshold (in pixels) for passing lane safety checks.
const DEFAULT_PASS_LANE_CLEARANCE: float = 45.0

## --- Player cache -----------------------------------------------------------
## Four parallel arrays rather than an array of structs: the hot loops in
## PlayerBrain read positions and teams far more often than they need the node
## itself, and the packed arrays keep those reads contiguous.

var player_nodes: Array[HeavyPlayerController] = []
var player_positions: PackedVector2Array = PackedVector2Array()
var player_velocities: PackedVector2Array = PackedVector2Array()
var player_teams: PackedInt32Array = PackedInt32Array()

## --- Ball cache -------------------------------------------------------------

var ball_node: Pseudo3DBall = null
var ball_position: Vector2 = Vector2.ZERO
var ball_velocity: Vector2 = Vector2.ZERO
## Index into player_nodes of whoever currently has the ball, or NO_INDEX.
## Resolved from Pseudo3DBall.possessor, falling back to last_touched_by.
var possessor_index: int = NO_INDEX

## Next slot handed out by register_player() when a caller passes NO_INDEX.
var _auto_index: int = 0

## --- Defensive line cache ----------------------------------------------------
## A world-level, per-team depth target the back line steers against as one
## band instead of four independently-computed dots (PlayerBrain adds this on
## top of its existing per-player dynamic formation anchor — see
## PlayerBrain._find_open_space_target()'s OUTFIELD_DEFENDER branch). This
## project's attacking axis is X (goals sit at the X ends — see
## PitchBoundary.get_goal_centre()), so "line depth" here is an X coordinate
## despite the more familiar "defensive_line_y" naming from side-view football
## games. Recomputed once per physics frame at this node's -100 priority,
## ahead of any PlayerBrain decision, so every defender reads this frame's
## line rather than a stale one.
##
## Index 0 == GameManager.TEAM_A (attacks +X), index 1 == GameManager.TEAM_B
## (attacks -X). Read as ints here rather than via GameManager's constants to
## avoid adding a new autoload dependency to this file's boot-order-sensitive
## header (see class doc "Depends on:").

## Crowding radius used to judge whether the current ball carrier is under
## pressure. Mirrors PlayerBrain.PRESSURE_RADIUS so "pressured" reads the same
## meaning in both places; duplicated rather than referenced so this file
## still depends on nothing but HeavyPlayerController and Pseudo3DBall.
const CARRIER_PRESSURE_RADIUS: float = 180.0

## World-px the line sits goal-side of the ball when its team applies no
## pressure to the carrier (opponent has time — line drops deep to cover the
## space in behind).
const LINE_OFFSET_DROPPED: float = 150.0
## World-px when the team is fully pressuring the carrier (numbers already
## around the ball — the line can step up and compress the pitch).
const LINE_OFFSET_PRESSED: float = 60.0
## How fast the line glides toward its target, world-px/sec. Keeps the back
## four moving as a smooth wave rather than snapping every time the ball
## twitches.
const LINE_DEPTH_LERP_SPEED: float = 220.0

## Per-team [TEAM_A, TEAM_B] defensive line depth, world-space X. Read by
## PlayerBrain via MatchWorldModel.instance.defensive_line_x[team].
var defensive_line_x: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])

## False until the first _update_defensive_lines() call, so that call can snap
## straight to its target instead of gliding in from a stale 0.0 at kickoff.
var _defensive_lines_ready: bool = false

## Scratch buffers for the two Array-returning accessors. Reused between calls
## so a caller on a warm path does not allocate; see the accessor docs for the
## aliasing rule that comes with that.
var _opponent_scratch: Array[int] = []
var _teammate_scratch: Array[int] = []

## --- Spatial Hash Grid -------------------------------------------------------
## 2D spatial partition for fast proximity and density queries.
## With pitch ~1600x900, 160px cells form a ~10x6 grid where each cell holds
## 0-3 players on average. Radii queries (55-220px) inspect only 1-9 cells.
const CELL_SIZE: float = 160.0
const INV_CELL_SIZE: float = 1.0 / CELL_SIZE

## Cell -> Array[int] of player indices (slots).
## Buckets are reused across frames to maintain zero GC allocations.
var _grid: Dictionary = {}
## Track cells populated during the frame so only dirty cells are cleared.
var _active_cells: Array[Vector2i] = []

## Scratch buffers for spatial query results.
var _nearby_players_scratch: Array[int] = []
var _nearby_opponents_scratch: Array[int] = []
var _nearby_teammates_scratch: Array[int] = []
var _nearby_nodes2d_scratch: Array[Node2D] = []

## --- Pressing trigger detection ----------------------------------------------
## Football-relevant reasons the defending team should press right now rather
## than hold shape and wait. Deliberately small: five cheap checks over
## state this file already caches, gated so at most one trigger is active at
## a time and each one holds for a fixed window once armed — see
## PRESS_TRIGGER_HOLD_SECONDS. NONE means no trigger is currently active.
enum PressTrigger {
	NONE = 0,
	BACKWARD_PASS = 1,       ## A pass was played back toward the kicker's own goal, into pressure.
	SQUARE_PASS = 2,         ## A pass was played sideways (neither forward nor back), into pressure.
	TOUCHLINE_ISOLATION = 3, ## Carrier is pinned near a touchline with no close support.
	HEAVY_TOUCH = 4,         ## The ball has run loose away from its own toucher's feet, near an opponent.
	FACING_OWN_GOAL = 5,     ## Carrier's back is to the opponent's goal while they hold the ball.
}

## Seconds a continuous trigger (touchline isolation, heavy touch, facing own
## goal) holds once armed before the next evaluation is allowed. Long enough
## for PlayerBrain's up-to-15-frame decision stagger (see PlayerBrain.md) to
## actually see and act on it; short enough that the press does not outlive
## the moment that justified it.
const PRESS_TRIGGER_HOLD_SECONDS: float = 1.4
## Same idea for the two pass-event triggers, which fire from a discrete kick
## rather than a per-frame condition — slightly shorter, since by the time it
## expires the pass has already been controlled or lost.
const PRESS_TRIGGER_PASS_HOLD_SECONDS: float = 1.1

## Forward-direction dot product band a struck (non-shot) ball's velocity must
## fall in, relative to the kicker's attacking direction, to count as backward
## (< -this) or square (within +/- this) rather than a normal forward pass.
const PASS_FORWARD_DOT_TOLERANCE: float = 0.25
## How far ahead along the ball's just-struck velocity to project when asking
## "is this pass landing near an opponent" — a straight-line lookahead, not a
## trajectory walk, since only the destination neighbourhood matters here.
const PASS_PRESSURE_LOOKAHEAD_SECONDS: float = 0.35

## World-px from either touchline inside which the ball carrier counts as
## "pinned wide" for the isolation trigger.
const TOUCHLINE_MARGIN: float = 70.0
## A carrier pinned near the touchline needs a teammate within this radius to
## count as supported; beyond it, they are isolated.
const ISOLATION_SUPPORT_RADIUS: float = 200.0

## Ball-to-toucher distance band, world-px, that counts as a heavy first
## touch: close enough that it is still clearly this player's ball, far
## enough that it has plainly got away from their feet. Mirrors the kind of
## gap DribbleState's foot-range check would already treat as "lost the
## ball" at the top end.
const HEAVY_TOUCH_MIN_DIST: float = 55.0
const HEAVY_TOUCH_MAX_DIST: float = 130.0

## Minimum facing_dot (see HeavyPlayerController.get_facing_dot()) toward a
## point deep in the carrier's own half for "facing own goal" to trigger.
const FACING_OWN_GOAL_DOT_THRESHOLD: float = 0.5

## True while a pressing trigger is active. Read this — or, better, listen for
## GameEvents.press_trigger_changed — rather than re-deriving any of the
## conditions below in another system.
var press_trigger_active: bool = false
var press_trigger_type: PressTrigger = PressTrigger.NONE
## Nullable: the backward/square-pass triggers name the kicker, since the
## receiver is not yet known at the moment the ball is struck.
var press_trigger_carrier: HeavyPlayerController = null
var press_trigger_position: Vector2 = Vector2.ZERO

## Counts down while a trigger is active; continuous triggers are only
## re-evaluated once this reaches zero, which is what keeps the system from
## flapping between contradictory reads of a fast-changing situation.
var _press_trigger_timer: float = 0.0

## Bound by PitchScene alongside PlayerBrain.bind_boundary() (see
## _bind_players()). Optional — left null in any setup that never calls
## bind_boundary(), in which case TOUCHLINE_ISOLATION alone never fires.
var _boundary: PitchBoundary = null

## Deferred to the first _physics_process() rather than connected in
## _ready(): this autoload is deliberately declared first in project.godot
## (see class doc "Depends on:") so nothing else has to load before it, which
## means GameEvents does not exist yet when this node's own _ready() runs.
## By the first physics frame every autoload is guaranteed ready.
var _ball_struck_connected: bool = false


func _enter_tree() -> void:
	instance = self
	_resize_arrays()


func _ready() -> void:
	# Ahead of PlayerBrain (0) and HeavyPlayerController (100). The whole
	# point of the model is that it is already fresh when they read it.
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if instance == self:
		instance = null


## --- Registration -----------------------------------------------------------

## Claims `index` for `node`. Pass NO_INDEX to take the next free slot, which is
## what HeavyPlayerController._ready() does under the declarative spawn layout.
## Returns the index actually used, or NO_INDEX if the roster is already full.
func register_player(index: int, node: HeavyPlayerController, team: int) -> int:
	var slot: int = index
	if slot == NO_INDEX:
		slot = _auto_index
		_auto_index += 1

	if slot < 0 or slot >= TOTAL_PLAYERS:
		push_warning(
			"MatchWorldModel.register_player: slot %d is outside 0..%d; %s not cached."
			% [slot, TOTAL_PLAYERS - 1, node.name if node != null else "<null>"])
		return NO_INDEX

	player_nodes[slot] = node
	player_teams[slot] = team
	if node != null:
		player_positions[slot] = node.global_position
		player_velocities[slot] = node.velocity

	# Keep the auto counter ahead of any explicitly claimed slot so a mixed
	# explicit/auto registration order cannot hand the same slot out twice.
	if slot >= _auto_index:
		_auto_index = slot + 1

	return slot


func register_ball(node: Pseudo3DBall) -> void:
	ball_node = node
	if node != null:
		ball_position = node.global_position
		ball_velocity = node.velocity


## Clears the roster back to empty. Called when a match tears down, so the next
## match's players start claiming slots from 0 again.
func unregister_all() -> void:
	_auto_index = 0
	ball_node = null
	ball_position = Vector2.ZERO
	ball_velocity = Vector2.ZERO
	possessor_index = NO_INDEX
	defensive_line_x[0] = 0.0
	defensive_line_x[1] = 0.0
	_defensive_lines_ready = false
	_clear_press_trigger()
	_press_trigger_timer = 0.0
	_boundary = null
	_grid.clear()
	_active_cells.clear()
	_nearby_players_scratch.clear()
	_nearby_opponents_scratch.clear()
	_nearby_teammates_scratch.clear()
	_nearby_nodes2d_scratch.clear()
	_resize_arrays()


## --- Per-frame refresh ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _ball_struck_connected:
		GameEvents.ball_struck.connect(_on_ball_struck)
		_ball_struck_connected = true

	if ball_node != null and is_instance_valid(ball_node):
		ball_position = ball_node.global_position
		ball_velocity = ball_node.velocity

	possessor_index = _resolve_possessor_index()

	for i: int in range(TOTAL_PLAYERS):
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		player_positions[i] = node.global_position
		player_velocities[i] = node.velocity

	_update_spatial_grid()
	_update_defensive_lines(delta)
	_update_press_trigger(delta)


## Converts a 2D world position into discrete spatial grid cell coordinates.
func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floorf(world_pos.x * INV_CELL_SIZE)),
		int(floorf(world_pos.y * INV_CELL_SIZE))
	)


## Refreshes the spatial partition grid. Reuses cell bucket arrays to achieve
## zero heap allocations per physics frame.
func _update_spatial_grid() -> void:
	for cell: Vector2i in _active_cells:
		var clear_bucket: Array[int] = _grid.get(cell, [] as Array[int])
		clear_bucket.clear()
	_active_cells.clear()

	for i: int in range(TOTAL_PLAYERS):
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		var cell: Vector2i = world_to_cell(player_positions[i])
		if not _grid.has(cell):
			var new_bucket: Array[int] = []
			_grid[cell] = new_bucket
		var bucket: Array[int] = _grid[cell]
		bucket.append(i)
		_active_cells.append(cell)


## Bound by PitchScene at match setup, mirroring PlayerBrain.bind_boundary().
## Only the touchline-isolation trigger reads this; every other trigger works
## without it.
func bind_boundary(b: PitchBoundary) -> void:
	_boundary = b


## Recomputes both teams' shared line depth from the ball's position and
## whichever team is currently pressuring the carrier. Called after the
## per-player position refresh above so it reads this frame's positions.
func _update_defensive_lines(delta: float) -> void:
	if ball_node == null or not is_instance_valid(ball_node):
		return

	var target_x: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
	for t: int in range(2):
		# Team 0 attacks +X, team 1 attacks -X (see soccer-physics.md /
		# FormationAnchorMath's identical convention) — dropping off means
		# moving opposite the attack direction, toward this team's own goal.
		var attack_sign: float = 1.0 if t == 0 else -1.0
		var pressure: float = 0.0
		# Only this team's own pressure on an opposing carrier steps their
		# line up. A loose ball or their own possession leaves pressure at
		# 0.0, which settles the line to its deepest, safest default rather
		# than inventing a reading for a phase this cache does not track.
		if possessor_index != NO_INDEX and player_teams[possessor_index] != t:
			pressure = _team_pressure_on_ball(t)
		var offset: float = lerpf(LINE_OFFSET_DROPPED, LINE_OFFSET_PRESSED, pressure)
		target_x[t] = ball_position.x - attack_sign * offset

	if not _defensive_lines_ready:
		defensive_line_x[0] = target_x[0]
		defensive_line_x[1] = target_x[1]
		_defensive_lines_ready = true
		return

	defensive_line_x[0] = move_toward(defensive_line_x[0], target_x[0], LINE_DEPTH_LERP_SPEED * delta)
	defensive_line_x[1] = move_toward(defensive_line_x[1], target_x[1], LINE_DEPTH_LERP_SPEED * delta)


## 0.0-1.0 crowding score of `team`'s players around the ball — computed
## directly from the spatial grid without linear scans or allocations.
func _team_pressure_on_ball(team: int) -> float:
	return clampf(get_teammate_density(ball_position, CARRIER_PRESSURE_RADIUS, team), 0.0, 1.0)


## Pseudo3DBall carries the possessor on `possessor` (a Node2D set by
## DribbleState/TackleState) and the last striker on `last_touched_by`.
## `possessor` is the stronger claim, so it wins; last_touched_by only stands in
## while the ball is loose, which is what "who does the AI treat as the carrier"
## wants.
func _resolve_possessor_index() -> int:
	if ball_node == null or not is_instance_valid(ball_node):
		return NO_INDEX

	var holder: Node2D = ball_node.possessor
	if holder == null:
		holder = ball_node.last_touched_by
	if holder == null:
		return NO_INDEX

	for i: int in range(TOTAL_PLAYERS):
		if player_nodes[i] == holder:
			return i
	return NO_INDEX


## --- Accessors --------------------------------------------------------------
## All O(TOTAL_PLAYERS) at worst and none of them touch the scene tree.

## Indices of every registered player NOT on `team`.
##
## The returned Array is a scratch buffer owned by this node and is overwritten
## by the next call — copy it if you need to hold it across a call. Not used on
## the per-frame steering path; PlayerBrain indexes player_positions directly
## there to stay allocation-free.
func get_opponents_of(team: int) -> Array[int]:
	_opponent_scratch.clear()
	for i: int in range(TOTAL_PLAYERS):
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if player_teams[i] != team:
			_opponent_scratch.append(i)
	return _opponent_scratch


## Indices of every registered player on the same team as player_nodes[index],
## excluding `index` itself. Same scratch-buffer rule as get_opponents_of().
func get_teammates_of(index: int) -> Array[int]:
	_teammate_scratch.clear()
	if index < 0 or index >= TOTAL_PLAYERS:
		return _teammate_scratch

	var team: int = player_teams[index]
	for i: int in range(TOTAL_PLAYERS):
		if i == index:
			continue
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if player_teams[i] == team:
			_teammate_scratch.append(i)
	return _teammate_scratch


## --- Spatial Grid Proximity & Density Queries -------------------------------

## Indices of every registered player within `radius` of `pos`.
## Scratch-buffered and allocation-free. Overwritten by the next call.
func get_nearby_players(pos: Vector2, radius: float) -> Array[int]:
	_nearby_players_scratch.clear()
	if radius <= 0.0:
		return _nearby_players_scratch
	var r_sq: float = radius * radius
	var min_cx: int = int(floorf((pos.x - radius) * INV_CELL_SIZE))
	var max_cx: int = int(floorf((pos.x + radius) * INV_CELL_SIZE))
	var min_cy: int = int(floorf((pos.y - radius) * INV_CELL_SIZE))
	var max_cy: int = int(floorf((pos.y + radius) * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if player_positions[i].distance_squared_to(pos) <= r_sq:
					_nearby_players_scratch.append(i)
	return _nearby_players_scratch


## Indices of registered players NOT on `team` within `radius` of `pos`.
## Scratch-buffered and allocation-free.
func get_nearby_opponents(pos: Vector2, radius: float, team: int) -> Array[int]:
	_nearby_opponents_scratch.clear()
	if radius <= 0.0:
		return _nearby_opponents_scratch
	var r_sq: float = radius * radius
	var min_cx: int = int(floorf((pos.x - radius) * INV_CELL_SIZE))
	var max_cx: int = int(floorf((pos.x + radius) * INV_CELL_SIZE))
	var min_cy: int = int(floorf((pos.y - radius) * INV_CELL_SIZE))
	var max_cy: int = int(floorf((pos.y + radius) * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if player_teams[i] != team and player_positions[i].distance_squared_to(pos) <= r_sq:
					_nearby_opponents_scratch.append(i)
	return _nearby_opponents_scratch


## Indices of registered players on `team` within `radius` of `pos`, excluding `exclude_index`.
## Scratch-buffered and allocation-free.
func get_nearby_teammates(pos: Vector2, radius: float, team: int, exclude_index: int = NO_INDEX) -> Array[int]:
	_nearby_teammates_scratch.clear()
	if radius <= 0.0:
		return _nearby_teammates_scratch
	var r_sq: float = radius * radius
	var min_cx: int = int(floorf((pos.x - radius) * INV_CELL_SIZE))
	var max_cx: int = int(floorf((pos.x + radius) * INV_CELL_SIZE))
	var min_cy: int = int(floorf((pos.y - radius) * INV_CELL_SIZE))
	var max_cy: int = int(floorf((pos.y + radius) * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if i != exclude_index and player_teams[i] == team and player_positions[i].distance_squared_to(pos) <= r_sq:
					_nearby_teammates_scratch.append(i)
	return _nearby_teammates_scratch


## Node2D instances of opponents within `radius` of `pos`.
## Scratch-buffered and allocation-free. Replaces legacy full-pitch scans.
func get_nearby_opponent_nodes(pos: Vector2, radius: float, team: int) -> Array[Node2D]:
	_nearby_nodes2d_scratch.clear()
	if radius <= 0.0:
		return _nearby_nodes2d_scratch
	var r_sq: float = radius * radius
	var min_cx: int = int(floorf((pos.x - radius) * INV_CELL_SIZE))
	var max_cx: int = int(floorf((pos.x + radius) * INV_CELL_SIZE))
	var min_cy: int = int(floorf((pos.y - radius) * INV_CELL_SIZE))
	var max_cy: int = int(floorf((pos.y + radius) * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if player_teams[i] != team and player_positions[i].distance_squared_to(pos) <= r_sq:
					var node: HeavyPlayerController = player_nodes[i]
					if node != null and is_instance_valid(node):
						_nearby_nodes2d_scratch.append(node)
	return _nearby_nodes2d_scratch


## Zero-allocation count of registered players within `radius` of `pos`.
func count_nearby_players(pos: Vector2, radius: float) -> int:
	if radius <= 0.0:
		return 0
	var count: int = 0
	var r_sq: float = radius * radius
	var min_cx: int = int(floorf((pos.x - radius) * INV_CELL_SIZE))
	var max_cx: int = int(floorf((pos.x + radius) * INV_CELL_SIZE))
	var min_cy: int = int(floorf((pos.y - radius) * INV_CELL_SIZE))
	var max_cy: int = int(floorf((pos.y + radius) * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if player_positions[i].distance_squared_to(pos) <= r_sq:
					count += 1
	return count


## Zero-allocation count of opponents within `radius` of `pos`.
func count_nearby_opponents(pos: Vector2, radius: float, team: int) -> int:
	if radius <= 0.0:
		return 0
	var count: int = 0
	var r_sq: float = radius * radius
	var min_cx: int = int(floorf((pos.x - radius) * INV_CELL_SIZE))
	var max_cx: int = int(floorf((pos.x + radius) * INV_CELL_SIZE))
	var min_cy: int = int(floorf((pos.y - radius) * INV_CELL_SIZE))
	var max_cy: int = int(floorf((pos.y + radius) * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if player_teams[i] != team and player_positions[i].distance_squared_to(pos) <= r_sq:
					count += 1
	return count


## Zero-allocation count of teammates within `radius` of `pos`, excluding `exclude_index`.
func count_nearby_teammates(pos: Vector2, radius: float, team: int, exclude_index: int = NO_INDEX) -> int:
	if radius <= 0.0:
		return 0
	var count: int = 0
	var r_sq: float = radius * radius
	var min_cx: int = int(floorf((pos.x - radius) * INV_CELL_SIZE))
	var max_cx: int = int(floorf((pos.x + radius) * INV_CELL_SIZE))
	var min_cy: int = int(floorf((pos.y - radius) * INV_CELL_SIZE))
	var max_cy: int = int(floorf((pos.y + radius) * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if i != exclude_index and player_teams[i] == team and player_positions[i].distance_squared_to(pos) <= r_sq:
					count += 1
	return count


## Weighted crowding score of opponents within `radius` of `pos`.
## Uses 1.0 - (d / radius) falloff. Allocation-free.
func get_opponent_density(pos: Vector2, radius: float, team: int) -> float:
	if radius <= 0.0:
		return 0.0
	var total: float = 0.0
	var r_sq: float = radius * radius
	var min_cx: int = int(floorf((pos.x - radius) * INV_CELL_SIZE))
	var max_cx: int = int(floorf((pos.x + radius) * INV_CELL_SIZE))
	var min_cy: int = int(floorf((pos.y - radius) * INV_CELL_SIZE))
	var max_cy: int = int(floorf((pos.y + radius) * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if player_teams[i] != team:
					var d_sq: float = pos.distance_squared_to(player_positions[i])
					if d_sq < r_sq:
						total += 1.0 - (sqrt(d_sq) / radius)
	return total


## Weighted crowding score of teammates on `team` within `radius` of `pos`, excluding `exclude_index`.
## Uses 1.0 - (d / radius) falloff. Allocation-free.
func get_teammate_density(pos: Vector2, radius: float, team: int, exclude_index: int = NO_INDEX) -> float:
	if radius <= 0.0:
		return 0.0
	var total: float = 0.0
	var r_sq: float = radius * radius
	var min_cx: int = int(floorf((pos.x - radius) * INV_CELL_SIZE))
	var max_cx: int = int(floorf((pos.x + radius) * INV_CELL_SIZE))
	var min_cy: int = int(floorf((pos.y - radius) * INV_CELL_SIZE))
	var max_cy: int = int(floorf((pos.y + radius) * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if i != exclude_index and player_teams[i] == team:
					var d_sq: float = pos.distance_squared_to(player_positions[i])
					if d_sq < r_sq:
						total += 1.0 - (sqrt(d_sq) / radius)
	return total


## Returns true if the passing lane from `start_pos` to `end_pos` is clear of any opponent
## (players not on `passer_team_id`) within `corridor_width` px of the pass segment.
##
## Performs an analytical point-to-segment distance / vector projection check.
## Uses the spatial grid bounding box to test only relevant cells. Allocation-free.
func is_passing_lane_open(
		start_pos: Vector2,
		end_pos: Vector2,
		passer_team_id: int,
		corridor_width: float = DEFAULT_PASS_LANE_CLEARANCE
) -> bool:
	if corridor_width <= 0.0:
		return true

	var min_x: float = minf(start_pos.x, end_pos.x) - corridor_width
	var max_x: float = maxf(start_pos.x, end_pos.x) + corridor_width
	var min_y: float = minf(start_pos.y, end_pos.y) - corridor_width
	var max_y: float = maxf(start_pos.y, end_pos.y) + corridor_width

	var min_cx: int = int(floorf(min_x * INV_CELL_SIZE))
	var max_cx: int = int(floorf(max_x * INV_CELL_SIZE))
	var min_cy: int = int(floorf(min_y * INV_CELL_SIZE))
	var max_cy: int = int(floorf(max_y * INV_CELL_SIZE))

	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if player_teams[i] != passer_team_id:
					if UtilityMath.is_lane_blocked(start_pos, end_pos, player_positions[i], corridor_width):
						return false
	return true


## Returns true if any opponent (not on `team`) sits within `clearance` px of the
## segment from `from_pos` to `to_pos`. Kept for backward compatibility; delegates
## directly to is_passing_lane_open. Allocation-free.
func is_lane_blocked_by_opponent(from_pos: Vector2, to_pos: Vector2, clearance: float, team: int) -> bool:
	return not is_passing_lane_open(from_pos, to_pos, team, clearance)


## Returns the minimum distance from any opponent (player not on `passer_team_id`)
## to the segment from `start_pos` to `end_pos`. Returns INF if no opponents exist.
## Allocation-free.
func get_passing_lane_min_distance(start_pos: Vector2, end_pos: Vector2, passer_team_id: int) -> float:
	var min_dist_sq: float = INF
	for i: int in range(TOTAL_PLAYERS):
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if player_teams[i] == passer_team_id:
			continue
		var d_sq: float = UtilityMath.distance_squared_to_segment(player_positions[i], start_pos, end_pos)
		if d_sq < min_dist_sq:
			min_dist_sq = d_sq
	return sqrt(min_dist_sq) if min_dist_sq < INF else INF


## Distance from `pos` to the closest registered player NOT on `team`.
## Checks local spatial grid cells first for O(1) early exit before falling back
## to a full roster check. Returns INF when no opponent is registered. Allocation-free.
func nearest_opponent_dist_to(pos: Vector2, team: int) -> float:
	var centre_cell: Vector2i = world_to_cell(pos)
	var best_dist_sq: float = INF

	# Search 3x3 local cells first (radius <= 160px from center cell)
	for cy: int in range(centre_cell.y - 1, centre_cell.y + 2):
		for cx: int in range(centre_cell.x - 1, centre_cell.x + 2):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				continue
			var bucket: Array[int] = _grid[cell]
			for i: int in bucket:
				if player_teams[i] != team:
					var d_sq: float = pos.distance_squared_to(player_positions[i])
					if d_sq < best_dist_sq:
						best_dist_sq = d_sq

	# If an opponent is within the safe 3x3 interior, return early without full scan.
	var min_outer_dist_x: float = minf(
		absf(pos.x - float(centre_cell.x - 1) * CELL_SIZE),
		absf(float(centre_cell.x + 2) * CELL_SIZE - pos.x)
	)
	var min_outer_dist_y: float = minf(
		absf(pos.y - float(centre_cell.y - 1) * CELL_SIZE),
		absf(float(centre_cell.y + 2) * CELL_SIZE - pos.y)
	)
	var min_outer_dist: float = minf(min_outer_dist_x, min_outer_dist_y)
	if best_dist_sq < min_outer_dist * min_outer_dist:
		return sqrt(best_dist_sq)

	var best_sq: float = best_dist_sq
	for i: int in range(TOTAL_PLAYERS):
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if player_teams[i] == team:
			continue
		var cand_d_sq: float = pos.distance_squared_to(player_positions[i])
		if cand_d_sq < best_sq:
			best_sq = cand_d_sq
	return sqrt(best_sq) if best_sq < INF else INF


## Position of the closest registered player NOT on `team`, or `pos` itself
## when no opponent is registered. Allocation-free — no Arrays or Dictionaries.
func nearest_opponent_position(pos: Vector2, team: int) -> Vector2:
	var best_dist_sq: float = INF
	var best_pos: Vector2 = pos
	for i: int in range(TOTAL_PLAYERS):
		if player_teams[i] == team:
			continue
		if not is_instance_valid(player_nodes[i]):
			continue
		var d_sq: float = pos.distance_squared_to(player_positions[i])
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_pos = player_positions[i]
	return best_pos


## True when `index` addresses a slot holding a live player.
func is_slot_live(index: int) -> bool:
	if index < 0 or index >= TOTAL_PLAYERS:
		return false
	var node: HeavyPlayerController = player_nodes[index]
	return node != null and is_instance_valid(node)


## Removes a sent-off player from the active cache so get_teammates_of() /
## get_opponents_of() / nearest_opponent_dist_to() no longer count them. The
## node is left in place (MatchReferee hides it, never frees it during a
## match) — only the cache slot is cleared, same shape as an unregistered slot.
func mark_player_unavailable(player: HeavyPlayerController) -> void:
	for i: int in range(TOTAL_PLAYERS):
		if player_nodes[i] == player:
			player_nodes[i] = null
			player_positions[i] = Vector2.ZERO
			player_velocities[i] = Vector2.ZERO
			if possessor_index == i:
				possessor_index = NO_INDEX
			return


func _resize_arrays() -> void:
	player_nodes.clear()
	player_nodes.resize(TOTAL_PLAYERS)
	player_positions.resize(TOTAL_PLAYERS)
	player_velocities.resize(TOTAL_PLAYERS)
	player_teams.resize(TOTAL_PLAYERS)

	for i: int in range(TOTAL_PLAYERS):
		player_nodes[i] = null
		player_positions[i] = Vector2.ZERO
		player_velocities[i] = Vector2.ZERO
		player_teams[i] = NO_INDEX


## --- Pressing trigger detection ----------------------------------------------

## Counts down an active trigger; a continuous trigger (everything except the
## two pass triggers, which are armed directly from _on_ball_struck()) is only
## ever evaluated once the previous one has fully expired. That single gate is
## what stops the system from re-reading a fast-changing situation every frame
## and flipping between contradictory trigger types.
func _update_press_trigger(delta: float) -> void:
	if _press_trigger_timer > 0.0:
		_press_trigger_timer = maxf(_press_trigger_timer - delta, 0.0)
		if _press_trigger_timer <= 0.0:
			_clear_press_trigger()
		return

	if _check_facing_own_goal_trigger():
		return
	if _check_touchline_isolation_trigger():
		return
	_check_heavy_touch_trigger()


func _arm_press_trigger(trigger: PressTrigger, carrier: HeavyPlayerController, position: Vector2, hold_seconds: float) -> void:
	press_trigger_active = true
	press_trigger_type = trigger
	press_trigger_carrier = carrier
	press_trigger_position = position
	_press_trigger_timer = hold_seconds
	GameEvents.press_trigger_changed.emit(true, int(trigger), carrier, position)


func _clear_press_trigger() -> void:
	if not press_trigger_active:
		return
	press_trigger_active = false
	press_trigger_type = PressTrigger.NONE
	press_trigger_carrier = null
	GameEvents.press_trigger_changed.emit(false, int(PressTrigger.NONE), null, Vector2.ZERO)


## Pass-direction trigger: BACKWARD_PASS or SQUARE_PASS. Fired straight off
## GameEvents.ball_struck rather than read as continuous state, since a pass
## is a discrete moment, not a condition that holds — apply_kick() has already
## committed ball_node.velocity by the time every ball_struck emitter (see
## ChargeKickState, DribbleState, ThrowInState) raises the signal, so the
## direction read here is the real, just-struck pass line.
## "Into pressure" is approximated as "an opponent is already near where the
## ball is heading" — a straight-line lookahead along the just-struck
## velocity, not a trajectory walk, and cheap: one nearest_opponent_dist_to()
## call reusing the same allocation-free primitive PlayerBrain's off-ball
## scoring already relies on.
func _on_ball_struck(struck_player: Node, _speed: float, _charge_ratio: float, is_shot: bool) -> void:
	if is_shot or ball_node == null or not is_instance_valid(ball_node):
		return
	var kicker: HeavyPlayerController = struck_player as HeavyPlayerController
	if kicker == null:
		return
	var travel: Vector2 = ball_node.velocity
	if travel.is_zero_approx():
		return

	# Team 0 attacks +X, team 1 attacks -X (see _update_defensive_lines()'s
	# identical convention).
	var attack_sign: float = 1.0 if kicker.team == 0 else -1.0
	var forward_dot: float = travel.normalized().dot(Vector2(attack_sign, 0.0))

	var trigger: PressTrigger = PressTrigger.NONE
	if forward_dot < -PASS_FORWARD_DOT_TOLERANCE:
		trigger = PressTrigger.BACKWARD_PASS
	elif forward_dot <= PASS_FORWARD_DOT_TOLERANCE:
		trigger = PressTrigger.SQUARE_PASS
	if trigger == PressTrigger.NONE:
		return

	var landing_point: Vector2 = ball_node.global_position + travel * PASS_PRESSURE_LOOKAHEAD_SECONDS
	if nearest_opponent_dist_to(landing_point, kicker.team) > CARRIER_PRESSURE_RADIUS:
		return  # Played away from any nearby opponent — not worth pressing for.

	_arm_press_trigger(trigger, kicker, landing_point, PRESS_TRIGGER_PASS_HOLD_SECONDS)


## FACING_OWN_GOAL: the current possessor's facing_dot toward a point deep in
## their own half clears FACING_OWN_GOAL_DOT_THRESHOLD. Read live off the node
## (get_facing_dot()) rather than from the position/velocity cache, same
## reasoning as PlayerBrain's own facing checks — facing lags velocity through
## a turn, which is exactly the moment this trigger cares about.
func _check_facing_own_goal_trigger() -> bool:
	if possessor_index == NO_INDEX:
		return false
	var carrier: HeavyPlayerController = player_nodes[possessor_index]
	if not is_instance_valid(carrier):
		return false

	var attack_sign: float = 1.0 if player_teams[possessor_index] == 0 else -1.0
	var own_half_probe: Vector2 = player_positions[possessor_index] + Vector2(-attack_sign * 500.0, 0.0)
	if carrier.get_facing_dot(own_half_probe) < FACING_OWN_GOAL_DOT_THRESHOLD:
		return false

	_arm_press_trigger(PressTrigger.FACING_OWN_GOAL, carrier, carrier.global_position, PRESS_TRIGGER_HOLD_SECONDS)
	return true


## TOUCHLINE_ISOLATION: the current possessor is within TOUCHLINE_MARGIN of
## either touchline and has no teammate within ISOLATION_SUPPORT_RADIUS.
## No-ops (returns false) whenever bind_boundary() was never called.
func _check_touchline_isolation_trigger() -> bool:
	if possessor_index == NO_INDEX or _boundary == null or not is_instance_valid(_boundary):
		return false
	var carrier: HeavyPlayerController = player_nodes[possessor_index]
	if not is_instance_valid(carrier):
		return false

	var pos: Vector2 = player_positions[possessor_index]
	var rect: Rect2 = _boundary.get_pitch_rect()
	var near_touchline: bool = pos.y < rect.position.y + TOUCHLINE_MARGIN \
		or pos.y > rect.end.y - TOUCHLINE_MARGIN
	if not near_touchline:
		return false

	var team: int = player_teams[possessor_index]
	if count_nearby_teammates(pos, ISOLATION_SUPPORT_RADIUS, team, possessor_index) > 0:
		return false

	_arm_press_trigger(PressTrigger.TOUCHLINE_ISOLATION, carrier, carrier.global_position, PRESS_TRIGGER_HOLD_SECONDS)
	return true


## HEAVY_TOUCH: the ball is loose (no possessor), its last toucher is still
## the closest thing to "whose ball this is", and it has drifted a heavy-touch
## distance away from their feet with an opponent already close enough to
## pounce. A ball that has merely rolled a normal dribble-touch distance, or
## drifted with no opponent anywhere near it, does not count.
func _check_heavy_touch_trigger() -> bool:
	if possessor_index != NO_INDEX or ball_node == null or not is_instance_valid(ball_node):
		return false
	var toucher: HeavyPlayerController = ball_node.last_touched_by
	if not is_instance_valid(toucher):
		return false

	var toucher_index: int = NO_INDEX
	for i: int in range(TOTAL_PLAYERS):
		if player_nodes[i] == toucher:
			toucher_index = i
			break
	if toucher_index == NO_INDEX:
		return false

	var dist_sq: float = ball_position.distance_squared_to(player_positions[toucher_index])
	if dist_sq < HEAVY_TOUCH_MIN_DIST * HEAVY_TOUCH_MIN_DIST or dist_sq > HEAVY_TOUCH_MAX_DIST * HEAVY_TOUCH_MAX_DIST:
		return false
	if nearest_opponent_dist_to(ball_position, player_teams[toucher_index]) > CARRIER_PRESSURE_RADIUS:
		return false

	_arm_press_trigger(PressTrigger.HEAVY_TOUCH, toucher, ball_position, PRESS_TRIGGER_HOLD_SECONDS)
	return true
