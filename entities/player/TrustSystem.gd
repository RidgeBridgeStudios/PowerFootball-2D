##
## TrustSystem
##
## Per-match, per-player memory of how much THIS player's passer trusts each
## teammate as a pass target. One instance is attached (by PlayerFactory,
## mirroring MoodSystem) to every HeavyPlayerController, so trust is always
## read from the passer's own node — "how much do I trust them" rather than a
## global relationship table. Match-scoped only, exactly like MoodSystem: it
## never writes back to PlayerData, and is reset at each new PlayerFactory.apply()
## and at every substitution.
##
## Trust is asymmetric and keyed by the synthesized per-player id already used
## by MatchStatsTracker/ai-architect.md: `team * 1000 + squad_index`. There is
## no PlayerData.player_id to key on instead — see ai-architect.md's "PlayerData
## has no stable identity" note.
##
## Update flow: PlayerBrain registers a pending pass (register_pass()) at the
## exact moment a CPU pass is struck, since that is the one place that still
## knows the intended receiver. DribbleState resolves it one of two ways when
## the ball's next possession change is observed:
##   - the intended receiver picks it up            -> resolve_possession_change()
##     credits RECEPTION_TRUST_DELTA (successful link-up play)
##   - an opponent picks it up while a pass pending  -> resolve_possession_change()
##     debits INTERCEPTION_TRUST_DELTA from trust in the intended receiver
## A pending registration that never resolves (wide pass nobody touches, ball
## goes out of bounds) expires after PENDING_TIMEOUT so it can never attach to
## an unrelated later event.
##
## Depends on: HeavyPlayerController (as parent node).
## Exposes: register_pass(), resolve_possession_change(), get_trust(), reset(),
##          trust_multiplier(), player_key() (static)
##

class_name TrustSystem
extends Node

## --- Tuning — the single place to retune trust behaviour ---------------------

## Trust value read for a teammate the passer has no history with yet.
const NEUTRAL_TRUST: float = 0.5
const MIN_TRUST: float = 0.15
const MAX_TRUST: float = 0.95

## Applied to trust[target] when a pass to that exact target completes.
const RECEPTION_TRUST_DELTA: float = 0.10
## Applied to trust[target] when a pass to that exact target is intercepted.
const INTERCEPTION_TRUST_DELTA: float = -0.12

## Seconds a registered pending pass stays live before being treated as
## resolved-with-no-signal.
const PENDING_TIMEOUT: float = 3.0

## trust_multiplier() output range at trust == 0.0 / 1.0. 0.5 (NEUTRAL_TRUST)
## maps to exactly 1.0 — trust only ever nudges an already-scored candidate,
## never decides one on its own. Requirement: "bias choices, not override
## everything."
const TRUST_MULT_MIN: float = 0.85
const TRUST_MULT_MAX: float = 1.15

## Master switch — flip to false to disable the trust bias project-wide
## without touching any call site. Pass scoring simply reads a flat 1.0
## multiplier while this is off; trust bookkeeping (register/resolve) still
## runs so the data keeps accumulating and is ready the moment this flips
## back on.
static var trust_bias_enabled: bool = true

## --- State ---------------------------------------------------------------------

var _trust: Dictionary = {}   # int (player_key) -> float

var _player: HeavyPlayerController = null

## The teammate this player's last CPU-executed pass targeted, and how long
## that registration stays valid. -1 = no pass currently pending resolution.
var _pending_target_key: int = -1
var _pending_timer: float = 0.0


func _ready() -> void:
	_player = get_parent() as HeavyPlayerController
	if _player == null:
		push_error("TrustSystem must be a child of HeavyPlayerController.")


func _physics_process(delta: float) -> void:
	if _pending_target_key == -1:
		return
	_pending_timer -= delta
	if _pending_timer <= 0.0:
		_pending_target_key = -1


## Called by PlayerFactory at match start (and on substitution) — clears
## accumulated trust and any in-flight pending pass.
func reset() -> void:
	_trust.clear()
	_pending_target_key = -1
	_pending_timer = 0.0


## Called by PlayerBrain the instant a CPU pass is struck (ball.apply_kick()
## fires), so a later possession change can be attributed to this specific
## attempt. target_key is TrustSystem.player_key(receiver).
func register_pass(target_key: int) -> void:
	_pending_target_key = target_key
	_pending_timer = PENDING_TIMEOUT


## Called whenever the ball's possession moves to a new player and this system
## belongs to whoever touched it last (the passer). new_holder_key identifies
## who just gained it; same_team is whether they share this passer's team.
## No-ops if no pass is currently pending — e.g. the previous touch was a
## dribble carry, not a struck pass.
func resolve_possession_change(new_holder_key: int, same_team: bool) -> void:
	if _pending_target_key == -1:
		return
	if same_team and new_holder_key == _pending_target_key:
		_adjust(new_holder_key, RECEPTION_TRUST_DELTA)
	elif not same_team:
		_adjust(_pending_target_key, INTERCEPTION_TRUST_DELTA)
	# A same-team pickup that isn't the exact intended target (a loose-ball
	# recovery elsewhere) is left neutral — ambiguous credit is worse than none.
	_pending_target_key = -1


## Trust this player currently holds toward the given teammate, defaulting to
## NEUTRAL_TRUST for a candidate with no history yet.
func get_trust(target_key: int) -> float:
	return _trust.get(target_key, NEUTRAL_TRUST)


func _adjust(target_key: int, delta: float) -> void:
	var current: float = _trust.get(target_key, NEUTRAL_TRUST)
	_trust[target_key] = clampf(current + delta, MIN_TRUST, MAX_TRUST)


## Maps a 0.0-1.0 trust value onto a gentle multiplier for pass-utility scores.
## Neutral trust (0.5) always resolves to exactly 1.0.
static func trust_multiplier(trust: float) -> float:
	if not trust_bias_enabled:
		return 1.0
	return lerpf(TRUST_MULT_MIN, TRUST_MULT_MAX, clampf(trust, 0.0, 1.0))


## Synthesized per-player id, matching MatchStatsTracker._player_key() and the
## ai-architect.md convention: team * 1000 + squad_index. squad_index (not
## world_index) is what stays stable for a real player across a substitution.
static func player_key(p: HeavyPlayerController) -> int:
	return p.team * 1000 + p.squad_index
