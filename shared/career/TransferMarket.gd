##
## TransferMarket
##
## Valuation and negotiation. Two jobs:
##
##   1. VALUE a player — what a selling club will actually hold out for, which
##      is not the same as PlayerData.calculate_market_value(). That authored
##      figure is a static seed; a live market price moves with age, contract
##      length, form, reputation and how badly the owner wants to keep them.
##
##   2. NEGOTIATE — decide how a selling club and a player respond to an offer.
##      Both sides are modelled as reservation prices with a tolerance band, so
##      a bid slightly under is countered rather than refused, and a derisory
##      one is rejected outright with the club's patience taking a hit.
##
## The AI transfer behaviour deliberately reads ManagerData's existing signing
## philosophy fields (preferred_min_age, budget_flexibility, prized_attribute,
## preferred_playstyle) rather than inventing a parallel set, so an AI club
## recruits like the manager the rest of the game already says it has.
##
## Depends on: PlayerData, PlayerCareerState, ContractData, TransferOffer,
##             ManagerData, TeamData, CareerDate, PlayerDevelopmentEngine.
## Exposes: market_value(), asking_price(), evaluate_club_response(),
##          evaluate_player_terms(), wage_demand(), ai_should_bid(),
##          squad_need_score().
##

class_name TransferMarket
extends RefCounted

## A bid within this fraction of the asking price gets a counter rather than a
## flat rejection.
const COUNTER_BAND: float = 0.25
## Below this fraction of the asking price, the club is insulted.
const INSULT_BAND: float = 0.55
## Clubs will not sell below this multiple of value in the last contract year.
const EXPIRING_DISCOUNT: float = 0.45


## Live market value, in whole currency units. Starts from the player's own
## derived valuation and then applies the things that actually move a price.
static func market_value(
	data: PlayerData,
	state: PlayerCareerState,
	today: CareerDate
) -> int:
	if data == null:
		return 0
	var base: float = float(data.calculate_market_value())
	var age: int = data.get_age(today.year, today.month, today.day) if today != null else 25

	# Age curve: a 21-year-old with the same ability as a 31-year-old is worth
	# far more, because the buyer is purchasing years as well as ability.
	var age_mult: float = 1.0
	if age <= 20:
		age_mult = 1.55
	elif age <= 23:
		age_mult = 1.35
	elif age <= 26:
		age_mult = 1.15
	elif age <= 28:
		age_mult = 1.0
	elif age <= 30:
		age_mult = 0.80
	elif age <= 32:
		age_mult = 0.55
	elif age <= 34:
		age_mult = 0.32
	else:
		age_mult = 0.16
	base *= age_mult

	# Potential upside is real money for a young player and worth nothing for
	# an old one, so it is gated behind the age multiplier above.
	if state != null and age <= 23:
		var headroom: float = float(state.potential_remaining(data.calculate_overall_rating()))
		base *= 1.0 + clampf(headroom / 25.0, 0.0, 1.0) * 0.85

	# Form moves the price within a season.
	base *= lerpf(0.82, 1.22, clampf((data.form - 4.0) / 4.0, 0.0, 1.0))

	# Contract length is the single biggest lever a selling club has. A player
	# with six months left is nearly worthless on the market.
	if state != null and state.contract != null and today != null:
		var years_left: float = state.contract.years_remaining(today)
		if years_left <= 0.5:
			base *= EXPIRING_DISCOUNT
		elif years_left <= 1.0:
			base *= 0.62
		elif years_left <= 2.0:
			base *= 0.85
		elif years_left >= 4.0:
			base *= 1.12

	# Injured players are discounted for as long as they are out.
	if state != null and state.is_injured():
		base *= lerpf(0.95, 0.60, clampf(float(state.injury_days_remaining) / 120.0, 0.0, 1.0))

	return maxi(int(round(base)), 5000)


