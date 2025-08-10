extends HBoxContainer

@onready var eu_label: Label = $EuLabel
@onready var money_label: Label = $MoneyLabel
@onready var fuel_label: Label = $Fuel
@onready var coolant_label: Label = $Coolant

signal research_loaded
var research_db := {}

func _ready() -> void:
	GameState.eu_changed.connect(_on_eu_changed)
	_on_eu_changed(GameState.eu)  # initialize the label
	var f := FileAccess.open("res://data/research.json", FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			research_db = data
			research_loaded.emit()
	
func _on_eu_changed(v: float) -> void:
	eu_label.text = str(roundi(v))   
	
func _refresh() -> void:
	eu_label.text = "Eu: %.1f" % GameState.eu
	money_label.text = "$$: %.1f" % GameState.money
	fuel_label.text = "Fuel: %.1fml" % GameState.fuel
	coolant_label.text = "Coolant: %.1fml" % GameState.coolant
