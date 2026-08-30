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
##          get_opponents_of(), get_teammates_of(), nearest_opponent_dist_to()
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

## Scratch buffers for the two Array-returning accessors. Reused between calls
## so a caller on a warm path does not allocate; see the accessor docs for the
## aliasing rule that comes with that.
var _opponent_scratch: Array[int] = []
var _teammate_scratch: Array[int] = []


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
	_resize_arrays()


## --- Per-frame refresh ------------------------------------------------------

func _physics_process(_delta: float) -> void:
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


## Distance from `pos` to the closest registered player NOT on `team`.
## Returns INF when no opponent is registered. Allocation-free.
func nearest_opponent_dist_to(pos: Vector2, team: int) -> float:
	var best: float = INF
	for i: int in range(TOTAL_PLAYERS):
		var node: HeavyPlayerController = player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if player_teams[i] == team:
			continue
		var d: float = pos.distance_to(player_positions[i])
		if d < best:
			best = d
	return best


## Position of the closest registered player NOT on `team`, or `pos` itself
## when no opponent is registered. Allocation-free — no Arrays or Dictionaries.
func nearest_opponent_position(pos: Vector2, team: int) -> Vector2:
	var best_dist: float = INF
	var best_pos: Vector2 = pos
	for i: int in range(TOTAL_PLAYERS):
		if player_teams[i] == team:
			continue
		if not is_instance_valid(player_nodes[i]):
			continue
		var d: float = pos.distance_to(player_positions[i])
		if d < best_dist:
			best_dist = d
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