## What the selling club will actually hold out for. Always at or above market
## value — clubs do not sell at the valuation, they sell at a premium, and the
## premium scales with how much they want to keep the player.
static func asking_price(
	data: PlayerData,
	state: PlayerCareerState,
	selling_club: TeamData,
	today: CareerDate
) -> int:
	var value: int = market_value(data, state, today)
	var premium: float = 1.25

	# A club protecting a key player prices them out of the market.
	if state != null and state.contract != null:
		match state.contract.promised_status:
			ContractData.Status.STAR_PLAYER:
				premium += 0.65
			ContractData.Status.IMPORTANT:
				premium += 0.35
			ContractData.Status.REGULAR_STARTER:
				premium += 0.15
			_:
				pass

	# A transfer-listed player is being actively moved on — priced to sell.
	if state != null and state.transfer_listed:
		premium = maxf(premium - 0.45, 0.85)
	if state != null and state.has_requested_transfer:
		premium = maxf(premium - 0.25, 0.80)

	# A rich club has no need to sell at all.
	if selling_club != null:
		premium += selling_club.reputation * 0.30

	# A release clause is a hard ceiling — meet it and the club has no say.
	var price: int = int(round(float(value) * premium))
	if state != null and state.contract != null and state.contract.release_clause > 0:
		price = mini(price, state.contract.release_clause)
	return price


## The selling club's answer to a bid. Mutates and returns the offer.
static func evaluate_club_response(
	offer: TransferOffer,
	data: PlayerData,
	state: PlayerCareerState,
	selling_club: TeamData,
	today: CareerDate,
	rng: RandomNumberGenerator
) -> TransferOffer:
	if offer == null:
		return offer

	# A free agent has no selling club to satisfy — go straight to terms.
	if offer.kind == TransferOffer.Kind.FREE_AGENT:
		offer.advance_to(TransferOffer.State.CLUB_ACCEPTED, today, "No fee required — agree personal terms.")
		return offer

	var ask: int = asking_price(data, state, selling_club, today)

	# Meeting a release clause is not a negotiation.
	if state != null and state.contract != null and state.contract.release_clause > 0 \
			and offer.fee_offered >= state.contract.release_clause:
		offer.advance_to(
			TransferOffer.State.CLUB_ACCEPTED, today,
			"The release clause has been met. %s cannot block the move." % selling_club.team_name
		)
		return offer

	var ratio: float = float(offer.fee_offered) / maxf(float(ask), 1.0)
	# A little randomness so the same bid is not always answered identically.
	ratio += rng.randf_range(-0.04, 0.04)

	if ratio >= 1.0:
		offer.advance_to(
			TransferOffer.State.CLUB_ACCEPTED, today,
			"%s have accepted your offer for %s." % [selling_club.team_name, offer.player_name]
		)
	elif ratio >= 1.0 - COUNTER_BAND:
		offer.fee_demanded = ask
		offer.advance_to(
			TransferOffer.State.CLUB_COUNTERED, today,
			"%s value %s at %s and will not go lower." % [
				selling_club.team_name, offer.player_name, format_fee(ask)
			]
		)
	elif ratio >= INSULT_BAND:
		offer.advance_to(
			TransferOffer.State.CLUB_REJECTED, today,
			"%s have rejected your offer for %s as too low." % [selling_club.team_name, offer.player_name]
		)
	else:
		offer.advance_to(
			TransferOffer.State.CLUB_REJECTED, today,
			"%s have dismissed your offer for %s out of hand and asked you not to return." % [
				selling_club.team_name, offer.player_name
			]
		)
	return offer


