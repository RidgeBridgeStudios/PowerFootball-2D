##
## ClubFinances
##
## One club's books for the current season. Tracks the cash balance, the two
## budgets the manager spends against, and every revenue and cost line that
## moves them.
##
## The distinction that matters: transfer_budget is CASH the manager may commit
## to fees, while wage_budget_weekly is a RECURRING cap. Godot has no decimal
## type worth using here, so every amount is a whole currency unit (pounds) in
## an int — never a float, so a season of arithmetic cannot drift.
##
## Depends on: CareerDate, TeamData, ContractData.
## Exposes: the fields below, from_team(), weekly_wage_bill(), record_income(),
##          record_expense(), can_afford_fee(), can_afford_wage(),
##          project_end_of_season(), reallocate(), post_weekly_cycle().
##

class_name ClubFinances
extends Resource

## Ledger line categories, used for the finances breakdown screen.
enum Line {
	MATCHDAY_REVENUE = 0,
	SPONSORSHIP = 1,
	PRIZE_MONEY = 2,
	PLAYER_SALES = 3,
	WAGES = 4,
	TRANSFER_FEES = 5,
	STAFF_WAGES = 6,
	FACILITIES = 7,
	OTHER = 8,
}

const LINE_NAMES: Array[String] = [
	"Matchday Revenue", "Sponsorship", "Prize Money", "Player Sales",
	"Player Wages", "Transfer Fees", "Staff Wages", "Facilities", "Other"
]

## Average ticket yield per attending supporter, per home match.
const TICKET_YIELD: int = 34
## Share of capacity that actually turns up, scaled by reputation and form.
const BASE_ATTENDANCE_RATE: float = 0.62
## Weekly sponsorship at reputation 0.0 and at 1.0, lerped between.
const SPONSORSHIP_MIN_WEEKLY: int = 12000
const SPONSORSHIP_MAX_WEEKLY: int = 480000
## Prize money awarded per league position, from 1st downward.
const PRIZE_TOP: int = 9000000
const PRIZE_STEP: int = 850000

@export var club_name: String = ""
@export var balance: int = 0
@export var transfer_budget: int = 0
@export var wage_budget_weekly: int = 0
@export var stadium_capacity: int = 24000
## Cumulative season totals per Line, index-aligned with LINE_NAMES.
@export var season_income: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
@export var season_expense: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
## Outstanding transfer instalments still to pay: [{season_year, amount, note}]
@export var payables: Array[Dictionary] = []
## Instalments still owed TO this club from outgoing sales.
@export var receivables: Array[Dictionary] = []
@export var last_weekly_cycle: CareerDate = null
## Set true by the board when it refuses further spending this window.
@export var spending_frozen: bool = false


static func from_team(team: TeamData, capacity: int) -> ClubFinances:
	var f := ClubFinances.new()
	f.club_name = team.team_name
	f.transfer_budget = team.transfer_budget
	f.wage_budget_weekly = team.wage_budget_weekly
	f.stadium_capacity = maxi(capacity, 2000)
	# Opening balance scales with stature: a big club runs a bigger float.
	f.balance = int(round(float(team.transfer_budget) * 0.8 + float(team.wage_budget_weekly) * 12.0))
	return f


## Sum of every squad player's weekly wage, net of any loan subsidy the parent
## club is covering.
func weekly_wage_bill(team: TeamData, contracts: Dictionary) -> int:
	var total: int = 0
	for i: int in range(team.squad.size()):
		var key: int = i
		var contract: ContractData = contracts.get(key, null) as ContractData
		if contract != null:
			var share: float = 1.0
			if contract.is_on_loan and contract.loan_parent_club != club_name:
				share = 1.0 - clampf(contract.loan_wage_subsidy, 0.0, 1.0)
			total += int(round(float(contract.wage_weekly) * share))
		else:
			total += team.squad[i].wage_weekly
	return total


func weekly_staff_bill(team: TeamData) -> int:
	var total: int = 0
	for s: StaffData in team.staff:
		total += s.salary_weekly
	return total


func record_income(line: Line, amount: int) -> void:
	if amount <= 0:
		return
	balance += amount
	season_income[int(line)] += amount


func record_expense(line: Line, amount: int) -> void:
	if amount <= 0:
		return
	balance -= amount
	season_expense[int(line)] += amount


func total_income() -> int:
	var t: int = 0
	for v: int in season_income:
		t += v
	return t


func total_expense() -> int:
	var t: int = 0
	for v: int in season_expense:
		t += v
	return t


func can_afford_fee(fee: int) -> bool:
	return not spending_frozen and fee <= transfer_budget


## A new signing must fit under the recurring wage cap, counted against the
## CURRENT bill — not against the balance.
func can_afford_wage(new_weekly: int, current_bill: int) -> bool:
	return not spending_frozen and (current_bill + new_weekly) <= wage_budget_weekly


