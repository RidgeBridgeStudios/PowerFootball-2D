class_name DatePicker
extends PopupPanel

signal date_selected(target_date: Dictionary)

var spin_day: SpinBox
var spin_month: SpinBox
var spin_year: SpinBox
var btn_confirm: Button

func _ready() -> void:
	var vbox: VBoxContainer = VBoxContainer.new()
	add_child(vbox)

	var hbox: HBoxContainer = HBoxContainer.new()
	vbox.add_child(hbox)

	spin_day = _create_spin(1, 31, 1, "Day")
	spin_month = _create_spin(1, 12, 1, "Month")
	spin_year = _create_spin(2024, 2035, 2024, "Year")
	hbox.add_child(spin_day)
	hbox.add_child(spin_month)
	hbox.add_child(spin_year)

	btn_confirm = Button.new()
	btn_confirm.text = "Advance To Date"
	btn_confirm.pressed.connect(_on_confirm)
	vbox.add_child(btn_confirm)

func _create_spin(p_min: int, p_max: int, p_val: int, p_prefix: String) -> SpinBox:
	var s: SpinBox = SpinBox.new()
	s.min_value = p_min
	s.max_value = p_max
	s.value = p_val
	s.prefix = p_prefix + ": "
	return s

func open(initial_date: Dictionary) -> void:
	spin_day.value = initial_date.get("day", 1)
	spin_month.value = initial_date.get("month", 1)
	spin_year.value = initial_date.get("year", 2024)
	popup_centered(Vector2i(300, 95))

func _on_confirm() -> void:
	hide()
	date_selected.emit({
		"day": int(spin_day.value),
		"month": int(spin_month.value),
		"year": int(spin_year.value)
	})
