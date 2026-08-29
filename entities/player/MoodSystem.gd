##
## MoodSystem
## Per-match mood tracker. Owns the mood float, tier transitions, passive drift,
## and the per-tick effective-stat multipliers that HeavyPlayerController and
## PlayerBrain read each frame. Mood is runtime-only — it never writes back to
## PlayerData.
## Mood starts at 0.5 (NORMAL) and drifts on match events received through
## GameEvents. HeavyPlayerController calls get_speed_multiplier() and
## get_accel_multiplier() inside _recalculate_movement_curve(); PlayerBrain reads
## get_composure_delta() / get_vision_delta() / get_aggression_delta() from its
## own _physics_process.
## Depends on: GameEvents, GameManager, HeavyPlayerController (as parent node).
## Exposes: apply_delta(), reset(), current_tier, mood_value,
##          get_speed_multiplier(), get_accel_multiplier(),
##          get_composure_delta(), get_vision_delta(), get_aggression_delta(),
##          get_kick_accuracy_scatter_multiplier()
##

class_name MoodSystem
extends Node

enum Tier { SLUMP = 0, NORMAL = 1, STREAK = 2 }

## --- Tier thresholds and effects --------------------------------------------

const SLUMP_THRESHOLD: float = 0.33
const STREAK_THRESHOLD: float = 0.67

const SLUMP_SPEED_MULT: float = 0.82   # -18%
const SLUMP_ACCEL_MULT: float = 1.25   # +25% time = slower
const SLUMP_COMPOSURE_DELTA: float = -0.20
const SLUMP_VISION_DELTA: float = -0.15
const SLUMP_AGGRESSION_DELTA: float = 0.15
const SLUMP_ACCURACY_MULT: float = 2.0   # scatter doubled

const STREAK_SPEED_MULT: float = 1.12   # +12%
const STREAK_ACCEL_MULT: float = 0.90   # -10% time = quicker first step
const STREAK_COMPOSURE_DELTA: float = 0.15
const STREAK_VISION_DELTA: float = 0.12
const STREAK_AGGRESSION_DELTA: float = 0.0
const STREAK_ACCURACY_MULT: float = 0.5   # scatter halved

const DRIFT_RATE_SLUMP: float = 0.02 / 60.0   # per second
const DRIFT_RATE_STREAK: float = 0.01 / 60.0

## --- State --------------------------------------------------------------------

## Physics frames between passive-drift updates, matching
## PlayerBrain.UPDATE_INTERVAL. Drift is a slow per-second ramp, so applying it
## once every 15 frames with 15 frames' worth of delta is numerically identical
## to applying it every frame — it just stops 22 mood systems from doing tier
## comparisons on the same tick.
const UPDATE_INTERVAL: int = 15

var mood_value: float = 0.5
var current_tier: Tier = Tier.NORMAL
var _player: HeavyPlayerController = null

## Phase offset for the drift stagger, taken from the owning player's world
## model slot so the 22 systems spread across the interval.
var _stagger_offset: int = 0
var _frame_counter: int = 0
## Physics time accumulated since the last drift application.
var _drift_accumulator: float = 0.0


func _ready() -> void:
	_player = get_parent() as HeavyPlayerController
	if _player == null:
		push_error("MoodSystem must be a child of HeavyPlayerController.")
	else:
		_stagger_offset = maxi(_player.world_index, 0)

	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.tackle_won.connect(_on_tackle_won)
	GameEvents.foul_committed.connect(_on_foul_committed)
	GameEvents.stamina_depleted.connect(_on_stamina_depleted)
	GameEvents.ball_struck.connect(_on_ball_struck)


func _physics_process(delta: float) -> void:
	if not GameManager.is_in_play():
		return

	# Accumulate every frame, apply on this system's stagger slot, so no drift
	# time is lost even though the tier comparison runs 15× less often.
	_drift_accumulator += delta
	_frame_counter += 1
	if (_frame_counter + _stagger_offset) % UPDATE_INTERVAL != 0:
		return

	var elapsed: float = _drift_accumulator
	_drift_accumulator = 0.0

	match current_tier:
		Tier.SLUMP:
			mood_value += DRIFT_RATE_SLUMP * elapsed
		Tier.STREAK:
			mood_value -= DRIFT_RATE_STREAK * elapsed
		_:
			return

	_set_mood(mood_value)


## Called by PlayerFactory at match start — clears in-match mood back to neutral.
func reset() -> void:
	mood_value = 0.5
	current_tier = Tier.NORMAL


func apply_delta(delta: float) -> void:
	_set_mood(mood_value + delta)


func _set_mood(value: float) -> void:
	mood_value = clampf(value, 0.0, 1.0)

	var new_tier: Tier = Tier.NORMAL
	if mood_value < SLUMP_THRESHOLD:
		new_tier = Tier.SLUMP
	elif mood_value >= STREAK_THRESHOLD:
		new_tier = Tier.STREAK

	if new_tier != current_tier:
		current_tier = new_tier
		GameEvents.player_mood_changed.emit(_player, int(current_tier))


## --- Event handlers -----------------------------------------------------------

func _on_goal_scored(team: int) -> void:
	if _player == null:
		return
	if _player.team == team:
		apply_delta(0.10)
	else:
		apply_delta(-0.08)


func _on_tackle_won(winner: Node, loser: Node) -> void:
	if winner == _player:
		apply_delta(0.06)
	if loser == _player:
		apply_delta(-0.05)


func _on_foul_committed(fouler: Node, _victim: Node, _position: Vector2) -> void:
	if fouler == _player:
		apply_delta(-0.07)


func _on_stamina_depleted(player: Node) -> void:
	if player == _player:
		apply_delta(-0.06)


func _on_ball_struck(player: Node, speed: float, charge_ratio: float) -> void:
	if player == _player and charge_ratio > 0.7 and speed > 450.0:
		apply_delta(0.04)


## --- Effective-stat multipliers (pure, no side effects) -----------------------

func get_speed_multiplier() -> float:
	match current_tier:
		Tier.SLUMP: return SLUMP_SPEED_MULT
		Tier.STREAK: return STREAK_SPEED_MULT
		_: return 1.0


func get_accel_multiplier() -> float:
	match current_tier:
		Tier.SLUMP: return SLUMP_ACCEL_MULT
		Tier.STREAK: return STREAK_ACCEL_MULT
		_: return 1.0


func get_composure_delta() -> float:
	match current_tier:
		Tier.SLUMP: return SLUMP_COMPOSURE_DELTA
		Tier.STREAK: return STREAK_COMPOSURE_DELTA
		_: return 0.0


func get_vision_delta() -> float:
	match current_tier:
		Tier.SLUMP: return SLUMP_VISION_DELTA
		Tier.STREAK: return STREAK_VISION_DELTA
		_: return 0.0


func get_aggression_delta() -> float:
	match current_tier:
		Tier.SLUMP: return SLUMP_AGGRESSION_DELTA
		Tier.STREAK: return STREAK_AGGRESSION_DELTA
		_: return 0.0


func get_kick_accuracy_scatter_multiplier() -> float:
	match current_tier:
		Tier.SLUMP: return SLUMP_ACCURACY_MULT
		Tier.STREAK: return STREAK_ACCURACY_MULT
		_: return 1.0
