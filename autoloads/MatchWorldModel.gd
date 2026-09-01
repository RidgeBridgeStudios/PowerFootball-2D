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
##          team_urgency/team_momentum/current_match_stage — macro match
##          architecture cache, written from GameEvents.team_urgency_updated /
##          team_momentum_updated / match_stage_changed; get_pitch_centre_x()
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

## --- Tactical Pitch Control Grid (12x8) ---
const TACTICAL_GRID_WIDTH: int = 12
const TACTICAL_GRID_HEIGHT: int = 8
const TACTICAL_CELL_W: float = 106.6666
const TACTICAL_CELL_H: float = 90.0
const TACTICAL_GRID_CELLS: int = 96
const TACTICAL_OFFSET_X: float = 640.0
const TACTICAL_OFFSET_Y: float = 360.0

var p_pos_x: PackedFloat32Array = PackedFloat32Array()
var p_pos_y: PackedFloat32Array = PackedFloat32Array()
var p_vel_x: PackedFloat32Array = PackedFloat32Array()
var p_vel_y: PackedFloat32Array = PackedFloat32Array()
var grid_home: PackedInt32Array = PackedInt32Array()
var grid_away: PackedInt32Array = PackedInt32Array()
var grid_dominant: PackedInt32Array = PackedInt32Array()


## --- Ball cache -------------------------------------------------------------

var ball_node: Pseudo3DBall = null
var ball_position: Vector2 = Vector2.ZERO
var ball_velocity: Vector2 = Vector2.ZERO
## Index into player_nodes of whoever currently has the ball, or NO_INDEX.
## Resolved from Pseudo3DBall.possessor, falling back to last_touched_by.
var possessor_index: int = NO_INDEX
var _turnover_predicted: bool = false

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

## --- Macro match architecture cache (urgency, momentum, stage) --------------
## Per-team [TEAM_A, TEAM_B] scalars written by the GameEvents listeners below
## in response to ManagerDirector (urgency) and MatchStatsTracker (momentum)
## publishing on GameEvents — this node never computes either value itself,
## it only caches the latest broadcast so hot-path readers (PlayerBrain,
## PassUtilityScorer/FormationAnchorMath call sites) never touch a signal
## connection or re-derive the math per decision tick. Both ranges are
## [-1.0, 1.0]; positive urgency/momentum favours attacking risk, negative
## favours safety/preservation.
var team_urgency: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var team_momentum: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Plain int mirror of GameManager.MatchStage, kept as int (not the enum type)
## so this file does not need to reference GameManager's type at parse time —
## GameManager loads AFTER this autoload in project.godot's boot order (see
## class doc "Depends on:"). GameManager is the source of truth; this is a
## read-only cache updated via GameEvents.match_stage_changed.
var current_match_stage: int = 0

## --- Sacchi Compactness Cache ---
var team_com_x: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var team_att_x: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var team_def_x: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])


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

const GRID_WIDTH: int = 24
const GRID_HEIGHT: int = 16
const GRID_OFFSET_X: float = 1920.0
const GRID_OFFSET_Y: float = 1280.0

var _grid: Array[Array] = []
var _active_cells: Array[int] = []

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
	PROLONGED_POSSESSION = 6, ## Same possessor has held the ball continuously past a time threshold with no other trigger firing.
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

## Seconds the same possessor may hold the ball uninterrupted, with none of
## the other trigger heuristics firing, before PROLONGED_POSSESSION forces a
## press anyway. Backstop against an indefinite stand-off when a carrier is
## calm enough (facing forward, mid-pitch, soft first touch) to never trip
## FACING_OWN_GOAL / TOUCHLINE_ISOLATION / HEAVY_TOUCH on their own.
const PROLONGED_POSSESSION_SECONDS: float = 2.5

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

## Seconds the current possessor_index has held the ball uninterrupted. Reset
## to zero whenever possessor_index changes (including to/from NO_INDEX);
## feeds _check_prolonged_possession_trigger().
var _possession_hold_timer: float = 0.0
var _possession_hold_index: int = NO_INDEX

## Stall watchdog: automatic, zero-setup diagnostic for the "loose ball sits
## unclaimed" class of bug. Fires exactly once per stall episode — no manual
## Remote-tree flag toggling required. See _update_stall_watchdog().
const STALL_TRACE_THRESHOLD_SECONDS: float = 2.0
const STALL_SPEED_EPSILON: float = 15.0
var _stall_timer: float = 0.0
var _stall_traced: bool = false