## Commits a fee: leaves the transfer budget and the cash balance together, and
## books any instalments beyond the first as future payables.
func commit_fee(fee: int, instalment_years: int, note: String, season_year: int) -> void:
	var years: int = maxi(instalment_years, 1)
	var per_year: int = fee / years
	transfer_budget = maxi(transfer_budget - fee, 0)
	record_expense(Line.TRANSFER_FEES, per_year)
	for y: int in range(1, years):
		payables.append({"season_year": season_year + y, "amount": per_year, "note": note})


func receive_fee(fee: int, instalment_years: int, note: String, season_year: int) -> void:
	var years: int = maxi(instalment_years, 1)
	var per_year: int = fee / years
	transfer_budget += per_year
	record_income(Line.PLAYER_SALES, per_year)
	for y: int in range(1, years):
		receivables.append({"season_year": season_year + y, "amount": per_year, "note": note})


## Home-match gate receipts. Attendance rises with reputation and with the
## club's current league form, so a winning side genuinely earns more.
func book_matchday(reputation: float, form_factor: float) -> int:
	var rate: float = clampf(BASE_ATTENDANCE_RATE + reputation * 0.30 + form_factor * 0.10, 0.25, 1.0)
	var attendance: int = int(round(float(stadium_capacity) * rate))
	var gate: int = attendance * TICKET_YIELD
	record_income(Line.MATCHDAY_REVENUE, gate)
	return gate


func book_sponsorship(reputation: float) -> int:
	var weekly: int = int(round(lerpf(float(SPONSORSHIP_MIN_WEEKLY), float(SPONSORSHIP_MAX_WEEKLY), clampf(reputation, 0.0, 1.0))))
	record_income(Line.SPONSORSHIP, weekly)
	return weekly


static func prize_money_for_position(position: int, team_count: int) -> int:
	var pos: int = clampi(position, 1, maxi(team_count, 1))
	return maxi(PRIZE_TOP - (pos - 1) * PRIZE_STEP, 250000)


## One week of recurring costs. Called by CareerManager every Monday.
func post_weekly_cycle(team: TeamData, contracts: Dictionary, reputation: float, today: CareerDate) -> Dictionary:
	var wages: int = weekly_wage_bill(team, contracts)
	var staff: int = weekly_staff_bill(team)
	var sponsor: int = book_sponsorship(reputation)
	record_expense(Line.WAGES, wages)
	record_expense(Line.STAFF_WAGES, staff)
	last_weekly_cycle = today.copy() if today != null else last_weekly_cycle
	return {"wages": wages, "staff": staff, "sponsorship": sponsor, "balance": balance}


## Straight-line projection to 30 June from the current weekly run rate.
func project_end_of_season(team: TeamData, contracts: Dictionary, reputation: float, today: CareerDate) -> int:
	if today == null:
		return balance
	var season_end: CareerDate = CareerDate.make(today.year if today.month < 7 else today.year + 1, 6, 30)
	var weeks_left: float = maxf(float(today.days_until(season_end)) / 7.0, 0.0)
	var weekly_net: int = book_sponsorship_estimate(reputation) - weekly_wage_bill(team, contracts) - weekly_staff_bill(team)
	var outstanding: int = 0
	for p: Dictionary in payables:
		outstanding += int(p.get("amount", 0))
	for r: Dictionary in receivables:
		outstanding -= int(r.get("amount", 0))
	return balance + int(round(float(weekly_net) * weeks_left)) - outstanding


## Sponsorship value without booking it — used by the projection above.
func book_sponsorship_estimate(reputation: float) -> int:
	return int(round(lerpf(float(SPONSORSHIP_MIN_WEEKLY), float(SPONSORSHIP_MAX_WEEKLY), clampf(reputation, 0.0, 1.0))))


## Moves money between the two budgets. Returns false if the shift would push
## either side negative. Board approval is enforced by the caller, not here.
func reallocate(transfer_delta: int) -> bool:
	# Converting transfer cash into wage headroom is lossy: one unit of weekly
	# wage costs roughly a season of that wage in cash.
	var wage_delta: int = -transfer_delta / 52
	if transfer_budget + transfer_delta < 0:
		return false
	if wage_budget_weekly + wage_delta < 0:
		return false
	transfer_budget += transfer_delta
	wage_budget_weekly += wage_delta
	return true


## Rolls instalments due this season into the books and clears them.
func settle_due_instalments(season_year: int) -> void:
	var remaining_pay: Array[Dictionary] = []
	for p: Dictionary in payables:
		if int(p.get("season_year", 0)) <= season_year:
			record_expense(Line.TRANSFER_FEES, int(p.get("amount", 0)))
		else:
			remaining_pay.append(p)
	payables = remaining_pay

	var remaining_rec: Array[Dictionary] = []
	for r: Dictionary in receivables:
		if int(r.get("season_year", 0)) <= season_year:
			record_income(Line.PLAYER_SALES, int(r.get("amount", 0)))
		else:
			remaining_rec.append(r)
	receivables = remaining_rec


func reset_season_ledger() -> void:
	season_income = [0, 0, 0, 0, 0, 0, 0, 0, 0]
	season_expense = [0, 0, 0, 0, 0, 0, 0, 0, 0]
