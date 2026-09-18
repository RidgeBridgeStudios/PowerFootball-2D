class_name TransferOfferEvent
extends SimEvent

var player_name: String = ""
var bidding_club: String = ""
var offer_amount: int = 0

func _init(p_date: Dictionary = {}, p_player_name: String = "Player", p_bidding_club: String = "Club", p_amount: int = 5000000) -> void:
	var t: String = "Transfer Bid: " + p_player_name
	var d: String = "%s have offered £%d for %s." % [p_bidding_club, p_amount, p_player_name]
	super(p_date, Priority.Type.URGENT, t, d)
	player_name = p_player_name
	bidding_club = p_bidding_club
	offer_amount = p_amount

func serialize() -> Dictionary:
	var data: Dictionary = super.serialize()
	data["player_name"] = player_name
	data["bidding_club"] = bidding_club
	data["offer_amount"] = offer_amount
	return data

func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	player_name = data.get("player_name", "")
	bidding_club = data.get("bidding_club", "")
	offer_amount = data.get("offer_amount", 0)
