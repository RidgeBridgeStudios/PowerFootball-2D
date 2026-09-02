##
## ContractData
##
## One player's or staff member's employment terms. Split out of PlayerData
## because a contract has a life of its own in career mode: it is negotiated,
## it expires on a real calendar date, it carries bonus clauses that pay out on
## match events, and its remaining length drives both market value and the
## player's willingness to agitate for a move.
##
## PlayerData keeps its own wage_weekly/contract_years fields as the authored
## seed values; CareerManager promotes them into a ContractData the moment a
## career starts, and from then on this resource is authoritative.
##
## Depends on: CareerDate.
## Exposes: the fields below, is_expired(), days_remaining(), years_remaining(),
##          total_cost_to_expiry(), promise_satisfied_by(), make_default().
##

class_name ContractData
extends Resource

## Squad-status promise made at signing. Drives morale when playing time does
## not match: see MoraleEngine.evaluate_playing_time().
enum Status { STAR_PLAYER = 0, IMPORTANT = 1, REGULAR_STARTER = 2, ROTATION = 3, SQUAD_PLAYER = 4, PROSPECT = 5 }

const STATUS_NAMES: Array[String] = [
	"Star Player", "Important", "Regular Starter", "Rotation", "Squad Player", "Prospect"
]

## Minimum share of available minutes each promised status expects. A player
## below their band starts losing morale; well above it gains.
const STATUS_MINUTES_EXPECTATION: Array[float] = [0.85, 0.70, 0.55, 0.35, 0.15, 0.05]

@export var club_name: String = ""
@export var wage_weekly: int = 15000
@export var expiry: CareerDate = null
@export var signed_on: CareerDate = null
@export var release_clause: int = 0
@export var loyalty_bonus: int = 0
@export var signing_bonus: int = 0
## Paid per goal scored (attackers negotiate this up).
@export var goal_bonus: int = 0
## Paid once if the club finishes at or above promised_finish_position.
@export var promotion_bonus: int = 0
@export var promised_status: Status = Status.REGULAR_STARTER
## Transfer fee this club paid, amortised across the contract length.
@export var transfer_fee_paid: int = 0
## True while the player is out on loan at another club.
@export var is_on_loan: bool = false
@export var loan_parent_club: String = ""
@export var loan_expires: CareerDate = null
## Share of the wage the parent club still covers while on loan (0.0 - 1.0).
@export_range(0.0, 1.0) var loan_wage_subsidy: float = 0.0


static func make_default(p_club: String, p_wage: int, p_years: int, today: CareerDate) -> ContractData:
	var c := ContractData.new()
	c.club_name = p_club
	c.wage_weekly = p_wage
	c.signed_on = today.copy() if today != null else CareerDate.make(2026, 7, 1)
	var base: CareerDate = today if today != null else CareerDate.make(2026, 7, 1)
	# Contracts always expire on 30 June, the way real football contracts do,
	# rather than on the anniversary of signing.
	c.expiry = CareerDate.make(base.year + maxi(p_years, 1), 6, 30)
	return c


func days_remaining(today: CareerDate) -> int:
	if expiry == null or today == null:
		return 0
	return maxi(today.days_until(expiry), 0)


func years_remaining(today: CareerDate) -> float:
	return float(days_remaining(today)) / 365.0


func is_expired(today: CareerDate) -> bool:
	if expiry == null or today == null:
		return false
	return not today.is_before(expiry) and not today.equals(expiry)


## True once inside the final six months, when a player may negotiate freely
## with other clubs and the selling club's leverage collapses.
func is_in_final_six_months(today: CareerDate) -> bool:
	var remaining: int = days_remaining(today)
	return remaining > 0 and remaining <= 182


func status_name() -> String:
	return STATUS_NAMES[clampi(int(promised_status), 0, STATUS_NAMES.size() - 1)]


func expected_minutes_share() -> float:
	return STATUS_MINUTES_EXPECTATION[clampi(int(promised_status), 0, STATUS_MINUTES_EXPECTATION.size() - 1)]


## Remaining wage liability to expiry, in whole currency units. Finances uses
## this for the projected end-of-season balance.
func total_cost_to_expiry(today: CareerDate) -> int:
	var weeks: float = float(days_remaining(today)) / 7.0
	return int(round(float(wage_weekly) * weeks)) + loyalty_bonus


## Straight-line amortisation of the transfer fee across the contract term —
## the accounting charge this contract books each season.
func annual_amortisation() -> int:
	if transfer_fee_paid <= 0 or signed_on == null or expiry == null:
		return 0
	var term_days: int = maxi(signed_on.days_until(expiry), 1)
	var term_years: float = maxf(float(term_days) / 365.0, 1.0)
	return int(round(float(transfer_fee_paid) / term_years))


func copy() -> ContractData:
	var c := ContractData.new()
	c.club_name = club_name
	c.wage_weekly = wage_weekly
	c.expiry = expiry.copy() if expiry != null else null
	c.signed_on = signed_on.copy() if signed_on != null else null
	c.release_clause = release_clause
	c.loyalty_bonus = loyalty_bonus
	c.signing_bonus = signing_bonus
	c.goal_bonus = goal_bonus
	c.promotion_bonus = promotion_bonus
	c.promised_status = promised_status
	c.transfer_fee_paid = transfer_fee_paid
	c.is_on_loan = is_on_loan
	c.loan_parent_club = loan_parent_club
	c.loan_expires = loan_expires.copy() if loan_expires != null else null
	c.loan_wage_subsidy = loan_wage_subsidy
	return c


static func status_from_name(name_str: String) -> Status:
	for i: int in range(STATUS_NAMES.size()):
		if STATUS_NAMES[i].nocasecmp_to(name_str) == 0:
			return i as Status
	return Status.REGULAR_STARTER
