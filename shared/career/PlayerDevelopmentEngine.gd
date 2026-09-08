##
## PlayerDevelopmentEngine
##
## Ages players and moves their attributes over a career. The model has three
## regimes stitched together by one age curve:
##
##   - GROWTH   (under ~24): rapid gains, scaled by how much headroom is left
##                           between current ability and the hidden potential.
##   - PEAK     (~24-29):    near-flat; only training focus and form move things.
##   - DECLINE  (30+):       physical attributes fall first and fastest, mental
##                           ones keep improving for several more years.
##
## The split between physical and mental decline is the point. A 33-year-old
## should lose pace and stamina while GAINING composure, vision and leadership,
## so a veteran remains useful in a different way rather than simply fading.
##
## Growth is spent through PlayerData's real fields — top_speed,
## acceleration_time, stamina_max, close_control, vision, composure — because
## those are what the match engine actually reads. A development system that
## only moved a display number would be ornamental.
##
## Depends on: PlayerData, PlayerCareerState, TrainingSchedule, StaffData.
## Exposes: apply_daily_training(), apply_seasonal_ageing(), growth_multiplier(),
##          roll_potential(), current_ability(), development_label().
##

class_name PlayerDevelopmentEngine
extends RefCounted

## Age at which growth stops outpacing decline.
const PEAK_AGE_START: int = 24
const PEAK_AGE_END: int = 29
## Development experience needed to move overall ability by one point.
const XP_PER_ABILITY_POINT: float = 220.0

## Per-day experience a fully-focused session grants at coach quality 1.0.
const BASE_DAILY_XP: float = 9.0

## Physical decline. DECLINE_BASE is the fraction lost in the first season past
## the peak; DECLINE_RAMP is how much steeper each subsequent year gets.
##
## These are small on purpose. An earlier draft multiplied a 0.028 base by the
## number of years past peak, which compounded into an 11% single-season loss
## by 33 and drove every player to the 150 top_speed floor by 34 — a cliff, not
## a decline. At 0.012/0.22 a 220-pace player reads 207 at 32, 190 at 35 and
## 170 at 38 (~23% across nine years), and the trait/professionalism modifiers
## spread that from 156 (fragile, unprofessional) to 197 (IronMan professional)
## — which is the whole point of having them.
const DECLINE_BASE: float = 0.012
const DECLINE_RAMP: float = 0.22
## Mental attributes keep rising until this age.
const MENTAL_GROWTH_UNTIL: int = 34


## How receptive a player is to development at a given age. 1.0 at 16,
## tapering to 0 by the end of the peak band, and never negative.
##
## `archetype` branches this into the four PES Master League growth shapes.
## NORMAL (the default) is exactly the original curve, unchanged, so every
## existing call site that does not pass an archetype keeps its behaviour:
##
##   EARLY_PEAK   — explosive 17-21 (front-loaded), flat trickle 22-25.
##   LATE_BLOOMER — slow 17-23, a genuine second growth spurt 24-29.
##   EVERGREEN    — flat, moderate growth the whole window; no sharp taper.
static func growth_multiplier(age: int, archetype: PlayerCareerState.DevelopmentArchetype = PlayerCareerState.DevelopmentArchetype.NORMAL) -> float:
	if age <= 16:
		return 1.0

	match archetype:
		PlayerCareerState.DevelopmentArchetype.EARLY_PEAK:
			if age <= 21:
				# Front-loaded: nearly as fast as 16 all the way to 21.
				return clampf(1.0 - float(age - 16) * 0.04, 0.80, 1.0)
			if age <= 25:
				return maxf(0.22 - float(age - 21) * 0.04, 0.0)
			return maxf(0.10 - float(age - 25) * 0.03, 0.0)

		PlayerCareerState.DevelopmentArchetype.LATE_BLOOMER:
			if age <= 23:
				# Slower than NORMAL early on — the talent has not clicked yet.
				return clampf(0.70 - float(age - 16) * 0.06, 0.20, 0.70)
			if age <= 29:
				# The second wind: still gaining meaningfully in what would be
				# another archetype's peak years.
				return clampf(0.55 - float(age - 24) * 0.06, 0.22, 0.55)
			return maxf(0.15 - float(age - 29) * 0.03, 0.0)

		PlayerCareerState.DevelopmentArchetype.EVERGREEN:
			# Linear and moderate the whole window — no sharp early spike, no
			# early cutoff. Reaches a lower ceiling by 24 than the other three
			# archetypes trade for the much shallower decline curve below.
			if age >= PEAK_AGE_START:
				return maxf(0.20 - float(age - PEAK_AGE_START) * 0.015, 0.05)
			return clampf(0.62 - float(age - 16) * 0.045, 0.30, 0.62)

		_: # NORMAL — original curve, unchanged.
			if age >= PEAK_AGE_START:
				return maxf(0.18 - float(age - PEAK_AGE_START) * 0.03, 0.0)
			return clampf(1.0 - float(age - 16) * 0.107, 0.25, 1.0)


