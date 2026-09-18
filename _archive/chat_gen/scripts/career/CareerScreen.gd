class_name CareerScreen
extends Control

signal day_advanced(new_date: Dictionary)
signal simulation_stopped(reason: String)

@export var date_slide_offset: float = 14.0
@export var active_button_color: Color = Color(0.85, 0.85, 0.85, 0.9)
@export var vignette_flash_duration: float = 0.25

@onready var continue_button: Button = $ContinueButton
@onready var date_slot: Control = $MarginContainer/VBoxContainer/TopBar/DateSlot
@onready var date_label: Label = $MarginContainer/VBoxContainer/TopBar/DateSlot/DateLabel
@onready var speed_label: Label = $MarginContainer/VBoxContainer/TopBar/SpeedLabel
@onready var inbox_button: InboxButton = $MarginContainer/VBoxContainer/TopBar/InboxButton
@onready var schedule_container: VBoxContainer = $MarginContainer/VBoxContainer/ScheduleContainer
@onready var sim_manager: SimulationManager = $SimulationManager
@onready var mail_popup: Panel = $MailPopup
@onready var mail_title: Label = $MailPopup/VBoxContainer/MailTitle
@onready var mail_body: Label = $MailPopup/VBoxContainer/MailBody
@onready var mail_ok_button: Button = $MailPopup/VBoxContainer/MailOkButton
@onready var inbox_ui: InboxUI = $InboxUI
@onready var vignette_rect: ColorRect = $VignetteRect
@onready var date_picker: DatePicker = $DatePicker

var button_pulse_tween: Tween
var date_anim_tween: Tween
var schedule_rows: Array[ScheduleRow] = []

var ellipsis_step: int = 0
var ellipsis_timer: float = 0.0

const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"
]

func _ready() -> void:
	if not sim_manager:
		sim_manager = SimulationManager.new()
		sim_manager.name = "SimulationManager"
		add_child(sim_manager)

	if not vignette_rect:
		vignette_rect = ColorRect.new()
		vignette_rect.name = "VignetteRect"
		vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		vignette_rect.color = Color.BLACK
		vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vignette_rect.modulate.a = 0.0
		add_child(vignette_rect)
	else:
		vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vignette_rect.modulate.a = 0.0

	if not date_picker:
		date_picker = DatePicker.new()
		date_picker.name = "DatePicker"
		add_child(date_picker)

	if not inbox_ui:
		inbox_ui = InboxUI.new()
		inbox_ui.name = "InboxUI"
		inbox_ui.set_anchors_preset(Control.PRESET_CENTER)
		add_child(inbox_ui)

	_setup_continue_menu()
	mail_ok_button.pressed.connect(_on_mail_ok_pressed)
	inbox_button.pressed.connect(_on_inbox_button_pressed)
	date_picker.date_selected.connect(_on_target_date_selected)

	sim_manager.day_processed.connect(_on_day_processed)
	sim_manager.simulation_halted.connect(_on_simulation_halted)
	sim_manager.state_changed.connect(_on_sim_state_changed)
	sim_manager.inbox_updated.connect(_on_inbox_updated)

	mail_popup.hide()
	_update_date_label_instant()
	_update_speed_label()
	_seed_default_events()
	_populate_schedule()

func _setup_continue_menu() -> void:
	continue_button.pressed.connect(_on_continue_button_pressed)
	var popup: PopupMenu = continue_button.get_popup()
	popup.clear()
	popup.add_item("Continue (1×)", 0)
	popup.add_item("Continue (2×)", 1)
	popup.add_item("Continue (3×)", 2)
	popup.add_separator()
	popup.add_item("Advance to date…", 3)
	popup.id_pressed.connect(_on_continue_menu_id_pressed)

func _process(delta: float) -> void:
	if sim_manager.sim_state == SimState.State.RUNNING or sim_manager.sim_state == SimState.State.ADVANCING_TO_DATE:
		_animate_ellipsis(delta)

func _animate_ellipsis(delta: float) -> void:
	ellipsis_timer += delta
	if ellipsis_timer >= 0.2:
		ellipsis_timer = 0.0
		ellipsis_step = (ellipsis_step + 1) % 4
		var dots: String = ".".repeat(ellipsis_step)
		continue_button.text = "Stop" + dots

func _on_continue_button_pressed() -> void:
	if sim_manager.sim_state == SimState.State.RUNNING or sim_manager.sim_state == SimState.State.ADVANCING_TO_DATE:
		sim_manager.stop_simulation("manual")
	else:
		sim_manager.start_simulation(1.0)

func _on_continue_menu_id_pressed(id: int) -> void:
	match id:
		0: sim_manager.start_simulation(1.0)
		1: sim_manager.start_simulation(2.0)
		2: sim_manager.start_simulation(3.0)
		3: date_picker.open(sim_manager.current_date)

func _on_target_date_selected(target_date: Dictionary) -> void:
	sim_manager.advance_to_date(target_date, 2.0)

func _on_sim_state_changed(state: SimState.State) -> void:
	_update_speed_label()
	if state == SimState.State.RUNNING or state == SimState.State.ADVANCING_TO_DATE:
		continue_button.text = "Stop"
		continue_button.modulate = active_button_color
		_start_button_pulse()
	else:
		continue_button.text = "Continue"
		continue_button.modulate = Color.WHITE
		_stop_button_pulse()