## Possession watchdog: automatic diagnostic for "one player holds the ball
## and never does anything with it." Tracks ball_node.possessor directly
## (the true active carrier — DribbleState/TackleState, per soccer-physics.md
## — not the last_touched_by fallback _possession_hold_timer above also
## counts, which would keep this firing after the ball had already gone
## loose). Once the SAME active possessor has held continuously past this
## threshold, fires a repeating (not one-shot) [ActionScorer] trace on them
## every POSSESSION_TRACE_INTERVAL_SECONDS, building a time-series log of
## exactly what that player's brain is deciding and steering toward for as
## long as the possession episode lasts. See _update_possession_watchdog().
const POSSESSION_TRACE_THRESHOLD_SECONDS: float = 1.5
const POSSESSION_TRACE_INTERVAL_SECONDS: float = 0.5
var _active_possession_node: Node2D = null
var _active_possession_timer: float = 0.0
var _possession_trace_timer: float = 0.0

## Bound by PitchScene alongside PlayerBrain.bind_boundary() (see
## _bind_players()). Optional — left null in any setup that never calls
## bind_boundary(), in which case TOUCHLINE_ISOLATION alone never fires.
var _boundary: PitchBoundary = null

## Spacing/crowding diagnostics: opt-in instrumentation for the "crowding,
## no space creation" investigation (see AGENTS_ERRATA.md:
## crowding-space-creation-diagnostics). Disabled by default so normal play
## pays zero cost. Flip this true (Remote tab, or edit the default below),
## let a CPU-vs-CPU match run, and read the Godot Output panel:
## [SpacingReport] prints every SPACING_REPORT_INTERVAL_SECONDS with the
## current window's numbers; [SpacingSummary] prints once at full time with
## match-long averages. See _update_spacing_diagnostics()/_print_spacing_
## summary() below and PlayerBrain.evaluate_tactical_action()'s
## record_decision() call for how the action-tally half is fed.
@export var debug_spacing_diagnostics: bool = true

const SPACING_REPORT_INTERVAL_SECONDS: float = 15.0
## Physics frames between spatial samples (~10/sec at 60fps) — the O(11²)
## nearest-teammate scan per team is cheap, but there is no reason to pay it
## every single physics frame just to average it away a moment later.
const SPACING_SAMPLE_STRIDE: int = 6
## Same-team players within this radius of the ball count as "clumped" on it.
const SPACING_CLUMP_RADIUS: float = 100.0

## action index <-> DecisionAction, and role index <-> PlayerBrain.Role
## (OUTFIELD_ATTACKER=0, OUTFIELD_MIDFIELDER=1, OUTFIELD_DEFENDER=2,
## GOALKEEPER=3 — never actually recorded since evaluate_tactical_action()
## returns for goalkeepers before reaching record_decision()'s call site).
enum DecisionAction { MAINTAIN_FORMATION, PANIC_CLEAR, PASS, CHASE_BALL, FIND_SPACE, ATTEMPT_DRIBBLE, ATTEMPT_SHOOT, UNKNOWN }
const ACTION_COUNT: int = 8
const ROLE_COUNT: int = 4

var _spacing_report_timer: float = 0.0
var _spacing_sample_frame_counter: int = 0
var _spacing_window_samples: int = 0
var _spacing_total_samples: int = 0

# Parallel per-team ([team 0, team 1]) running sums — window resets every
# report, total accumulates for the full-time summary. Mirrors the existing
# team_com_x/team_att_x/team_def_x parallel-array convention above.
var _window_nearest_sum: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _total_nearest_sum: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _window_width_sum: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _total_width_sum: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _window_length_sum: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _total_length_sum: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _window_clump_sum: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _total_clump_sum: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])

var _match_worst_nearest_dist: PackedFloat32Array = PackedFloat32Array([INF, INF])
var _match_worst_pair_a: Array[int] = [NO_INDEX, NO_INDEX]
var _match_worst_pair_b: Array[int] = [NO_INDEX, NO_INDEX]

# Decision tally, flattened as team * ACTION_COUNT + action / team * ROLE_COUNT + role.
var _action_tally: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _possessor_ticks_total: PackedInt32Array = PackedInt32Array([0, 0])
var _possessor_pass_available_ticks: PackedInt32Array = PackedInt32Array([0, 0])
var _role_offball_ticks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
var _role_findspace_ticks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])

## Deferred to the first _physics_process() rather than connected in
## _ready(): this autoload is deliberately declared first in project.godot
## (see class doc "Depends on:") so nothing else has to load before it, which
## means GameEvents does not exist yet when this node's own _ready() runs.
## By the first physics frame every autoload is guaranteed ready.
var _deferred_events_connected: bool = false


