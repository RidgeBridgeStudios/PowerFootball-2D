##
## TransferOffer
##
## One in-flight transfer negotiation, from opening bid to signature. Models
## the two-stage FM flow: agree a fee with the selling CLUB, then agree
## personal terms with the PLAYER. Either side can reject, counter, or walk.
##
## An offer is a state machine, not a single number. CareerManager ticks
## pending offers once per day; the selling club responds on a delay so a bid
## is never resolved in the same frame it is made.
##
## Depends on: CareerDate, ContractData.
## Exposes: the fields below, make(), club_response_due(), advance_to(),
##          state_name(), is_terminal(), total_outlay().
##

class_name TransferOffer
extends Resource

enum State {
	DRAFT = 0,
	BID_SUBMITTED = 1,
	CLUB_REJECTED = 2,
	CLUB_COUNTERED = 3,
	CLUB_ACCEPTED = 4,
	TERMS_OFFERED = 5,
	TERMS_REJECTED = 6,
	TERMS_COUNTERED = 7,
	COMPLETED = 8,
	WITHDRAWN = 9,
}

const STATE_NAMES: Array[String] = [
	"Draft", "Bid Submitted", "Bid Rejected", "Club Countered", "Fee Agreed",
	"Terms Offered", "Terms Rejected", "Player Countered", "Completed", "Withdrawn"
]

enum Kind { PERMANENT = 0, LOAN = 1, FREE_AGENT = 2 }

const KIND_NAMES: Array[String] = ["Permanent", "Loan", "Free Transfer"]

## Days a selling club takes to respond to a bid.
const CLUB_RESPONSE_DAYS: int = 2
## Days a player takes to consider personal terms.
const PLAYER_RESPONSE_DAYS: int = 2

@export var buying_club: String = ""
@export var buyer_team_index: int = -1
@export var selling_club: String = ""
@export var player_name: String = ""
@export var player_team_index: int = -1
@export var player_squad_index: int = -1
@export var kind: Kind = Kind.PERMANENT
@export var state: State = State.DRAFT

## Fee terms.
@export var fee_offered: int = 0
## Set when the selling club counters — what they will actually accept.
@export var fee_demanded: int = 0
@export var sell_on_percent: float = 0.0
## Instalments spread the fee; the finance layer books them per season.
@export var instalment_years: int = 1

## Personal terms.
@export var wage_offered: int = 0
@export var wage_demanded: int = 0
@export var contract_years_offered: int = 3
@export var signing_bonus_offered: int = 0
@export var release_clause_offered: int = 0
@export var promised_status: ContractData.Status = ContractData.Status.REGULAR_STARTER

## Loan-specific.
@export var loan_wage_share: float = 0.5
@export var loan_months: int = 6

@export var submitted_on: CareerDate = null
@export var last_state_change: CareerDate = null
## Free text from the other side, shown in the inbox.
@export var response_message: String = ""
## True when the human manager is the buyer (drives which side the UI shows).
@export var initiated_by_user: bool = false


static func make(
	p_buying: String,
	p_selling: String,
	p_player_name: String,
	p_team_index: int,
	p_squad_index: int,
	p_kind: Kind,
	today: CareerDate
) -> TransferOffer:
	var o := TransferOffer.new()
	o.buying_club = p_buying
	o.selling_club = p_selling
	o.player_name = p_player_name
	o.player_team_index = p_team_index
	o.player_squad_index = p_squad_index
	o.kind = p_kind
	o.submitted_on = today.copy() if today != null else null
	o.last_state_change = today.copy() if today != null else null
	return o


static func make_loan(
	p_buying: String,
	p_buyer_index: int,
	p_selling: String,
	p_team_index: int,
	p_squad_index: int,
	p_player_name: String,
	p_wage_share: float,
	today: CareerDate
) -> TransferOffer:
	var o := make(p_buying, p_selling, p_player_name, p_team_index, p_squad_index, Kind.LOAN, today)
	o.buyer_team_index = p_buyer_index
	o.loan_wage_share = p_wage_share
	o.initiated_by_user = true
	o.state = State.BID_SUBMITTED
	return o


func player_key() -> int:
	return player_team_index * 1000 + player_squad_index


func advance_to(new_state: State, today: CareerDate, message: String = "") -> void:
	state = new_state
	last_state_change = today.copy() if today != null else last_state_change
	if message != "":
		response_message = message


## Whether enough days have passed for the other club to answer a live bid.
func club_response_due(today: CareerDate) -> bool:
	if state != State.BID_SUBMITTED or last_state_change == null or today == null:
		return false
	return last_state_change.days_until(today) >= CLUB_RESPONSE_DAYS


func player_response_due(today: CareerDate) -> bool:
	if state != State.TERMS_OFFERED or last_state_change == null or today == null:
		return false
	return last_state_change.days_until(today) >= PLAYER_RESPONSE_DAYS


func is_terminal() -> bool:
	return state == State.COMPLETED or state == State.WITHDRAWN


func is_awaiting_user() -> bool:
	return state == State.CLUB_COUNTERED or state == State.TERMS_COUNTERED or state == State.CLUB_ACCEPTED


func state_name() -> String:
	return STATE_NAMES[clampi(int(state), 0, STATE_NAMES.size() - 1)]


func kind_name() -> String:
	return KIND_NAMES[clampi(int(kind), 0, KIND_NAMES.size() - 1)]


## Fee plus the full wage commitment of the offered contract — the number the
## budget check must actually clear, not just the headline fee.
func total_outlay() -> int:
	var wage_cost: int = wage_offered * 52 * maxi(contract_years_offered, 1)
	return fee_offered + signing_bonus_offered + wage_cost


## The first-season cash cost, which is what the transfer budget gates on.
func first_season_cost() -> int:
	var fee_this_year: int = fee_offered / maxi(instalment_years, 1)
	return fee_this_year + signing_bonus_offered