func _on_day_processed(new_date: Dictionary) -> void:
	day_advanced.emit(new_date)
	_animate_date_transition(new_date)

func _on_simulation_halted(reason: String, event: SimEvent) -> void:
	simulation_stopped.emit(reason)
	if event != null:
		_play_vignette_flash()
		_highlight_event_row(event)
		var custom_screen: PackedScene = event.get_screen()
		if custom_screen:
			var scr: Node = custom_screen.instantiate()
			add_child(scr)
		else:
			_show_mail_popup(event)

func _on_inbox_updated(inbox: Array[SimEvent], unread_count: int) -> void:
	inbox_button.set_unread_count(unread_count)
	inbox_ui.refresh(inbox)

func _on_inbox_button_pressed() -> void:
	sim_manager.mark_inbox_read()
	inbox_ui.visible = not inbox_ui.visible

func _format_date(date: Dictionary) -> String:
	return "%02d %s %04d" % [date["day"], MONTH_NAMES[date["month"] - 1], date["year"]]

func _update_date_label_instant() -> void:
	date_label.text = _format_date(sim_manager.current_date)

func _update_speed_label() -> void:
	if sim_manager.sim_state == SimState.State.RUNNING or sim_manager.sim_state == SimState.State.ADVANCING_TO_DATE:
		speed_label.text = "▶ %.0f×" % sim_manager.speed_multiplier
	else:
		speed_label.text = ""

func _animate_date_transition(new_date: Dictionary) -> void:
	if date_anim_tween and date_anim_tween.is_valid():
		date_anim_tween.kill()

	date_anim_tween = create_tween()
	var step_time: float = maxf((sim_manager.tick_interval / sim_manager.speed_multiplier) * 0.25, 0.02)

	date_anim_tween.tween_property(date_label, ^"position:y", -date_slide_offset, step_time)
	date_anim_tween.parallel().tween_property(date_label, ^"modulate:a", 0.0, step_time)
	date_anim_tween.tween_callback(func() -> void:
		date_label.text = _format_date(new_date)
		date_label.position.y = date_slide_offset
	)
	date_anim_tween.tween_property(date_label, ^"position:y", 0.0, step_time)
	date_anim_tween.parallel().tween_property(date_label, ^"modulate:a", 1.0, step_time)

func _finish_date_animation() -> void:
	if date_anim_tween and date_anim_tween.is_valid():
		date_anim_tween.kill()
	date_label.position.y = 0.0
	date_label.modulate.a = 1.0
	_update_date_label_instant()

func _play_vignette_flash() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(vignette_rect, ^"modulate:a", 0.4, 0.08)
	tw.tween_property(vignette_rect, ^"modulate:a", 0.0, vignette_flash_duration)

func _start_button_pulse() -> void:
	continue_button.pivot_offset = continue_button.size * 0.5
	if button_pulse_tween and button_pulse_tween.is_valid():
		button_pulse_tween.kill()
	button_pulse_tween = create_tween().set_loops()
	button_pulse_tween.tween_property(continue_button, ^"scale", Vector2(1.04, 1.04), 0.25).set_trans(Tween.TRANS_SINE)
	button_pulse_tween.tween_property(continue_button, ^"scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE)

func _stop_button_pulse() -> void:
	if button_pulse_tween and button_pulse_tween.is_valid():
		button_pulse_tween.kill()
	continue_button.scale = Vector2.ONE

func _populate_schedule() -> void:
	for child in schedule_container.get_children():
		child.queue_free()
	schedule_rows.clear()

	for ev in sim_manager.event_queue:
		var row: ScheduleRow = ScheduleRow.new(ev)
		schedule_container.add_child(row)
		schedule_rows.append(row)

func _highlight_event_row(ev: SimEvent) -> void:
	for row in schedule_rows:
		if row.event_ref == ev or row.event_id == ev.id:
			row.flash()
			break

func _show_mail_popup(ev: SimEvent) -> void:
	var prio_name: String = Priority.Type.keys()[ev.priority]
	mail_title.text = "[%s] %s" % [prio_name, ev.title]
	mail_body.text = ev.description
	mail_popup.show()

func _on_mail_ok_pressed() -> void:
	mail_popup.hide()
	sim_manager.stop_simulation("acknowledged")

func _seed_default_events() -> void:
	sim_manager.clear_queue()
	sim_manager.queue_event(SimEvent.new({"day": 13, "month": 8, "year": 2024}, Priority.Type.INFO, "Scouting Report: Striker Target", "Scouts have identified an emerging talent."))
	sim_manager.queue_event(BoardMeetingEvent.new({"day": 15, "month": 8, "year": 2024}, "Season Objectives"))
	sim_manager.queue_event(InjuryEvent.new({"day": 16, "month": 8, "year": 2024}, "Marco Silva", "Sprained Ankle", 10))
	sim_manager.queue_event(TransferOfferEvent.new({"day": 18, "month": 8, "year": 2024}, "James Ward", "Arsenal FC", 14000000))
	sim_manager.queue_event(MatchEvent.new({"day": 22, "month": 8, "year": 2024}, "Rival United", true))