func _enter_tree() -> void:
	instance = self
	_grid.resize(GRID_WIDTH * GRID_HEIGHT)
	for i: int in range(GRID_WIDTH * GRID_HEIGHT):
		_grid[i] = [] as Array[int]
	_resize_arrays()
	p_pos_x.resize(TOTAL_PLAYERS)
	p_pos_y.resize(TOTAL_PLAYERS)
	p_vel_x.resize(TOTAL_PLAYERS)
	p_vel_y.resize(TOTAL_PLAYERS)
	grid_home.resize(TACTICAL_GRID_CELLS)
	grid_away.resize(TACTICAL_GRID_CELLS)
	grid_dominant.resize(TACTICAL_GRID_CELLS)



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
	team_urgency[0] = 0.0
	team_urgency[1] = 0.0
	team_momentum[0] = 0.0
	team_momentum[1] = 0.0
	current_match_stage = 0
	team_com_x[0] = 0.0
	team_com_x[1] = 0.0
	team_att_x[0] = 0.0
	team_att_x[1] = 0.0
	team_def_x[0] = 0.0
	team_def_x[1] = 0.0

	_clear_press_trigger()
	_press_trigger_timer = 0.0
	_boundary = null
	for cell_idx: int in range(GRID_WIDTH * GRID_HEIGHT):
		var bucket: Array = _grid[cell_idx]
		bucket.clear()
	_active_cells.clear()
	for i: int in range(TACTICAL_GRID_CELLS):
		grid_home[i] = 0
		grid_away[i] = 0
		grid_dominant[i] = -1
	_nearby_players_scratch.clear()
	_nearby_opponents_scratch.clear()
	_nearby_teammates_scratch.clear()
	_nearby_nodes2d_scratch.clear()
	_resize_arrays()


## --- Per-frame refresh ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _deferred_events_connected:
		GameEvents.ball_struck.connect(_on_ball_struck)
		GameEvents.team_urgency_updated.connect(_on_team_urgency_updated)
		GameEvents.team_momentum_updated.connect(_on_team_momentum_updated)
		GameEvents.match_stage_changed.connect(_on_match_stage_changed)
		GameEvents.match_phase_changed.connect(_on_match_phase_changed_for_diagnostics)
		_deferred_events_connected = true

	if ball_node != null and is_instance_valid(ball_node):
		ball_position = ball_node.global_position
		ball_velocity = ball_node.velocity

	possessor_index = _resolve_possessor_index()

	if possessor_index != _possession_hold_index:
		_possession_hold_index = possessor_index
		_possession_hold_timer = 0.0
	elif possessor_index != NO_INDEX:
		_possession_hold_timer += delta

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
		_turnover_predicted = false

	for i: int in range(TOTAL_PLAYERS):
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		player_positions[i] = node.global_position
		player_velocities[i] = node.velocity
		p_pos_x[i] = player_positions[i].x
		p_pos_y[i] = player_positions[i].y
		p_vel_x[i] = player_velocities[i].x
		p_vel_y[i] = player_velocities[i].y

	_update_spatial_grid()
	_update_tactical_grid()
	_update_defensive_lines(delta)
	for t: int in range(2):
		var count: float = 0.0
		var sum_x: float = 0.0
		var min_x: float = INF
		var max_x: float = -INF
		for i: int in range(TOTAL_PLAYERS):
			if player_teams[i] == t:
				var px: float = p_pos_x[i]
				sum_x += px
				count += 1.0
				if px < min_x:
					min_x = px
				if px > max_x:
					max_x = px
		if count > 0.0:
			team_com_x[t] = sum_x / count
			team_att_x[t] = max_x if t == 0 else min_x
			team_def_x[t] = min_x if t == 0 else max_x

	_update_press_trigger(delta)
	_update_stall_watchdog(delta)
	_update_possession_watchdog(delta)
	_update_spacing_diagnostics(delta)


