##
## PressOffice
##
## Pure quote-generation utility. Instantiated on demand with PressOffice.new()
## — no Node knowledge, no scene tree, no autoload. Given a ManagerData and a
## PressContext, generate_quote() selects a base sentence for the event/result
## pairing, then walks the manager's traits in a fixed order — each trait
## either prepends, replaces, or appends a fragment — and joins the result
## into a 1-3 sentence String.
##
## Depends on: ManagerData.
## Exposes: PressContext, generate_quote(data, ctx).
##

class_name PressOffice
extends RefCounted


class PressContext:
	## "post_match"  "pre_match"  "transfer_speculation"  "injury_update"
	## "touchline_goal"  "touchline_goal_conceded"  "touchline_shift"
	var event: String = "post_match"
	## "win"  "loss"  "draw"
	var match_result: String = "draw"
	## Positive = won by this margin; negative = lost by this margin.
	var goal_diff: int = 0
	## Name of the opponent.
	var opponent_name: String = ""
	## True if this was a derby, promotion decider, or cup final.
	var is_big_game: bool = false
	## Optional name of a player being discussed (injuries, signings).
	var player_name: String = ""


## --- Post-match win ---------------------------------------------------------

const POST_WIN_BASE: Array[String] = [
	"The result speaks for itself.",
	"We got what we came for. Three points.",
	"The boys were absolutely brilliant today.",
	"A hard-earned three points and I couldn't be prouder.",
	"We were clinical when it mattered. That's the standard I demand.",
]
const HOTHEAD_WIN_PREPEND: Array[String] = [
	"I don't want to make this about the referee, but some of those decisions...",
	"We won in spite of a lot of things today. I'll leave it at that.",
]
const VISIONARY_WIN_APPEND: Array[String] = [
	"The system worked exactly as we rehearsed it. Every movement was intentional.",
	"When the group buys into the idea completely, you see what's possible.",
]
const PRAGMATIST_WIN_REPLACE: Array[String] = [
	"We got three points. Everything else is noise.",
	"Job done. Next.",
]
const SENTIMENTAL_WIN_APPEND: Array[String] = [
	"The fans have been with us since before any of this. Tonight was for them.",
	"This club means everything to me. Every win feels personal.",
]
const MEDIASAVVY_WIN_BLAND_BASE: String = "The result speaks for itself."
const MEDIASAVVY_WIN_APPEND: String = "We're pleased with the result. We take it one game at a time."
const VOLATILE_WIN_EFFUSIVE: String = "I'm going to say it — that was one of the best performances I've seen from this group. Truly special."
const VOLATILE_WIN_MUTED: String = "It's three points. I don't get carried away. We train Monday."

## --- Post-match loss ---------------------------------------------------------

const POST_LOSS_BASE: Array[String] = [
	"We didn't perform to our standards today.",
	"The result is disappointing. The reaction will define us.",
	"There are no excuses. We were second best.",
	"They deserved it. We have to be honest about that.",
]
const HOTHEAD_LOSS_REPLACE: Array[String] = [
	"The referee robbed us and I'll say it clearly. That was not acceptable.",
	"I've never seen officiating like that in my career. Absolutely scandalous.",
]
const HOTHEAD_LOSS_BIG_GAME: String = "In a match of this magnitude, the decisions have to be right. They weren't. Not even close."
const LOYALIST_LOSS_REPLACE: Array[String] = [
	"I will not put this on the players. Every one of them gave everything.",
	"The responsibility sits with me. Full stop.",
]
const DISCIPLINARIAN_LOSS_APPEND: Array[String] = [
	"We'll review the tape. There will be conversations this week.",
	"The midfield was disorganised and we know it. That gets addressed.",
]
const MINDGAMES_LOSS_GENERIC: String = "I'll give them credit. They executed their plan."
const MINDGAMES_LOSS_NAMED_TEMPLATE: String = "Credit to %s. They were well-organised."
const VOLATILE_LOSS_SCATHING: String = "That performance was embarrassing. I'll be direct with the group."
const VOLATILE_LOSS_CALM: String = "Losses happen. The important thing is we stay together. We will."
const IDEALIST_LOSS_APPEND: String = "We won't change who we are because of one result. Our way is the right way."

## --- Post-match draw ---------------------------------------------------------

const POST_DRAW_BASE: Array[String] = [
	"A point away from home is not nothing.",
	"We'll take it and move on.",
	"Both teams had their moments. A fair result.",
	"A draw when we needed a win is hard to accept, but we move forward.",
]
const PRAGMATIST_DRAW_REPLACE: String = "A point. Fine. Onto the next."
const VISIONARY_DRAW_APPEND: String = "The structure was there. The goals just weren't kind to us today."
const VOLATILE_DRAW_ANNOYED: String = "A draw feels like a defeat tonight. It really does."
const VOLATILE_DRAW_PHILOSOPHICAL: String = "Football gives and takes. Today it gave us a point and took two."