## What wage a player expects, given their ability, reputation and the size of
## the club courting them.
static func wage_demand(
	data: PlayerData,
	state: PlayerCareerState,
	buying_club: TeamData,
	today: CareerDate
) -> int:
	if data == null:
		return 5000
	var overall: int = data.calculate_overall_rating()
	# Exponential in ability, the way real wage structures are.
	var base: float = 1800.0 * pow(1.085, float(overall - 50))
	base *= lerpf(0.75, 1.85, clampf(data.player_reputation, 0.0, 1.0))
	# Ambitious players want more; loyal ones will take less to stay put.
	base *= lerpf(0.88, 1.20, clampf(data.ambition, 0.0, 1.0))

	# Joining a bigger club, a player will accept relatively less because the
	# move itself is the prize; dropping down, they want compensating.
	if buying_club != null:
		base *= lerpf(1.20, 0.92, clampf(buying_club.reputation, 0.0, 1.0))

	var age: int = data.get_age(today.year, today.month, today.day) if today != null else 25
	if age >= 32:
		base *= 0.82
	elif age <= 20:
		base *= 0.65

	return maxi(int(round(base / 100.0)) * 100, 500)


## The player's answer to a personal-terms offer.
static func evaluate_player_terms(
	offer: TransferOffer,
	data: PlayerData,
	state: PlayerCareerState,
	buying_club: TeamData,
	current_club: TeamData,
	today: CareerDate,
	rng: RandomNumberGenerator
) -> TransferOffer:
	if offer == null or data == null:
		return offer

	var demand: int = wage_demand(data, state, buying_club, today)
	var wage_ratio: float = float(offer.wage_offered) / maxf(float(demand), 1.0)

	# Ambition weighs the move itself, not just the money. A player at a small
	# club offered a big one will take a haircut; the reverse needs a premium.
	var prestige_delta: float = 0.0
	if buying_club != null and current_club != null:
		prestige_delta = buying_club.reputation - current_club.reputation
	var appeal: float = wage_ratio + prestige_delta * lerpf(0.15, 0.70, clampf(data.ambition, 0.0, 1.0))

	# Promised status matters as much as money to a player who wants to play.
	var promised_share: float = ContractData.STATUS_MINUTES_EXPECTATION[
		clampi(int(offer.promised_status), 0, ContractData.STATUS_MINUTES_EXPECTATION.size() - 1)
	]
	appeal += (promised_share - 0.5) * 0.35

	# Loyalty resists a move away from a club the player is settled at.
	if current_club != null and buying_club != null and current_club.team_name != buying_club.team_name:
		appeal -= clampf(data.loyalty, 0.0, 1.0) * 0.22
	# An unhappy player is much easier to prise away.
	appeal += (0.5 - data.morale) * 0.35
	if state != null and state.has_requested_transfer:
		appeal += 0.30

	appeal += rng.randf_range(-0.05, 0.05)

	if appeal >= 1.0:
		offer.advance_to(
			TransferOffer.State.COMPLETED, today,
			"%s has agreed terms and will join %s." % [offer.player_name, offer.buying_club]
		)
	elif appeal >= 0.86:
		offer.wage_demanded = maxi(int(round(float(demand) * 1.05 / 100.0)) * 100, demand)
		offer.advance_to(
			TransferOffer.State.TERMS_COUNTERED, today,
			"%s is interested but wants %s per week." % [
				offer.player_name, format_fee(offer.wage_demanded)
			]
		)
	else:
		offer.advance_to(
			TransferOffer.State.TERMS_REJECTED, today,
			"%s is not interested in a move to %s." % [offer.player_name, offer.buying_club]
		)
	return offer


## --- AI club recruitment ---------------------------------------------------------

## How badly a club needs a player in a given position, 0..1. Reads the squad
## it already has: thin cover or poor quality in a slot raises the score.
static func squad_need_score(team: TeamData, position_role: String) -> float:
	if team == null or team.squad.is_empty():
		return 0.5
	var family: String = position_family(position_role)
	var count: int = 0
	var best: int = 0
	for p: PlayerData in team.squad:
		if position_family(p.position_role) != family:
			continue
		count += 1
		best = maxi(best, p.calculate_overall_rating())

	# Fewer than two bodies in a family is a genuine hole.
	var depth_need: float = clampf(1.0 - float(count) / 4.0, 0.0, 1.0)
	# Quality need is relative to the rest of the squad.
	var squad_avg: int = 0
	for p2: PlayerData in team.squad:
		squad_avg += p2.calculate_overall_rating()
	squad_avg = squad_avg / maxi(team.squad.size(), 1)
	var quality_need: float = clampf(float(squad_avg - best) / 12.0, 0.0, 1.0)
	return clampf(depth_need * 0.55 + quality_need * 0.45, 0.0, 1.0)