## Converts a 2D world position into discrete spatial grid cell coordinates.
func world_to_cell(world_pos: Vector2) -> Vector2i:
	var cx: int = clampi(int((world_pos.x + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var cy: int = clampi(int((world_pos.y + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	return Vector2i(cx, cy)


## Refreshes the spatial partition grid. Reuses cell bucket arrays to achieve
## zero heap allocations per physics frame.
func _update_spatial_grid() -> void:
	for cell_idx: int in _active_cells:
		var clear_bucket: Array = _grid[cell_idx]
		clear_bucket.clear()
	_active_cells.clear()

	for i: int in range(TOTAL_PLAYERS):
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		var cx: int = clampi(int((player_positions[i].x + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
		var cy: int = clampi(int((player_positions[i].y + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
		var cell_idx: int = cy * GRID_WIDTH + cx
		var bucket: Array = _grid[cell_idx]
		if bucket.is_empty():
			_active_cells.append(cell_idx)
		bucket.append(i)


## Bound by PitchScene at match setup, mirroring PlayerBrain.bind_boundary().
## Only the touchline-isolation trigger reads this; every other trigger works
## without it.
func bind_boundary(b: PitchBoundary) -> void:
	_boundary = b


## World-space X of the pitch centre, or 0.0 if bind_boundary() was never
## called (e.g. Practice Arena). Lets a caller (MatchStatsTracker's opponent-
## half check, for instance) answer "which half is this position in" without
## holding its own PitchBoundary reference.
func get_pitch_centre_x() -> float:
	return _boundary.get_centre_spot().x if _boundary != null else 0.0


func _on_team_urgency_updated(team: int, urgency: float) -> void:
	if team == 0 or team == 1:
		team_urgency[team] = urgency


func _on_team_momentum_updated(team: int, momentum: float) -> void:
	if team == 0 or team == 1:
		team_momentum[team] = momentum


func _on_match_stage_changed(stage: int) -> void:
	current_match_stage = stage


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
	var min_cx: int = clampi(int((pos.x - radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((pos.x + radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((pos.y - radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((pos.y + radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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
	var min_cx: int = clampi(int((pos.x - radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((pos.x + radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((pos.y - radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((pos.y + radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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
	var min_cx: int = clampi(int((pos.x - radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((pos.x + radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((pos.y - radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((pos.y + radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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
	var min_cx: int = clampi(int((pos.x - radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((pos.x + radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((pos.y - radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((pos.y + radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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
	var min_cx: int = clampi(int((pos.x - radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((pos.x + radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((pos.y - radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((pos.y + radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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
	var min_cx: int = clampi(int((pos.x - radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((pos.x + radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((pos.y - radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((pos.y + radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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
	var min_cx: int = clampi(int((pos.x - radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((pos.x + radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((pos.y - radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((pos.y + radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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
	var min_cx: int = clampi(int((pos.x - radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((pos.x + radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((pos.y - radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((pos.y + radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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
	var min_cx: int = clampi(int((pos.x - radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((pos.x + radius + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((pos.y - radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((pos.y + radius + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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
	var min_x: float = minf(start_pos.x, end_pos.x) - corridor_width
	var max_x: float = maxf(start_pos.x, end_pos.x) + corridor_width
	var min_y: float = minf(start_pos.y, end_pos.y) - corridor_width
	var max_y: float = maxf(start_pos.y, end_pos.y) + corridor_width

	var min_cx: int = clampi(int((min_x + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((max_x + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((min_y + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((max_y + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
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

	var min_x: float = minf(start_pos.x, end_pos.x) - 160.0
	var max_x: float = maxf(start_pos.x, end_pos.x) + 160.0
	var min_y: float = minf(start_pos.y, end_pos.y) - 160.0
	var max_y: float = maxf(start_pos.y, end_pos.y) + 160.0

	var min_cx: int = clampi(int((min_x + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(int((max_x + GRID_OFFSET_X) * INV_CELL_SIZE), 0, GRID_WIDTH - 1)
	var min_cy: int = clampi(int((min_y + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(int((max_y + GRID_OFFSET_Y) * INV_CELL_SIZE), 0, GRID_HEIGHT - 1)

	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
			for i: int in bucket:
				if player_teams[i] != passer_team_id:
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

	var min_cy: int = clampi(centre_cell.y - 1, 0, GRID_HEIGHT - 1)
	var max_cy: int = clampi(centre_cell.y + 1, 0, GRID_HEIGHT - 1)
	var min_cx: int = clampi(centre_cell.x - 1, 0, GRID_WIDTH - 1)
	var max_cx: int = clampi(centre_cell.x + 1, 0, GRID_WIDTH - 1)

	# Search 3x3 local cells first (radius <= 160px from center cell)
	for cy: int in range(min_cy, max_cy + 1):
		var row_offset: int = cy * GRID_WIDTH
		for cx: int in range(min_cx, max_cx + 1):
			var bucket: Array = _grid[row_offset + cx]
			for i: int in bucket:
				if player_teams[i] != team:
					var d_sq: float = pos.distance_squared_to(player_positions[i])
					if d_sq < best_dist_sq:
						best_dist_sq = d_sq

	var centre_cell_world_x: float = float(centre_cell.x) * CELL_SIZE - GRID_OFFSET_X
	var centre_cell_world_y: float = float(centre_cell.y) * CELL_SIZE - GRID_OFFSET_Y

	# If an opponent is within the safe 3x3 interior, return early without full scan.
	var min_outer_dist_x: float = minf(
		absf(pos.x - (centre_cell_world_x - CELL_SIZE)),
		absf((centre_cell_world_x + CELL_SIZE * 2.0) - pos.x)
	)
	var min_outer_dist_y: float = minf(
		absf(pos.y - (centre_cell_world_y - CELL_SIZE)),
		absf((centre_cell_world_y + CELL_SIZE * 2.0) - pos.y)
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
	if _check_heavy_touch_trigger():
		return
	_check_prolonged_possession_trigger()


## Automatic, zero-setup diagnostic for the "loose ball sits unclaimed, no
## one acts on it" class of bug. Tracks how long the ball has been both
## unpossessed and near-stationary; once that exceeds
## STALL_TRACE_THRESHOLD_SECONDS, arms exactly one [ActionScorer] trace on
## whichever live player is currently closest to the ball, then latches so it
## never fires again for the same stall episode (only resets once the ball
## moves or gets possessed again). No Remote-tree flag toggling required —
## the trace appears in Output on its own the next time this freezes.
func _update_stall_watchdog(delta: float) -> void:
	if ball_node == null or not is_instance_valid(ball_node):
		_stall_timer = 0.0
		_stall_traced = false
		return

	var is_loose: bool = ball_node.possessor == null
	var is_slow: bool = ball_node.velocity.length() < STALL_SPEED_EPSILON

	if not (is_loose and is_slow):
		_stall_timer = 0.0
		_stall_traced = false
		return

	_stall_timer += delta
	if _stall_timer < STALL_TRACE_THRESHOLD_SECONDS or _stall_traced:
		return

	_stall_traced = true

	var closest_idx: int = -1
	var closest_dist_sq: float = INF
	for i: int in range(TOTAL_PLAYERS):
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		var d: float = player_positions[i].distance_squared_to(ball_position)
		if d < closest_dist_sq:
			closest_dist_sq = d
			closest_idx = i

	if closest_idx == -1:
		return

	var closest_node: HeavyPlayerController = player_nodes[closest_idx]
	print("[StallWatchdog] Ball stalled %.1fs at %s (velocity=%.1f px/s). Closest player: %s (team %d, %.1fpx away). Forcing one [ActionScorer] trace on that player's next decision tick." % [
		_stall_timer, ball_position, ball_node.velocity.length(),
		closest_node.name, player_teams[closest_idx], sqrt(closest_dist_sq)])

	var brain := closest_node.get_node_or_null("PlayerBrain") as PlayerBrain
	if brain != null:
		brain.trace_next_decision()


## Automatic diagnostic for "one player holds the ball and jogs around never
## passing/shooting/dribbling with purpose." Unlike _update_stall_watchdog()
## (one-shot, fires on a STATIONARY loose ball), this repeats for as long as
## the SAME player keeps active possession, producing a time-series log via
## repeated [ActionScorer] traces — exactly what's needed to see a decision
## flip-flopping or staying stuck over several seconds, not just a single
## snapshot. No Remote-tree flag toggling required.
func _update_possession_watchdog(delta: float) -> void:
	if ball_node == null or not is_instance_valid(ball_node):
		_active_possession_node = null
		_active_possession_timer = 0.0
		_possession_trace_timer = 0.0
		return

	var holder: Node2D = ball_node.possessor
	if holder != _active_possession_node:
		_active_possession_node = holder
		_active_possession_timer = 0.0
		_possession_trace_timer = 0.0

	if holder == null:
		return

	_active_possession_timer += delta
	if _active_possession_timer < POSSESSION_TRACE_THRESHOLD_SECONDS:
		return

	_possession_trace_timer -= delta
	if _possession_trace_timer > 0.0:
		return
	_possession_trace_timer = POSSESSION_TRACE_INTERVAL_SECONDS

	var holder_controller := holder as HeavyPlayerController
	if holder_controller == null:
		return
	var brain := holder_controller.get_node_or_null("PlayerBrain") as PlayerBrain
	if brain != null:
		brain.trace_next_decision()


## --- Spacing / crowding diagnostics ---------------------------------------
## Opt-in instrumentation for the "crowding, no space creation" investigation.
## See debug_spacing_diagnostics above for how to turn it on and what to read.

func _update_spacing_diagnostics(delta: float) -> void:
	if not debug_spacing_diagnostics:
		return
	_spacing_report_timer += delta
	_spacing_sample_frame_counter += 1
	if _spacing_sample_frame_counter >= SPACING_SAMPLE_STRIDE:
		_spacing_sample_frame_counter = 0
		_accumulate_spacing_sample()
	if _spacing_report_timer >= SPACING_REPORT_INTERVAL_SECONDS:
		_spacing_report_timer = 0.0
		_print_spacing_report()


## One spatial sample: per team, the average distance from each player to
## their single nearest teammate (the "crowding index" — low means players
## are stacked on top of each other), the team's on-pitch bounding box
## (width/length — "is the pitch actually being used"), and how many
## teammates are within SPACING_CLUMP_RADIUS of the ball right now. Feeds
## both the window (periodic report) and total (full-time summary) sums.
## O(TOTAL_PLAYERS^2), but only runs every SPACING_SAMPLE_STRIDE frames and
## only while debug_spacing_diagnostics is on — never in the default path.
func _accumulate_spacing_sample() -> void:
	_spacing_window_samples += 1
	_spacing_total_samples += 1

	for t: int in range(2):
		var min_x: float = INF
		var max_x: float = -INF
		var min_y: float = INF
		var max_y: float = -INF
		var nearest_sum: float = 0.0
		var nearest_count: int = 0
		var clump_count: int = 0

		for i: int in range(TOTAL_PLAYERS):
			if player_teams[i] != t:
				continue
			var px: float = p_pos_x[i]
			var py: float = p_pos_y[i]
			min_x = minf(min_x, px)
			max_x = maxf(max_x, px)
			min_y = minf(min_y, py)
			max_y = maxf(max_y, py)

			var best_d_sq: float = INF
			var best_j: int = NO_INDEX
			for j: int in range(TOTAL_PLAYERS):
				if j == i or player_teams[j] != t:
					continue
				var d_sq: float = Vector2(px - p_pos_x[j], py - p_pos_y[j]).length_squared()
				if d_sq < best_d_sq:
					best_d_sq = d_sq
					best_j = j
			if best_j != NO_INDEX:
				var d: float = sqrt(best_d_sq)
				nearest_sum += d
				nearest_count += 1
				if d < _match_worst_nearest_dist[t]:
					_match_worst_nearest_dist[t] = d
					_match_worst_pair_a[t] = i
					_match_worst_pair_b[t] = best_j

			if ball_node != null and is_instance_valid(ball_node):
				var to_ball_sq: float = Vector2(px - ball_position.x, py - ball_position.y).length_squared()
				if to_ball_sq <= SPACING_CLUMP_RADIUS * SPACING_CLUMP_RADIUS:
					clump_count += 1

		var avg_nearest: float = (nearest_sum / float(nearest_count)) if nearest_count > 0 else 0.0
		var width: float = (max_y - min_y) if max_y > min_y else 0.0
		var length: float = (max_x - min_x) if max_x > min_x else 0.0

		_window_nearest_sum[t] += avg_nearest
		_total_nearest_sum[t] += avg_nearest
		_window_width_sum[t] += width
		_total_width_sum[t] += width
		_window_length_sum[t] += length
		_total_length_sum[t] += length
		_window_clump_sum[t] += float(clump_count)
		_total_clump_sum[t] += float(clump_count)


func _print_spacing_report() -> void:
	if _spacing_window_samples == 0:
		return
	var n: float = float(_spacing_window_samples)
	var pitch_w: float = _boundary.pitch_size.y if _boundary != null else 0.0
	var pitch_l: float = _boundary.pitch_size.x if _boundary != null else 0.0

	for t: int in range(2):
		var avg_nearest: float = _window_nearest_sum[t] / n
		var avg_width: float = _window_width_sum[t] / n
		var avg_length: float = _window_length_sum[t] / n
		var avg_clump: float = _window_clump_sum[t] / n
		var width_pct: float = (avg_width / pitch_w * 100.0) if pitch_w > 0.0 else -1.0
		var length_pct: float = (avg_length / pitch_l * 100.0) if pitch_l > 0.0 else -1.0
		print("[SpacingReport] team=%d avg_nearest_teammate=%.1fpx width=%.0fpx(%.0f%%) length=%.0fpx(%.0f%%) avg_players_within_%.0fpx_of_ball=%.2f" % [
			t, avg_nearest, avg_width, width_pct, avg_length, length_pct, SPACING_CLUMP_RADIUS, avg_clump])

	_window_nearest_sum[0] = 0.0
	_window_nearest_sum[1] = 0.0
	_window_width_sum[0] = 0.0
	_window_width_sum[1] = 0.0
	_window_length_sum[0] = 0.0
	_window_length_sum[1] = 0.0
	_window_clump_sum[0] = 0.0
	_window_clump_sum[1] = 0.0
	_spacing_window_samples = 0


func _action_tally_index(action: StringName) -> int:
	match action:
		&"MaintainFormation": return DecisionAction.MAINTAIN_FORMATION
		&"PanicClear": return DecisionAction.PANIC_CLEAR
		&"Pass": return DecisionAction.PASS
		&"ChaseBall": return DecisionAction.CHASE_BALL
		&"FindSpace": return DecisionAction.FIND_SPACE
		&"AttemptDribble": return DecisionAction.ATTEMPT_DRIBBLE
		&"AttemptShoot": return DecisionAction.ATTEMPT_SHOOT
		_: return DecisionAction.UNKNOWN


func _action_tally_label(idx: int) -> String:
	match idx:
		DecisionAction.MAINTAIN_FORMATION: return "MaintainFormation"
		DecisionAction.PANIC_CLEAR: return "PanicClear"
		DecisionAction.PASS: return "Pass"
		DecisionAction.CHASE_BALL: return "ChaseBall"
		DecisionAction.FIND_SPACE: return "FindSpace"
		DecisionAction.ATTEMPT_DRIBBLE: return "AttemptDribble"
		DecisionAction.ATTEMPT_SHOOT: return "AttemptShoot"
		_: return "Unknown"


func _role_label(r: int) -> String:
	match r:
		0: return "ATT"
		1: return "MID"
		2: return "DEF"
		_: return "GK"


## Called once per outfield decision tick from
## PlayerBrain.evaluate_tactical_action() when debug_spacing_diagnostics is
## on. Cheap counter increments only — no allocation — so the cost is opt-in
## and negligible even across all 22 players' staggered decision ticks.
func record_decision(team: int, role: int, action: StringName, is_possessor: bool, open_teammate_exists: bool) -> void:
	if not debug_spacing_diagnostics or team < 0 or team > 1:
		return

	_action_tally[team * ACTION_COUNT + _action_tally_index(action)] += 1

	if is_possessor:
		_possessor_ticks_total[team] += 1
		if open_teammate_exists:
			_possessor_pass_available_ticks[team] += 1
	elif role >= 0 and role < ROLE_COUNT:
		_role_offball_ticks[team * ROLE_COUNT + role] += 1
		if action == &"FindSpace":
			_role_findspace_ticks[team * ROLE_COUNT + role] += 1


func _on_match_phase_changed_for_diagnostics(phase: int) -> void:
	if debug_spacing_diagnostics and phase == GameManager.MatchPhase.FULL_TIME:
		_print_spacing_summary()


## Match-long aggregate — read this one at full time for the actual verdict
## rather than eyeballing the periodic [SpacingReport] windows individually.
func _print_spacing_summary() -> void:
	print("[SpacingSummary] ==== Crowding / space-creation report (%d spatial samples) ====" % _spacing_total_samples)

	var pitch_w: float = _boundary.pitch_size.y if _boundary != null else 0.0
	var pitch_l: float = _boundary.pitch_size.x if _boundary != null else 0.0
	var n: float = maxf(float(_spacing_total_samples), 1.0)

	for t: int in range(2):
		var avg_nearest: float = _total_nearest_sum[t] / n
		var avg_width: float = _total_width_sum[t] / n
		var avg_length: float = _total_length_sum[t] / n
		var avg_clump: float = _total_clump_sum[t] / n
		var width_pct: float = (avg_width / pitch_w * 100.0) if pitch_w > 0.0 else -1.0
		var length_pct: float = (avg_length / pitch_l * 100.0) if pitch_l > 0.0 else -1.0

		var worst_a_name: String = "?"
		var worst_b_name: String = "?"
		if _match_worst_pair_a[t] != NO_INDEX and is_instance_valid(player_nodes[_match_worst_pair_a[t]]):
			worst_a_name = player_nodes[_match_worst_pair_a[t]].name
		if _match_worst_pair_b[t] != NO_INDEX and is_instance_valid(player_nodes[_match_worst_pair_b[t]]):
			worst_b_name = player_nodes[_match_worst_pair_b[t]].name

		print("[SpacingSummary] team=%d avg_nearest_teammate=%.1fpx width_used=%.0f%% length_used=%.0f%% avg_players_within_%.0fpx_of_ball=%.2f worst_clump=%.1fpx(%s<->%s)" % [
			t, avg_nearest, width_pct, length_pct, SPACING_CLUMP_RADIUS, avg_clump,
			_match_worst_nearest_dist[t], worst_a_name, worst_b_name])

		var poss_total: int = _possessor_ticks_total[t]
		var poss_pct: float = (float(_possessor_pass_available_ticks[t]) / float(poss_total) * 100.0) if poss_total > 0 else -1.0
		print("[SpacingSummary] team=%d possessor_had_open_teammate=%.1f%% (%d/%d possessor decision ticks)" % [
			t, poss_pct, _possessor_pass_available_ticks[t], poss_total])

		for r: int in range(3):
			var off_total: int = _role_offball_ticks[t * ROLE_COUNT + r]
			var fs_count: int = _role_findspace_ticks[t * ROLE_COUNT + r]
			var fs_pct: float = (float(fs_count) / float(off_total) * 100.0) if off_total > 0 else -1.0
			print("[SpacingSummary] team=%d role=%s FindSpace_rate=%.1f%% (%d/%d off-ball decision ticks)" % [
				t, _role_label(r), fs_pct, fs_count, off_total])

		var action_line: String = "[SpacingSummary] team=%d action_distribution:" % t
		var team_action_total: int = 0
		for a: int in range(ACTION_COUNT):
			team_action_total += _action_tally[t * ACTION_COUNT + a]
		for a: int in range(ACTION_COUNT):
			var count: int = _action_tally[t * ACTION_COUNT + a]
			if count == 0:
				continue
			var pct: float = (float(count) / float(team_action_total) * 100.0) if team_action_total > 0 else 0.0
			action_line += " %s=%.1f%%" % [_action_tally_label(a), pct]
		print(action_line)


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
	elif _speed < 200.0: # slow pass or airborne pass
		trigger = PressTrigger.BACKWARD_PASS # reusing trigger type since it just activates press
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


## PROLONGED_POSSESSION: backstop trigger. Fires once the same possessor has
## held the ball continuously for PROLONGED_POSSESSION_SECONDS with none of
## the other three trigger heuristics ever catching them — e.g. a carrier who
## calmly holds/dribbles mid-pitch facing forward, never pinned to a
## touchline and never taking a heavy touch. Without this, _should_chase_ball()
## / clamp_chase_target() (PlayerBrain.gd) never lift the anchor-distance
## clamp for the pressing team, and the whole side reforms shape instead of
## ever closing the carrier down — an indefinite stand-off.
func _check_prolonged_possession_trigger() -> bool:
	if possessor_index == NO_INDEX:
		return false
	if _possession_hold_timer < PROLONGED_POSSESSION_SECONDS:
		return false
	var carrier: HeavyPlayerController = player_nodes[possessor_index]
	if not is_instance_valid(carrier):
		return false

	_arm_press_trigger(PressTrigger.PROLONGED_POSSESSION, carrier, carrier.global_position, PRESS_TRIGGER_HOLD_SECONDS)
	return true


func _update_tactical_grid() -> void:
	for i: int in range(TACTICAL_GRID_CELLS):
		grid_home[i] = 0
		grid_away[i] = 0
		grid_dominant[i] = -1

	var I_BASE: int = 1000
	var K_D: int = 300
	var K_V: int = 150

	for i: int in range(TOTAL_PLAYERS):
		if player_teams[i] != 0 and player_teams[i] != 1:
			continue
		
		var px: float = p_pos_x[i]
		var py: float = p_pos_y[i]
		var vx: float = p_vel_x[i]
		var vy: float = p_vel_y[i]
		
		var cx: int = clampi(int((px + TACTICAL_OFFSET_X) / TACTICAL_CELL_W), 0, TACTICAL_GRID_WIDTH - 1)
		var cy: int = clampi(int((py + TACTICAL_OFFSET_Y) / TACTICAL_CELL_H), 0, TACTICAL_GRID_HEIGHT - 1)
		
		var speed: float = sqrt(vx * vx + vy * vy)
		var v_norm_x: float = 0.0
		var v_norm_y: float = 0.0
		if speed > 0.1:
			v_norm_x = vx / speed
			v_norm_y = vy / speed
		
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				var nx: int = cx + dx
				var ny: int = cy + dy
				if nx >= 0 and nx < TACTICAL_GRID_WIDTH and ny >= 0 and ny < TACTICAL_GRID_HEIGHT:
					var cell_idx: int = ny * TACTICAL_GRID_WIDTH + nx
					
					var cell_world_x: float = float(nx) * TACTICAL_CELL_W - TACTICAL_OFFSET_X + TACTICAL_CELL_W * 0.5
					var cell_world_y: float = float(ny) * TACTICAL_CELL_H - TACTICAL_OFFSET_Y + TACTICAL_CELL_H * 0.5
					
					var dir_x: float = cell_world_x - px
					var dir_y: float = cell_world_y - py
					var dist: float = sqrt(dir_x * dir_x + dir_y * dir_y)
					var dir_norm_x: float = 0.0
					var dir_norm_y: float = 0.0
					if dist > 0.0001:
						dir_norm_x = dir_x / dist
						dir_norm_y = dir_y / dist
					
					var v_dot_dir: float = v_norm_x * dir_norm_x + v_norm_y * dir_norm_y
					var manhattan_dist: float = absf(float(dx)) + absf(float(dy))
					
					var influence: int = maxi(0, I_BASE - int(float(K_D) * manhattan_dist) + int(float(K_V) * v_dot_dir))
					
					if player_teams[i] == 0:
						grid_home[cell_idx] += influence
					else:
						grid_away[cell_idx] += influence

	for i: int in range(TACTICAL_GRID_CELLS):
		if grid_home[i] > grid_away[i]:
			grid_dominant[i] = 0
		elif grid_away[i] > grid_home[i]:
			grid_dominant[i] = 1
		else:
			grid_dominant[i] = -1

func get_pitch_control_at(pos: Vector2, team: int) -> float:
	var cx: int = clampi(int((pos.x + TACTICAL_OFFSET_X) / TACTICAL_CELL_W), 0, TACTICAL_GRID_WIDTH - 1)
	var cy: int = clampi(int((pos.y + TACTICAL_OFFSET_Y) / TACTICAL_CELL_H), 0, TACTICAL_GRID_HEIGHT - 1)
	var idx: int = cy * TACTICAL_GRID_WIDTH + cx
	var h: float = float(grid_home[idx])
	var a: float = float(grid_away[idx])
	var total: float = h + a
	if total <= 0.0:
		return 0.5
	if team == 0:
		return h / total
	else:
		return a / total

func get_cell_dominance(cell_x: int, cell_y: int) -> int:
	if cell_x < 0 or cell_x >= TACTICAL_GRID_WIDTH or cell_y < 0 or cell_y >= TACTICAL_GRID_HEIGHT:
		return -1
	return grid_dominant[cell_y * TACTICAL_GRID_WIDTH + cell_x]

func is_zone_14(cell_x: int, cell_y: int, attacking_team: int) -> bool:
	if attacking_team == 0:
		return (cell_x == 8 or cell_x == 9) and (cell_y == 3 or cell_y == 4)
	else:
		return (cell_x == 2 or cell_x == 3) and (cell_y == 3 or cell_y == 4)
