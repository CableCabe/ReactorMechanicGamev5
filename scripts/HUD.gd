extends HBoxContainer

@onready var eu_label: Label = $EuLabel
@onready var money_label: Label = $MoneyLabel
@onready var fuel_label: Label = $Fuel
@onready var coolant_label: Label = $Coolant

func _ready() -> void:
	GameState.eu_changed.connect(_on_eu_changed)
	_on_eu_changed(GameState.eu)  # initialize the label
	
func _on_eu_changed(v: float) -> void:
	%EuLabel.text = str(round(v))

func _refresh() -> void:
	eu_label.text = "Eu: %.1f" % GameState.eu
	money_label.text = "$$: %.1f" % GameState.money
	fuel_label.text = "Fuel: %.1fml" % GameState.fuel
	coolant_label.text = "Coolant: %.1fml" % GameState.coolant