## A player's current ability on the same 1-99 scale the scouting layer shows.
static func current_ability(data: PlayerData) -> int:
	return data.calculate_overall_rating()


## Assigns a hidden potential ceiling at career start or youth intake.
## Younger players get a wider spread — an 18-year-old could become anything,
## a 29-year-old is essentially already what they will be.
static func roll_potential(data: PlayerData, age: int, rng: RandomNumberGenerator) -> int:
	var current: int = current_ability(data)
	if age >= PEAK_AGE_START:
		# Past the growth window: potential is current ability plus a nudge.
		return clampi(current + rng.randi_range(0, 2), 1, 99)

	# Headroom shrinks with age; ambition and professionalism raise the ceiling
	# because they are what decides whether talent is actually realised.
	var years_of_growth: float = float(PEAK_AGE_START - age)
	var character: float = (data.ambition * 0.5 + data.professionalism * 0.3 + data.determination * 0.2)
	var mean_gain: float = years_of_growth * lerpf(1.1, 3.4, character)
	# Gaussian-ish spread via two uniform samples, so extremes are rare.
	var spread: float = (rng.randf() + rng.randf() - 1.0) * years_of_growth * 1.6
	return clampi(current + int(round(mean_gain + spread)), current, 99)


## One training day for one player. Returns the experience actually banked, so
## the caller can surface a "coming along nicely" report.
##
## Development is gated by remaining potential: a player at their ceiling banks
## almost nothing however hard they train, which is what stops every squad
## converging on 99 over a long career.
static func apply_daily_training(
	data: PlayerData,
	state: PlayerCareerState,
	session: TrainingSchedule.Session,
	focus: TrainingSchedule.Focus,
	coach_quality: float,
	facility_mult: float,
	age: int
) -> float:
	if data == null or state == null:
		return 0.0
	if state.is_injured():
		return 0.0
	var intensity: float = TrainingSchedule.intensity_of(session)
	if intensity <= 0.0:
		return 0.0

	var headroom: int = state.potential_remaining(current_ability(data))
	if headroom <= 0:
		return 0.0

	# Diminishing returns as a player closes on their ceiling.
	var headroom_factor: float = clampf(float(headroom) / 12.0, 0.08, 1.0)
	var xp: float = BASE_DAILY_XP * intensity
	xp *= growth_multiplier(age, state.archetype)
	xp *= headroom_factor
	xp *= clampf(coach_quality, 0.1, 1.0) * 1.35
	xp *= clampf(facility_mult, 0.5, 1.5)
	# Professionals get more out of the same session than the careless.
	xp *= lerpf(0.65, 1.35, clampf(data.professionalism, 0.0, 1.0))
	xp *= lerpf(0.75, 1.25, clampf(data.determination, 0.0, 1.0))
	# Training on empty legs is wasted training.
	xp *= lerpf(0.45, 1.0, clampf(state.condition, 0.0, 1.0))
	# NightOwl players are half-hearted in sessions that follow a late one.
	if data.has_trait(2048):
		xp *= 0.85

	state.development_xp += xp
	while state.development_xp >= XP_PER_ABILITY_POINT:
		state.development_xp -= XP_PER_ABILITY_POINT
		_apply_ability_point(data, session, focus, true)
	return xp


