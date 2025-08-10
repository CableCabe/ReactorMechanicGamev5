extends HBoxContainer

@onready var eu_label: Label = $EuLabel
@onready var money_label: Label = $MoneyLabel
@onready var fuel_label: Label = $Fuel
@onready var coolant_label: Label = $Coolant

func _ready() -> void:
	GameState.state_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	eu_label.text = "Eu: %.1f" % GameState.eu
	money_label.text = "$$: %.1f" % GameState.money
	fuel_label.text = "Fuel: %.1fml" % GameState.fuel
	coolant_label.text = "Coolant: %.1fml" % GameState.coolant
