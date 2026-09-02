##
## CareerDate
##
## Calendar date value type for the career layer. Proleptic Gregorian, with
## leap years, so a season can be advanced a day at a time and still land on
## real weekdays — the training week, transfer windows, and fixture scheduling
## all key off day_of_week()/to_ordinal().
##
## Deliberately a Resource (not a Dictionary) so it serialises with the rest of
## the career save and can be @export-ed onto other career resources.
##
## Depends on: nothing.
## Exposes: make(), to_ordinal(), from_ordinal(), advanced_by(), days_until(),
##          day_of_week(), to_iso(), to_display(), equals(), is_before().
##

class_name CareerDate
extends Resource

const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"
]
const DAY_NAMES: Array[String] = [
	"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
]

@export var year: int = 2026
@export var month: int = 7
@export var day: int = 1


static func make(p_year: int, p_month: int, p_day: int) -> CareerDate:
	var d := CareerDate.new()
	d.year = p_year
	d.month = clampi(p_month, 1, 12)
	d.day = clampi(p_day, 1, days_in_month(p_year, clampi(p_month, 1, 12)))
	return d


static func is_leap_year(p_year: int) -> bool:
	if p_year % 400 == 0:
		return true
	if p_year % 100 == 0:
		return false
	return p_year % 4 == 0


static func days_in_month(p_year: int, p_month: int) -> int:
	match p_month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			return 29 if is_leap_year(p_year) else 28
		_:
			return 30


## Days since 0001-01-01. The single arithmetic primitive every other date
## operation is built on — never step month/day fields by hand.
func to_ordinal() -> int:
	var y: int = year - 1
	var total: int = y * 365 + y / 4 - y / 100 + y / 400
	for m: int in range(1, month):
		total += days_in_month(year, m)
	return total + day


static func from_ordinal(ordinal: int) -> CareerDate:
	var remaining: int = maxi(ordinal, 1)
	var y: int = 1
	while true:
		var year_len: int = 366 if is_leap_year(y) else 365
		if remaining <= year_len:
			break
		remaining -= year_len
		y += 1
	var m: int = 1
	while true:
		var month_len: int = days_in_month(y, m)
		if remaining <= month_len:
			break
		remaining -= month_len
		m += 1
	return CareerDate.make(y, m, remaining)


func advanced_by(days: int) -> CareerDate:
	return CareerDate.from_ordinal(to_ordinal() + days)


func days_until(other: CareerDate) -> int:
	if other == null:
		return 0
	return other.to_ordinal() - to_ordinal()


## 0 = Monday ... 6 = Sunday. 0001-01-01 was a Monday in the proleptic calendar.
func day_of_week() -> int:
	return (to_ordinal() - 1) % 7


func day_name() -> String:
	return DAY_NAMES[day_of_week()]


func month_name() -> String:
	return MONTH_NAMES[clampi(month, 1, 12) - 1]


func to_iso() -> String:
	return "%04d-%02d-%02d" % [year, month, day]


func to_display() -> String:
	return "%s %d %s %d" % [DAY_NAMES[day_of_week()].substr(0, 3), day, month_name().substr(0, 3), year]


func equals(other: CareerDate) -> bool:
	if other == null:
		return false
	return year == other.year and month == other.month and day == other.day


func is_before(other: CareerDate) -> bool:
	if other == null:
		return false
	return to_ordinal() < other.to_ordinal()


func copy() -> CareerDate:
	return CareerDate.make(year, month, day)


static func from_iso(iso: String) -> CareerDate:
	var parts: PackedStringArray = iso.split("-")
	if parts.size() < 3:
		return CareerDate.make(2026, 7, 1)
	return CareerDate.make(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())