## --- Pre-match ---------------------------------------------------------------

const PRE_MATCH_BASE: Array[String] = [
	"It's going to be a tough match.",
	"We respect the opposition and we're preparing well.",
	"Every game at this level demands full focus.",
]
const MINDGAMES_PRE_PREPEND: Array[String] = [
	"I've been studying them carefully. There are patterns I find... interesting.",
	"They're a good side. Very predictable, but good.",
]
const MINDGAMES_PRE_BIG_GAME: String = "I think we know a lot more about them than they know about us."
const VISIONARY_PRE_APPEND: String = "Our principles don't change based on the opponent. That's the foundation."
const MEDIASAVVY_PRE_REPLACE_ALL: String = "We're focused and ready. It'll be a good game. We're looking forward to it."
const IDEALIST_PRE_APPEND: String = "We play our football. Whoever's in front of us, we play our football."

## --- Transfer speculation -----------------------------------------------------

const TRANSFER_BASE: Array[String] = [
	"I don't discuss other clubs' players in the press.",
	"Our focus is entirely on the squad we have right now.",
	"Transfers happen at the right time, through the right channels.",
]
const HOTHEAD_TRANSFER_REPLACE: String = "If the board gives me what I need, you'll see the signings. If not — we manage."
const MEDIASAVVY_TRANSFER_REPLACE: String = "No comment on transfer speculation. The club handles these things appropriately."
const SENTIMENTAL_TRANSFER_APPEND: String = "When we bring someone in, they have to understand what this club means. That matters more to me than ability."

## --- Injury update -------------------------------------------------------------

const INJURY_BASE: Array[String] = [
	"[player] is being assessed and we'll know more in the coming days.",
	"We're monitoring the situation closely. We don't want to rush anything.",
	"These things happen in football. We have the depth to cope.",
]
const LOYALIST_INJURY_APPEND: String = "The most important thing is that he recovers fully. Results can wait."
const DISCIPLINARIAN_INJURY_APPEND: String = "The others know what's expected. The standard doesn't drop."

## --- Touchline: goal scored --------------------------------------------------

const TOUCHLINE_GOAL_BASE: Array[String] = [
	"YES! Come on!",
	"That's it! Keep pushing!",
	"Beautiful! Don't stop now!",
	"Get back in position! Reset!",
]
const HOTHEAD_GOAL_PREPEND: Array[String] = [
	"THAT'S what I'm talking about!",
	"Finally! NOW we play!",
]
const VISIONARY_GOAL_APPEND: Array[String] = [
	"Exactly as we drilled it. Exactly.",
	"The movement created that. Remember it.",
]
const PRAGMATIST_GOAL_REPLACE: Array[String] = [
	"Good. Stay organised.",
	"One more. Same focus.",
]
const SENTIMENTAL_GOAL_APPEND: Array[String] = [
	"This crowd is unbelievable. Feed off them!",
	"For each other! Always for each other!",
]
const VOLATILE_GOAL_EFFUSIVE: String = "INCREDIBLE! I love this group! I LOVE this group!"
const VOLATILE_GOAL_MUTED: String = "Good. Don't celebrate too long."
const DISCIPLINARIAN_GOAL_APPEND: String = "Back in shape. NOW. We don't switch off."

## --- Touchline: goal conceded ------------------------------------------------

const TOUCHLINE_CONCEDED_BASE: Array[String] = [
	"Wake UP! That was unacceptable!",
	"Hold the line! Stay compact!",
	"Concentrate! Defensive shape, now!",
	"Don't panic. Stick to the plan.",
]
const HOTHEAD_CONCEDED_REPLACE: Array[String] = [
	"That is EMBARRASSING! Sort yourselves out!",
	"How?! HOW does that happen?!",
]
const LOYALIST_CONCEDED_APPEND: String = "I believe in you. Fix it together."
const DISCIPLINARIAN_CONCEDED_REPLACE: Array[String] = [
	"Concentration. Shape. Do your jobs.",
	"That will not happen again. I promise you that.",
]
const IDEALIST_CONCEDED_APPEND: String = "Our way. Keep playing our way."
const VOLATILE_CONCEDED_FURIOUS: String = "That was SOFT. Completely soft. Unacceptable."
const VOLATILE_CONCEDED_CALM: String = "It's fine. Breathe. We've been here before."

## --- Touchline: tactical shift -----------------------------------------------

