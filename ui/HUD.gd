##
## HUD
##
## Match readout: score, clock, the shot power meter, and the world-space stamina
## bar under the active player. It reads GameManager for state and listens on
## GameEvents for match flow — no gameplay system knows the HUD exists.
##
## The power meter is only visible while a kick is charging; the stamina bar
## lives on the player scene (world space, so it tracks the sprite) and is driven
## from here for whichever player is currently controlled.
##
## Depends on: GameManager, GameEvents, HeavyPlayerController.
## Exposes: bind_active_player(player)
##

class_name HUD
extends CanvasLayer

## Charge below this leaves the power meter hidden, so a tapped pass does not
## flash the bar.
const METER_VISIBILITY_THRESHOLD: float = 0.02

var active_player: HeavyPlayerController = null

@onready var score_label: Label = $Root/TopBar/ScoreLabel
@onready var clock_label: Label = $Root/TopBar/ClockLabel
@onready var status_label: Label = $Root/StatusLabel
@onready var power_meter: ProgressBar = $Root/PowerMeter


func _ready() -> void:
	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.kickoff_started.connect(_on_kickoff_started)
	GameEvents.match_ended.connect(_on_match_ended)
	GameEvents.player_switched.connect(_on_player_switched)

	power_meter.min_value = 0.0
	power_meter.max_value = 1.0
	power_meter.value = 0.0
	power_meter.visible = false
	status_label.text = ""


func _process(_delta: float) -> void:
	score_label.text = GameManager.get_score_string()
	clock_label.text = GameManager.get_clock_string()
	_update_power_meter()
	_update_stamina_bar()


## Points the HUD at the player the human is currently controlling. Called on
## spawn and again on every GameEvents.player_switched.
func bind_active_player(player: HeavyPlayerController) -> void:
	if active_player == player:
		return

	# Only the controlled player shows a stamina bar; the rest stay clean.
	if active_player != null and is_instance_valid(active_player):
		active_player.stamina_bar.visible = false

	active_player = player
	if active_player != null:
		active_player.stamina_bar.visible = true


func _update_power_meter() -> void:
	if active_player == null or not is_instance_valid(active_player):
		power_meter.visible = false
		return

	var charge: float = active_player.state_factory.get_charge_ratio()
	power_meter.value = charge
	power_meter.visible = charge > METER_VISIBILITY_THRESHOLD


func _update_stamina_bar() -> void:
	if active_player == null or not is_instance_valid(active_player):
		return

	var bar: ProgressBar = active_player.stamina_bar
	bar.value = active_player.get_stamina_ratio()
	# Red once sprint is locked out, so exhaustion reads at a glance.
	bar.modulate = Color(0.9, 0.3, 0.25) if active_player.sprint_locked else Color(0.95, 0.95, 0.95)


func _on_goal_scored(team: int) -> void:
	status_label.text = "GOAL — TEAM %s" % ("A" if team == GameManager.TEAM_A else "B")


func _on_kickoff_started() -> void:
	status_label.text = "KICKOFF"
	# TODO: replace this with a short tween-out banner rather than clearing text
	# on the next event.


func _on_match_ended(winner: int) -> void:
	if winner < 0:
		status_label.text = "FULL TIME — DRAW"
	else:
		status_label.text = "FULL TIME — TEAM %s WINS" % ("A" if winner == GameManager.TEAM_A else "B")


func _on_player_switched(new_player: Node) -> void:
	bind_active_player(new_player as HeavyPlayerController)