## Moves one point of ability into the concrete PlayerData fields the match
## engine reads. `improving` false means the point is being LOST to age.
static func _apply_ability_point(
	data: PlayerData,
	session: TrainingSchedule.Session,
	focus: TrainingSchedule.Focus,
	improving: bool
) -> void:
	var sign_mult: float = 1.0 if improving else -1.0

	# The individual focus wins if one is set; otherwise the team session
	# decides which family the point lands in.
	match focus:
		TrainingSchedule.Focus.PACE:
			data.top_speed = clampf(data.top_speed + 3.0 * sign_mult, 150.0, 275.0)
			return
		TrainingSchedule.Focus.STAMINA:
			data.stamina_max = clampf(data.stamina_max + 2.5 * sign_mult, 60.0, 140.0)
			return
		TrainingSchedule.Focus.FINISHING:
			data.close_control = clampf(data.close_control + 0.022 * sign_mult, 0.05, 0.99)
			data.composure = clampf(data.composure + 0.012 * sign_mult, 0.05, 0.99)
			return
		TrainingSchedule.Focus.PASSING:
			data.vision = clampf(data.vision + 0.022 * sign_mult, 0.05, 0.99)
			data.close_control = clampf(data.close_control + 0.010 * sign_mult, 0.05, 0.99)
			return
		TrainingSchedule.Focus.DEFENDING:
			data.aggression = clampf(data.aggression + 0.018 * sign_mult, 0.05, 0.99)
			data.work_rate = clampf(data.work_rate + 0.014 * sign_mult, 0.05, 0.99)
			return
		TrainingSchedule.Focus.COMPOSURE:
			data.composure = clampf(data.composure + 0.024 * sign_mult, 0.05, 0.99)
			return
		TrainingSchedule.Focus.LEADERSHIP:
			data.leadership = clampf(data.leadership + 0.024 * sign_mult, 0.05, 0.99)
			data.determination = clampf(data.determination + 0.010 * sign_mult, 0.05, 0.99)
			return
		_:
			pass

	match TrainingSchedule.SESSION_FOCUS[clampi(int(session), 0, TrainingSchedule.SESSION_FOCUS.size() - 1)]:
		&"physical":
			data.top_speed = clampf(data.top_speed + 1.8 * sign_mult, 150.0, 275.0)
			data.stamina_max = clampf(data.stamina_max + 1.6 * sign_mult, 60.0, 140.0)
			data.acceleration_time = clampf(data.acceleration_time - 0.004 * sign_mult, 0.11, 0.40)
		&"technical":
			data.close_control = clampf(data.close_control + 0.016 * sign_mult, 0.05, 0.99)
			data.vision = clampf(data.vision + 0.008 * sign_mult, 0.05, 0.99)
		&"mental":
			data.composure = clampf(data.composure + 0.014 * sign_mult, 0.05, 0.99)
			data.vision = clampf(data.vision + 0.012 * sign_mult, 0.05, 0.99)
			data.work_rate = clampf(data.work_rate + 0.008 * sign_mult, 0.05, 0.99)
		&"set_piece":
			data.close_control = clampf(data.close_control + 0.012 * sign_mult, 0.05, 0.99)
			data.composure = clampf(data.composure + 0.010 * sign_mult, 0.05, 0.99)
		_:
			data.close_control = clampf(data.close_control + 0.006 * sign_mult, 0.05, 0.99)


