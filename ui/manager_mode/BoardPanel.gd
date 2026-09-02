##
## BoardPanel
##
## Board expectations, confidence versus trajectory, facilities, and the
## request system — the place a manager asks for money or upgrades and finds
## out whether they are trusted enough to get them.
##
## Depends on: CareerPanel, CareerTheme, BoardState, CareerManager.
##

class_name BoardPanel
extends CareerPanel


func title() -> String:
	return "Board"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var board: BoardState = career.board
	if board == null:
		empty_state(host, "No board data.")
		return

	host.add_child(CareerTheme.card_root(_confidence_card(board, career, p)))
	host.add_child(CareerTheme.card_root(_facilities_card(board, p)))
	host.add_child(CareerTheme.card_root(_requests_card(board, career, p)))


func _confidence_card(board: BoardState, career: CareerSaveData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Board Confidence")
	body.add_child(CareerTheme.label("Owner: %s" % board.owner_name, p.text_secondary))
	body.add_child(CareerTheme.label(
		"Season expectation: %s" % board.expectation_label(), p.text_primary, p.font_size_heading
	))

	# Confidence and trajectory are separate readings on purpose: the board can
	# rate the manager while still being unhappy with where the season is going.
	var confidence_row: HBoxContainer = CareerTheme.row()
	confidence_row.add_child(CareerTheme.cell("Confidence", 110, p.text_muted))
	confidence_row.add_child(CareerTheme.bar(board.confidence, 200))
	confidence_row.add_child(CareerTheme.label(
		board.confidence_label(), CareerTheme.tint_for_rating(board.confidence)
	))
	body.add_child(confidence_row)

	var trajectory_row: HBoxContainer = CareerTheme.row()
	trajectory_row.add_child(CareerTheme.cell("Trajectory", 110, p.text_muted))
	trajectory_row.add_child(CareerTheme.bar(board.trajectory, 200))
	trajectory_row.add_child(CareerTheme.label(
		"On track" if board.trajectory >= 0.5 else "Below expectation",
		p.positive if board.trajectory >= 0.5 else p.warning
	))
	body.add_child(trajectory_row)

	var league: CompetitionData = career.league_competition()
	if league != null:
		var position: int = league.position_of(career.user_team_index)
		var target: int = board.target_position(league.table.size())
		body.add_child(CareerTheme.label(
			"Currently %s, board target %s." % [_ordinal(position), _ordinal(target)],
			p.positive if position <= target else p.warning
		))

	if board.matches_below_threshold > 0:
		body.add_child(CareerTheme.label(
			"WARNING: confidence has been critical for %d of the last %d matches. Dismissal follows at %d." % [
				board.matches_below_threshold, board.matches_below_threshold, BoardState.SACK_GRACE_MATCHES
			],
			p.danger
		))
	return body


func _facilities_card(board: BoardState, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Facilities")
	body.add_child(_facility_row("Training facilities", board.training_facilities, board, p))
	body.add_child(_facility_row("Youth facilities", board.youth_facilities, board, p))
	body.add_child(_facility_row("Scouting network", board.scouting_range, board, p))
	var stadium: HBoxContainer = CareerTheme.row()
	stadium.add_child(CareerTheme.cell("Stadium capacity", 150, p.text_muted))
	stadium.add_child(CareerTheme.label(str(board.stadium_capacity), p.text_primary))
	body.add_child(stadium)
	return body


func _facility_row(caption: String, level: int, board: BoardState, p: CareerThemePalette) -> HBoxContainer:
	var line: HBoxContainer = CareerTheme.row()
	line.add_child(CareerTheme.cell(caption, 150, p.text_muted))
	line.add_child(CareerTheme.bar(float(level) / 5.0, 140))
	line.add_child(CareerTheme.label(
		"Level %d of 5  (x%.2f)" % [level, board.facility_multiplier(level)], p.text_secondary
	))
	return line


func _requests_card(board: BoardState, career: CareerSaveData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Requests")
	body.add_child(CareerTheme.muted(
		"The board weigh your confidence, the season's trajectory, and what the club can afford. Asking too often is refused outright."
	))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)

	for kind: int in range(BoardState.REQUEST_NAMES.size()):
		var request_kind: BoardState.RequestKind = kind as BoardState.RequestKind
		var recent: bool = board.has_recent_request(request_kind, career.today)
		var b: Button = CareerTheme.button(BoardState.REQUEST_NAMES[kind])
		b.disabled = recent
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			CareerManager.file_board_request(request_kind)
			refresh()
		)
		grid.add_child(b)
		grid.add_child(CareerTheme.muted(
			"Recently asked" if recent else "Available"
		))

	if not board.request_history.is_empty():
		body.add_child(CareerTheme.divider())
		body.add_child(CareerTheme.muted("PREVIOUS REQUESTS"))
		var start: int = maxi(board.request_history.size() - 6, 0)
		for i: int in range(board.request_history.size() - 1, start - 1, -1):
			var entry: Dictionary = board.request_history[i]
			var status: String = String(entry.get("status", "pending"))
			var tint: Color = p.text_muted
			if status == "approved":
				tint = p.positive
			elif status == "partial":
				tint = p.warning
			elif status == "rejected":
				tint = p.danger
			var kind_index: int = int(entry.get("kind", 0))
			var line: HBoxContainer = CareerTheme.row()
			line.add_child(CareerTheme.cell(
				BoardState.REQUEST_NAMES[clampi(kind_index, 0, BoardState.REQUEST_NAMES.size() - 1)],
				220, p.text_secondary
			))
			line.add_child(CareerTheme.cell(status.capitalize(), 90, tint))
			line.add_child(CareerTheme.label(String(entry.get("response", "")), p.text_muted, p.font_size_small))
			body.add_child(line)
	return body


func _ordinal(n: int) -> String:
	var suffix: String = "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
			_:
				suffix = "th"
	return "%d%s" % [n, suffix]