const TOUCHLINE_SHIFT_BASE: Array[String] = [
	"New shape! Everyone adjust!",
	"Switch now! You know the positions!",
	"Formation change! Trust the system!",
]
const VISIONARY_SHIFT_APPEND: Array[String] = [
	"This was always the plan for this moment.",
	"We rehearsed this. Execute it.",
]
const PRAGMATIST_SHIFT_REPLACE: Array[String] = [
	"Adapt or lose. Simple.",
	"New plan. Same commitment.",
]
const HOTHEAD_SHIFT_PREPEND: Array[String] = [
	"Right, enough of this —",
	"I've seen enough —",
]
const IDEALIST_SHIFT_APPEND: String = "The shape changes. The principles never do."


func generate_quote(data: ManagerData, ctx: PressContext) -> String:
	if data == null or ctx == null:
		return ""

	match ctx.event:
		"post_match":
			match ctx.match_result:
				"win":
					return _post_match_win(data, ctx)
				"loss":
					return _post_match_loss(data, ctx)
				_:
					return _post_match_draw(data, ctx)
		"pre_match":
			return _pre_match(data, ctx)
		"transfer_speculation":
			return _transfer_speculation(data, ctx)
		"injury_update":
			return _injury_update(data, ctx)
		"touchline_goal":
			return _touchline_goal(data, ctx)
		"touchline_goal_conceded":
			return _touchline_conceded(data, ctx)
		"touchline_shift":
			return _touchline_shift(data, ctx)
		_:
			return ""


func _post_match_win(data: ManagerData, _ctx: PressContext) -> String:
	var prepend: String = ""
	var base: String = _pick(POST_WIN_BASE)
	var append: Array[String] = []

	if data.has_trait(1): # HotHead
		prepend = _pick(HOTHEAD_WIN_PREPEND)
	if data.has_trait(8): # Visionary
		append.append(_pick(VISIONARY_WIN_APPEND))
	if data.has_trait(4): # Pragmatist
		base = _pick(PRAGMATIST_WIN_REPLACE)
	if data.has_trait(64): # Sentimental
		append.append(_pick(SENTIMENTAL_WIN_APPEND))
	if data.has_trait(128): # MediaSavvy
		base = MEDIASAVVY_WIN_BLAND_BASE
		append.append(MEDIASAVVY_WIN_APPEND)
	if data.has_trait(256): # Volatile
		base = VOLATILE_WIN_EFFUSIVE if randf() < 0.5 else VOLATILE_WIN_MUTED

	return _assemble(prepend, base, append)


func _post_match_loss(data: ManagerData, ctx: PressContext) -> String:
	var prepend: String = ""
	var base: String = _pick(POST_LOSS_BASE)
	var append: Array[String] = []

	if data.has_trait(1): # HotHead
		base = HOTHEAD_LOSS_BIG_GAME if ctx.is_big_game else _pick(HOTHEAD_LOSS_REPLACE)
	if data.has_trait(2): # Loyalist
		base = _pick(LOYALIST_LOSS_REPLACE)
	if data.has_trait(16): # Disciplinarian
		append.append(_pick(DISCIPLINARIAN_LOSS_APPEND))
	if data.has_trait(32): # MindGames
		if ctx.opponent_name != "":
			append.append(MINDGAMES_LOSS_NAMED_TEMPLATE % ctx.opponent_name)
		else:
			append.append(MINDGAMES_LOSS_GENERIC)
	if data.has_trait(256): # Volatile
		base = VOLATILE_LOSS_SCATHING if randf() < 0.5 else VOLATILE_LOSS_CALM
	if data.has_trait(512): # Idealist
		append.append(IDEALIST_LOSS_APPEND)

	return _assemble(prepend, base, append)


func _post_match_draw(data: ManagerData, _ctx: PressContext) -> String:
	var prepend: String = ""
	var base: String = _pick(POST_DRAW_BASE)
	var append: Array[String] = []

	if data.has_trait(4): # Pragmatist
		base = PRAGMATIST_DRAW_REPLACE
	if data.has_trait(8): # Visionary
		append.append(VISIONARY_DRAW_APPEND)
	if data.has_trait(256): # Volatile
		base = VOLATILE_DRAW_ANNOYED if randf() < 0.5 else VOLATILE_DRAW_PHILOSOPHICAL

	return _assemble(prepend, base, append)


func _pre_match(data: ManagerData, ctx: PressContext) -> String:
	var prepend: String = ""
	var base: String = _pick(PRE_MATCH_BASE)
	var append: Array[String] = []

	if data.has_trait(32): # MindGames
		prepend = MINDGAMES_PRE_BIG_GAME if ctx.is_big_game else _pick(MINDGAMES_PRE_PREPEND)
	if data.has_trait(8): # Visionary
		append.append(VISIONARY_PRE_APPEND)
	if data.has_trait(128): # MediaSavvy — replaces the whole quote built so far.
		prepend = ""
		base = MEDIASAVVY_PRE_REPLACE_ALL
		append.clear()
	if data.has_trait(512): # Idealist
		append.append(IDEALIST_PRE_APPEND)

	return _assemble(prepend, base, append)


