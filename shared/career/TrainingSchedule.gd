##
## TrainingSchedule
##
## The club's weekly training plan: what each of the seven days is spent on,
## and what each individual player is working on privately.
##
## The core tension the model has to produce is FM's: heavy weeks build
## attributes and match sharpness but accumulate fatigue and injury risk, light
## weeks preserve legs but stall development. Both effects run through the same
## per-day intensity number, so a manager cannot get one without the other.
##
## Depends on: PlayerData, StaffData, BoardState.
## Exposes: the fields below, make_default(), weekly_intensity(),
##          session_for_day(), set_day(), focus_for_player(), coach_bonus().
##

class_name TrainingSchedule
extends Resource

enum Session {
	REST = 0,
	RECOVERY = 1,
	PHYSICAL = 2,
	TECHNICAL = 3,
	TACTICAL = 4,
	SET_PIECES = 5,
	MATCH_PREP = 6,
	DOUBLE_INTENSITY = 7,
}

const SESSION_NAMES: Array[String] = [
	"Rest", "Recovery", "Physical", "Technical", "Tactical",
	"Set Pieces", "Match Preparation", "Double Session"
]

## Physical load each session puts on a player, 0.0 (rest) to 1.0 (double).
const SESSION_INTENSITY: Array[float] = [0.0, 0.12, 0.85, 0.45, 0.38, 0.30, 0.50, 1.0]

## Which player attribute family each session develops. Index-aligned with
## Session; REST/RECOVERY develop nothing.
const SESSION_FOCUS: Array[StringName] = [
	&"none", &"none", &"physical", &"technical", &"mental",
	&"set_piece", &"mental", &"physical",
]

## Individual focus a player can be assigned on top of the team schedule.
enum Focus {
	BALANCED = 0,
	PACE = 1,
	STAMINA = 2,
	FINISHING = 3,
	PASSING = 4,
	DEFENDING = 5,
	COMPOSURE = 6,
	LEADERSHIP = 7,
	POSITION_RETRAIN = 8,
}

const FOCUS_NAMES: Array[String] = [
	"Balanced", "Pace", "Stamina", "Finishing", "Passing",
	"Defending", "Composure", "Leadership", "Position Retraining"
]

## Baseline injury chance per player per day at intensity 1.0 and no
## fitness-coach support. Scaled by condition, age, and facilities.
const BASE_DAILY_INJURY_RISK: float = 0.009

@export var club_name: String = ""
## Seven entries, index 0 = Monday .. 6 = Sunday. Matches CareerDate.day_of_week().
@export var week: Array[int] = [
	Session.RECOVERY, Session.PHYSICAL, Session.TECHNICAL, Session.TACTICAL,
	Session.MATCH_PREP, Session.SET_PIECES, Session.REST
]
## Youth squad runs its own week — usually lighter and more technical.
@export var youth_week: Array[int] = [
	Session.TECHNICAL, Session.TECHNICAL, Session.PHYSICAL, Session.TACTICAL,
	Session.TECHNICAL, Session.RECOVERY, Session.REST
]
## squad_index -> Focus.
@export var individual_focus: Dictionary = {}
## squad_index -> position string being retrained toward.
@export var retrain_target: Dictionary = {}


static func make_default(p_club: String) -> TrainingSchedule:
	var t := TrainingSchedule.new()
	t.club_name = p_club
	return t


func session_for_day(day_of_week: int) -> Session:
	var idx: int = clampi(day_of_week, 0, 6)
	if idx >= week.size():
		return Session.REST
	return week[idx] as Session


func youth_session_for_day(day_of_week: int) -> Session:
	var idx: int = clampi(day_of_week, 0, 6)
	if idx >= youth_week.size():
		return Session.REST
	return youth_week[idx] as Session


func set_day(day_of_week: int, session: Session) -> void:
	var idx: int = clampi(day_of_week, 0, 6)
	while week.size() < 7:
		week.append(int(Session.REST))
	week[idx] = int(session)


func set_youth_day(day_of_week: int, session: Session) -> void:
	var idx: int = clampi(day_of_week, 0, 6)
	while youth_week.size() < 7:
		youth_week.append(int(Session.REST))
	youth_week[idx] = int(session)


static func session_name(session: Session) -> String:
	return SESSION_NAMES[clampi(int(session), 0, SESSION_NAMES.size() - 1)]


static func intensity_of(session: Session) -> float:
	return SESSION_INTENSITY[clampi(int(session), 0, SESSION_INTENSITY.size() - 1)]


## Mean intensity across the week — the number the training screen shows as the
## workload gauge, and what the fatigue model integrates.
func weekly_intensity() -> float:
	var total: float = 0.0
	for s: int in week:
		total += intensity_of(s as Session)
	return total / 7.0


func weekly_intensity_label() -> String:
	var i: float = weekly_intensity()
	if i >= 0.70:
		return "Very Heavy"
	if i >= 0.55:
		return "Heavy"
	if i >= 0.38:
		return "Balanced"
	if i >= 0.22:
		return "Light"
	return "Very Light"


func focus_for_player(squad_index: int) -> Focus:
	return int(individual_focus.get(squad_index, int(Focus.BALANCED))) as Focus


func set_focus(squad_index: int, focus: Focus) -> void:
	individual_focus[squad_index] = int(focus)


static func focus_name(focus: Focus) -> String:
	return FOCUS_NAMES[clampi(int(focus), 0, FOCUS_NAMES.size() - 1)]


## Combined coaching quality for one session family, drawn from the club's
## staff. A club with no relevant coach trains at a flat 0.5.
static func coach_bonus(staff: Array[StaffData], family: StringName) -> float:
	var best: float = 0.0
	var count: int = 0
	for s: StaffData in staff:
		var relevance: float = 0.0
		match family:
			&"physical":
				relevance = s.physiotherapy * 0.4 + s.coaching * 0.6
			&"technical":
				relevance = s.coaching
			&"mental":
				relevance = s.tactical_knowledge * 0.6 + s.coaching * 0.4
			&"set_piece":
				relevance = s.tactical_knowledge
			_:
				relevance = s.coaching * 0.5
		if relevance > 0.0:
			best = maxf(best, relevance)
			count += 1
	if count == 0:
		return 0.5
	return clampf(best, 0.1, 1.0)


## Per-player, per-day injury probability. Age and low condition dominate;
## good facilities and a strong physio pull it back down.
static func daily_injury_risk(
	player: PlayerData,
	condition: float,
	intensity: float,
	facility_mult: float,
	physio_quality: float,
	age: int
) -> float:
	if intensity <= 0.0:
		return 0.0
	var risk: float = BASE_DAILY_INJURY_RISK * intensity
	# Fatigue is the single biggest driver — training hard on empty legs is
	# how players get hurt.
	risk *= lerpf(3.2, 0.7, clampf(condition, 0.0, 1.0))
	# Age curve: flat to 28, then climbing.
	risk *= 1.0 + maxf(float(age - 28), 0.0) * 0.09
	# Facilities and physio quality both reduce it.
	risk /= maxf(facility_mult, 0.4)
	risk *= lerpf(1.35, 0.65, clampf(physio_quality, 0.0, 1.0))
	# IronMan (4096) players are durable by trait.
	if player != null and player.has_trait(4096):
		risk *= 0.45
	# A low-professionalism player takes worse care of themselves.
	if player != null:
		risk *= lerpf(1.25, 0.85, clampf(player.professionalism, 0.0, 1.0))
	return clampf(risk, 0.0, 0.25)