## Groups specific roles into the four families depth is actually judged on.
static func position_family(role: String) -> String:
	match role.to_upper():
		"GK":
			return "GK"
		"CB", "LB", "RB", "LWB", "RWB":
			return "DEF"
		"DM", "CDM", "CM", "LM", "RM", "AM", "CAM":
			return "MID"
		_:
			return "ATT"


## Whether an AI club would open talks for a player, and at what fee. Returns
## 0 when it would not bid at all.
static func ai_should_bid(
	buyer: TeamData,
	buyer_manager: ManagerData,
	target: PlayerData,
	target_state: PlayerCareerState,
	seller: TeamData,
	budget_available: int,
	today: CareerDate,
	rng: RandomNumberGenerator
) -> int:
	if buyer == null or target == null or buyer == seller:
		return 0

	var ask: int = asking_price(target, target_state, seller, today)
	if ask > budget_available:
		return 0

	var age: int = target.get_age(today.year, today.month, today.day) if today != null else 25
	var interest: float = 0.0

	# 1. Does the squad need this position at all?
	interest += squad_need_score(buyer, target.position_role) * 0.40

	# 2. Is the player actually an upgrade on what they have?
	var overall: int = target.calculate_overall_rating()
	var squad_avg: int = 0
	for p: PlayerData in buyer.squad:
		squad_avg += p.calculate_overall_rating()
	squad_avg = squad_avg / maxi(buyer.squad.size(), 1)
	interest += clampf(float(overall - squad_avg) / 10.0, -0.5, 0.5) * 0.35

	# 3. Manager philosophy — the existing signing-preference fields.
	if buyer_manager != null:
		if age >= buyer_manager.preferred_min_age and age <= buyer_manager.preferred_max_age:
			interest += 0.12
		else:
			interest -= 0.18
		if target.mass >= buyer_manager.preferred_mass_min and target.mass <= buyer_manager.preferred_mass_max:
			interest += 0.05
		match buyer_manager.prized_attribute:
			"vision":
				interest += (target.vision - 0.5) * 0.20
			"composure":
				interest += (target.composure - 0.5) * 0.20
			"aggression":
				interest += (target.aggression - 0.5) * 0.20
			_:
				pass
		# A youth-trusting manager chases potential over present ability.
		if target_state != null and age <= 22:
			var headroom: float = float(target_state.potential_remaining(overall))
			interest += clampf(headroom / 20.0, 0.0, 1.0) * buyer_manager.youth_trust * 0.25

	# 4. A club will not sign someone far too good for them, or vice versa.
	interest -= absf(buyer.reputation - target.player_reputation) * 0.30

	# 5. Availability signals.
	if target_state != null:
		if target_state.transfer_listed:
			interest += 0.20
		if target_state.has_requested_transfer:
			interest += 0.15
		if target_state.is_injured() and target_state.injury_days_remaining > 40:
			interest -= 0.35

	interest += rng.randf_range(-0.08, 0.08)

	if interest < 0.45:
		return 0

	# Bid strength scales with how much they want the player and how freely the
	# manager spends.
	var flex: float = buyer_manager.budget_flexibility if buyer_manager != null else 0.5
	var bid_ratio: float = lerpf(0.82, 1.08, clampf(interest, 0.0, 1.0)) * lerpf(0.92, 1.06, flex)
	return mini(int(round(float(ask) * bid_ratio)), budget_available)


## Compact money formatting used across every career screen.
static func format_fee(amount: int) -> String:
	var v: float = float(amount)
	if absf(v) >= 1_000_000.0:
		return "£%.1fM" % (v / 1_000_000.0)
	if absf(v) >= 1_000.0:
		return "£%.0fK" % (v / 1_000.0)
	return "£%d" % amount
