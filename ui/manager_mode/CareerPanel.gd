##
## CareerPanel
##
## Base class for every Manager Mode section (Overview, Squad, Tactics, ...).
##
## A panel is a plain RefCounted, not a Node: it is handed a host container and
## fills it. That keeps every section stateless between visits — the career IS
## the state — so a panel can never show a stale read of squad or finances, and
## navigating away and back is always a fresh render.
##
## Subclasses override build(). Everything visual goes through CareerTheme, so
## no panel contains a literal Color or a set_position() call.
##
## Depends on: CareerTheme, CareerSaveData.
## Exposes: build(), title(), refresh_requested signal contract via the host.
##

class_name CareerPanel
extends RefCounted

## Set by ManagerModeRoot before build() so a panel can ask for a re-render or
## a section change without knowing about the root's internals.
var request_refresh: Callable = Callable()
var request_section: Callable = Callable()


## Display name shown in the top bar. Overridden by every subclass.
func title() -> String:
	return "Section"


## Fills `host` with this section's content. `career` is guaranteed non-null —
## ManagerModeRoot does not route to a panel without an active career.
func build(_host: VBoxContainer, _career: CareerSaveData) -> void:
	pass


## --- Shared helpers ------------------------------------------------------------

func refresh() -> void:
	if request_refresh.is_valid():
		request_refresh.call()


func go_to(section: int) -> void:
	if request_section.is_valid():
		request_section.call(section)


## An empty-state message, so a section with nothing in it never renders blank.
func empty_state(host: VBoxContainer, message: String) -> void:
	host.add_child(CareerTheme.spacer(20))
	var l: Label = CareerTheme.muted(message)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host.add_child(l)


## The user's club, or null. Every panel needs this and none should re-derive it.
func club(career: CareerSaveData) -> TeamData:
	return DataLoader.get_team(career.user_team_index)