## Applied once per player at each season rollover. Handles the decline side of
## the curve, plus the compensating mental growth that keeps veterans playable.
## Returns a short description if something notable happened, else "".
static func apply_seasonal_ageing(
	data: PlayerData,
	state: PlayerCareerState,
	age: int,
	rng: RandomNumberGenerator
) -> String:
	if data == null:
		return ""

	# Mental attributes keep maturing well past the physical peak.
	if age <= MENTAL_GROWTH_UNTIL:
		var mental_gain: float = 0.012 * lerpf(0.6, 1.5, clampf(data.professionalism, 0.0, 1.0))
		data.composure = clampf(data.composure + mental_gain, 0.05, 0.99)
		data.vision = clampf(data.vision + mental_gain * 0.7, 0.05, 0.99)
		if age >= 27:
			data.leadership = clampf(data.leadership + mental_gain * 1.2, 0.05, 0.99)

	var peak_end: int = _peak_age_end_for(state.archetype)
	if age <= peak_end:
		return ""

	# Physical decline, accelerating with each year past the peak and with a
	# career's accumulated injuries.
	var years_past: int = age - peak_end
	var rate: float = DECLINE_BASE * (1.0 + float(years_past) * DECLINE_RAMP) * _decline_ramp_scale_for(state.archetype)
	rate *= 1.0 + state.injury_proneness * 0.8
	# IronMan (4096) ages more gracefully; a low-professionalism player worse.
	if data.has_trait(4096):
		rate *= 0.55
	rate *= lerpf(1.25, 0.80, clampf(data.professionalism, 0.0, 1.0))
	rate *= rng.randf_range(0.75, 1.25)

	var speed_before: float = data.top_speed
	data.top_speed = clampf(data.top_speed * (1.0 - rate), 150.0, 275.0)
	data.stamina_max = clampf(data.stamina_max * (1.0 - rate * 0.9), 60.0, 140.0)
	data.acceleration_time = clampf(data.acceleration_time * (1.0 + rate * 0.8), 0.11, 0.42)
	# The physics constants are derived from these — see PlayerFactory, which
	# calls _recalculate_movement_curve() when it applies the data to a body.

	var lost: float = speed_before - data.top_speed
	if lost >= 4.5:
		return "%s (%d) has visibly lost a yard of pace." % [data.player_name, age]
	return ""


## Age the physical decline curve starts biting for a given archetype.
## EARLY_PEAK burns out sooner; LATE_BLOOMER's peak runs on for years longer;
## EVERGREEN and NORMAL keep the original PEAK_AGE_END.
static func _peak_age_end_for(archetype: PlayerCareerState.DevelopmentArchetype) -> int:
	match archetype:
		PlayerCareerState.DevelopmentArchetype.EARLY_PEAK:
			return 25
		PlayerCareerState.DevelopmentArchetype.LATE_BLOOMER:
			return 33
		_:
			return PEAK_AGE_END


## How steeply decline ramps up per year past peak. EARLY_PEAK falls off a
## cliff once it starts; EVERGREEN barely declines at all, which is the whole
## point of the archetype's name.
static func _decline_ramp_scale_for(archetype: PlayerCareerState.DevelopmentArchetype) -> float:
	match archetype:
		PlayerCareerState.DevelopmentArchetype.EARLY_PEAK:
			return 1.7
		PlayerCareerState.DevelopmentArchetype.EVERGREEN:
			return 0.45
		PlayerCareerState.DevelopmentArchetype.LATE_BLOOMER:
			return 1.1
		_:
			return 1.0


## Human-readable trajectory for the squad screen.
static func development_label(data: PlayerData, state: PlayerCareerState, age: int) -> String:
	if state == null:
		return "Unknown"
	var headroom: int = state.potential_remaining(current_ability(data))
	var peak_end: int = _peak_age_end_for(state.archetype)
	if age > peak_end:
		return "Declining"
	if age >= PEAK_AGE_START:
		return "At Peak" if headroom <= 2 else "Peak, some room"
	if headroom >= 15:
		return "High Ceiling"
	if headroom >= 7:
		return "Developing"
	if headroom >= 2:
		return "Nearly There"
	return "Ceiling Reached"
