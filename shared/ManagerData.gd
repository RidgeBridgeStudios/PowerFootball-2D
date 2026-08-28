##
## ManagerData
##
## Pure data container for one manager: identity, tactical philosophy, squad
## and signing preferences, personality traits, and career stats. Saveable as
## a .tres resource so a manager can be authored and edited without touching a
## scene, the same way PlayerData is. ManagerDirector and PressOffice are what
## turn an instance of this into live match behaviour and press quotes — this
## resource never touches a Node.
##
## current_team matches TeamData.team_name of the team this manager manages.
## No reference to TeamData itself is kept — data independence is mandatory.
##
## Depends on: nothing.
## Exposes: the fields below, has_trait(), get_win_rate(), get_goal_difference(),
##          make_default().
##

class_name ManagerData
extends Resource

## --- Identity ------------------------------------------------------------

@export var manager_name: String = ""
@export var nationality: String = ""
## 1-100. Higher = more settled tactical system, more media confidence.
@export var experience: int = 30
## Matches TeamData.team_name of the team this manager manages.
## Empty string means the manager is available for hire.
@export var current_team: String = ""

## --- Tactical philosophy ---------------------------------------------------

## 0 = deep compact block, 1 = aggressive high line.
## ManagerDirector uses this to shift formation_anchor Y values up the pitch.
@export_range(0.0, 1.0) var defensive_line: float = 0.5
## 0 = patient possession build-up (low formation_ball_weight),
## 1 = direct / counter-attack (high formation_ball_weight).
@export_range(0.0, 1.0) var tempo: float = 0.5
## 0 = narrow shape, 1 = wide shape.
## ManagerDirector scales formation_anchor X spread by this.
@export_range(0.0, 1.0) var width: float = 0.5
## 0 = passive mid-block, 1 = relentless gegenpressing.
## Raises aggression_attribute and shortens decision_interval on all players.
@export_range(0.0, 1.0) var pressing_intensity: float = 0.5
## 0 = avoids contact, 1 = seeks it. Adds a secondary boost to aggression_attribute.
@export_range(0.0, 1.0) var physicality: float = 0.5

## The formation applied at kick-off and whenever the scoreline is level.
@export var preferred_formation: String = "4-4-2"
## Shifted to when losing and time is running out.
@export var attacking_formation: String = "4-3-3"
## Shifted to when protecting a lead late in the match.
@export var defensive_formation: String = "4-4-2"

## --- Squad philosophy ------------------------------------------------------

## How much the manager trusts youth (0 = never plays U21, 1 = embraces them).
@export_range(0.0, 1.0) var youth_trust: float = 0.5
## How much the manager values loyalty over form when picking a lineup.
## 0 = pure meritocracy, 1 = always plays established favourites.
@export_range(0.0, 1.0) var loyalty_bias: float = 0.5
## How harshly the manager reacts to a player's poor performance.
## 0 = patient, 1 = immediately dropped.
@export_range(0.0, 1.0) var form_sensitivity: float = 0.5

## --- Signing philosophy (career mode transfer logic) -----------------------

@export var preferred_min_age: int = 20
@export var preferred_max_age: int = 30
## 0 = budget-conscious, 1 = willing to pay premium for quality.
@export_range(0.0, 1.0) var budget_flexibility: float = 0.5
## Preferred physical build. Governs which PlayerData mass values this manager
## rates highly in transfer scouting.
@export var preferred_mass_min: float = 65.0
@export var preferred_mass_max: float = 90.0
## The PlayerBrain attribute the manager prizes most when scouting.
## Valid values: "vision", "composure", "aggression", "none".
@export var prized_attribute: String = "none"
## Playstyle tag the manager recruits toward.
## Valid values: "technical", "physical", "pace", "aerial", "engine", "none".
@export var preferred_playstyle: String = "none"

## --- Personality traits -----------------------------------------------------
##
## HotHead (1)         — blunt press, escalates pressing after the 2nd conceded goal.
## Loyalist (2)         — never blames players in press; loyalty_bias reads as 1.0 (future feature tag).
## Pragmatist (4)       — dry press; shifts to defensive_formation at +1 instead of +2.
## Visionary (8)        — talks systems in press; midfield formation_ball_weight +0.10 (cap 0.75).
## Disciplinarian (16)  — accountable press; composure_attribute floor of 0.40.
## MindGames (32)       — undermines opponents pre-match; no in-match effect.
## Sentimental (64)     — nostalgic press; no in-match effect.
## MediaSavvy (128)     — polished, on-message press; no in-match effect.
## Volatile (256)       — unpredictable press tone; randomises _live_pressing +-0.15 after a shift.
## Idealist (512)       — never changes tactical stance; attacking/defensive formation locked to preferred.
@export_flags(
	"HotHead:1",
	"Loyalist:2",
	"Pragmatist:4",
	"Visionary:8",
	"Disciplinarian:16",
	"MindGames:32",
	"Sentimental:64",
	"MediaSavvy:128",
	"Volatile:256",
	"Idealist:512"
) var traits: int = 0


func has_trait(bit: int) -> bool:
	return (traits & bit) != 0


## --- Career stats ------------------------------------------------------------
## Not @export: written back by PitchScene._log_manager_stats() after a match
## and persisted through ManagerLoader.save_managers(), the same split PlayerData
## uses between authored fields and runtime-accumulated ones.

var matches_managed: int = 0
var wins: int = 0
var draws: int = 0
var losses: int = 0
var goals_scored: int = 0
var goals_conceded: int = 0


func get_win_rate() -> float:
	if matches_managed == 0:
		return 0.0
	return float(wins) / float(matches_managed)


func get_goal_difference() -> int:
	return goals_scored - goals_conceded


static func make_default(p_name: String, p_nationality: String) -> ManagerData:
	var m := ManagerData.new()
	m.manager_name = p_name
	m.nationality = p_nationality
	return m
