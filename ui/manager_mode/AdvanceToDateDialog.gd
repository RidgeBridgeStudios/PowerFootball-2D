class_name AdvanceToDateDialog
extends PopupPanel

signal date_confirmed(target: CareerDate)

var _spin_year: SpinBox
var _spin_month: SpinBox
var _spin_day: SpinBox

func _ready() -> void:
	exclusive = true
	popup_window = false

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	vbox.add_child(CareerTheme.label("Advance to date", CareerTheme.palette().text_primary, CareerTheme.palette().font_size_heading))
	vbox.add_child(CareerTheme.divider())

	var spinner_row := CareerTheme.row(8)
	vbox.add_child(spinner_row)

	var current_year: int = 2026
	if CareerManager.career != null and CareerManager.career.today != null:
		current_year = CareerManager.career.today.year

	_spin_year = SpinBox.new()
	_spin_year.min_value = current_year
	_spin_year.max_value = current_year + 5
	_spin_year.prefix = "Year: "
	_spin_year.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_spin_month = SpinBox.new()
	_spin_month.min_value = 1
	_spin_month.max_value = 12
	_spin_month.prefix = "Month: "
	_spin_month.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_spin_day = SpinBox.new()
	_spin_day.min_value = 1
	_spin_day.max_value = 31
	_spin_day.prefix = "Day: "
	_spin_day.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	spinner_row.add_child(_spin_year)
	spinner_row.add_child(_spin_month)
	spinner_row.add_child(_spin_day)

	_spin_month.value_changed.connect(_on_month_or_year_changed)
	_spin_year.value_changed.connect(_on_month_or_year_changed)

	var quick_row := CareerTheme.row(6)
	vbox.add_child(quick_row)

	var btn_week: Button = CareerTheme.button("+1 week", false)
	btn_week.pressed.connect(func() -> void: _apply_quick_set(7, 0))
	quick_row.add_child(btn_week)

	var btn_1m: Button = CareerTheme.button("+1 month", false)
	btn_1m.pressed.connect(func() -> void: _apply_quick_set(0, 1))
	quick_row.add_child(btn_1m)

	var btn_3m: Button = CareerTheme.button("+3 months", false)
	btn_3m.pressed.connect(func() -> void: _apply_quick_set(0, 3))
	quick_row.add_child(btn_3m)

	var btn_6m: Button = CareerTheme.button("+6 months", false)
	btn_6m.pressed.connect(func() -> void: _apply_quick_set(0, 6))
	quick_row.add_child(btn_6m)

	vbox.add_child(CareerTheme.divider())

	var bottom_row := CareerTheme.row(8)
	vbox.add_child(bottom_row)

	var cancel_btn: Button = CareerTheme.button("Cancel", false)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(hide)
	bottom_row.add_child(cancel_btn)

	var advance_btn: Button = CareerTheme.button("Advance", true)
	advance_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advance_btn.pressed.connect(_on_advance_pressed)
	bottom_row.add_child(advance_btn)

	_init_default_date()


func _init_default_date() -> void:
	if CareerManager.career != null and CareerManager.career.today != null:
		_set_from_date(CareerManager.career.today.advanced_by(7))
	else:
		_set_from_date(CareerDate.make(2026, 7, 8))


func _set_from_date(base: CareerDate) -> void:
	if base == null:
		return
	_spin_year.value = base.year
	_spin_month.value = base.month
	_update_day_max()
	_spin_day.value = clampi(base.day, 1, int(_spin_day.max_value))


func _apply_quick_set(add_days: int, add_months: int) -> void:
	if CareerManager.career == null or CareerManager.career.today == null:
		return
	var today: CareerDate = CareerManager.career.today
	if add_days > 0:
		_set_from_date(today.advanced_by(add_days))
		return

	if add_months > 0:
		var target_m: int = today.month + add_months
		var target_y: int = today.year + (target_m - 1) / 12
		target_m = ((target_m - 1) % 12) + 1
		var clamped_d: int = clampi(today.day, 1, CareerDate.days_in_month(target_y, target_m))
		_set_from_date(CareerDate.make(target_y, target_m, clamped_d))


func _on_month_or_year_changed(_val: float) -> void:
	_update_day_max()


func _update_day_max() -> void:
	var y: int = int(_spin_year.value)
	var m: int = int(_spin_month.value)
	var max_d: int = CareerDate.days_in_month(y, m)
	_spin_day.max_value = max_d
	if _spin_day.value > max_d:
		_spin_day.value = max_d


func _on_advance_pressed() -> void:
	var y: int = int(_spin_year.value)
	var m: int = int(_spin_month.value)
	var max_d: int = CareerDate.days_in_month(y, m)
	var d: int = clampi(int(_spin_day.value), 1, max_d)
	var target: CareerDate = CareerDate.make(y, m, d)
	hide()
	date_confirmed.emit(target)