func _transfer_speculation(data: ManagerData, ctx: PressContext) -> String:
	var prepend: String = ""
	var base: String = _pick(TRANSFER_BASE)
	var append: Array[String] = []

	if data.has_trait(1): # HotHead
		base = HOTHEAD_TRANSFER_REPLACE
	if data.has_trait(128): # MediaSavvy
		base = MEDIASAVVY_TRANSFER_REPLACE
	if data.has_trait(64): # Sentimental
		append.append(SENTIMENTAL_TRANSFER_APPEND)

	# Neither the base pool nor any trait fragment above carries a signing
	# placeholder to fill — a named target only ever surfaces through a
	# manager's own trait voice, never a generic line, so there is nothing
	# further to insert here even when ctx.player_name is set.
	return _assemble(prepend, base, append)


func _injury_update(data: ManagerData, ctx: PressContext) -> String:
	var prepend: String = ""
	var subject: String = ctx.player_name if ctx.player_name != "" else "The player"
	var base: String = _pick(INJURY_BASE).replace("[player]", subject)
	var append: Array[String] = []

	if data.has_trait(2): # Loyalist
		append.append(LOYALIST_INJURY_APPEND)
	if data.has_trait(16): # Disciplinarian
		append.append(DISCIPLINARIAN_INJURY_APPEND)

	return _assemble(prepend, base, append)


func _touchline_goal(data: ManagerData, _ctx: PressContext) -> String:
	var prepend: String = ""
	var base: String = _pick(TOUCHLINE_GOAL_BASE)
	var append: Array[String] = []

	if data.has_trait(1): # HotHead
		prepend = _pick(HOTHEAD_GOAL_PREPEND)
	if data.has_trait(4): # Pragmatist
		base = _pick(PRAGMATIST_GOAL_REPLACE)
	if data.has_trait(8): # Visionary
		append.append(_pick(VISIONARY_GOAL_APPEND))
	if data.has_trait(16): # Disciplinarian
		append.append(DISCIPLINARIAN_GOAL_APPEND)
	if data.has_trait(64): # Sentimental
		append.append(_pick(SENTIMENTAL_GOAL_APPEND))
	if data.has_trait(256): # Volatile
		base = VOLATILE_GOAL_EFFUSIVE if randf() < 0.6 else VOLATILE_GOAL_MUTED

	return _assemble(prepend, base, append)


func _touchline_conceded(data: ManagerData, _ctx: PressContext) -> String:
	var prepend: String = ""
	var base: String = _pick(TOUCHLINE_CONCEDED_BASE)
	var append: Array[String] = []

	if data.has_trait(1): # HotHead
		base = _pick(HOTHEAD_CONCEDED_REPLACE)
	if data.has_trait(2): # Loyalist
		append.append(LOYALIST_CONCEDED_APPEND)
	if data.has_trait(16): # Disciplinarian
		base = _pick(DISCIPLINARIAN_CONCEDED_REPLACE)
	if data.has_trait(256): # Volatile
		base = VOLATILE_CONCEDED_FURIOUS if randf() < 0.5 else VOLATILE_CONCEDED_CALM
	if data.has_trait(512): # Idealist
		append.append(IDEALIST_CONCEDED_APPEND)

	return _assemble(prepend, base, append)


func _touchline_shift(data: ManagerData, _ctx: PressContext) -> String:
	var prepend: String = ""
	var base: String = _pick(TOUCHLINE_SHIFT_BASE)
	var append: Array[String] = []

	if data.has_trait(1): # HotHead
		prepend = _pick(HOTHEAD_SHIFT_PREPEND)
	if data.has_trait(4): # Pragmatist
		base = _pick(PRAGMATIST_SHIFT_REPLACE)
	if data.has_trait(8): # Visionary
		append.append(_pick(VISIONARY_SHIFT_APPEND))
	if data.has_trait(512): # Idealist
		append.append(IDEALIST_SHIFT_APPEND)

	return _assemble(prepend, base, append)


func _pick(pool: Array[String]) -> String:
	return pool[randi() % pool.size()]


func _assemble(prepend: String, base: String, append: Array[String]) -> String:
	var parts: Array[String] = []
	if prepend != "":
		parts.append(prepend)
	parts.append(base)
	for fragment: String in append:
		parts.append(fragment)
	return " ".join(parts)
