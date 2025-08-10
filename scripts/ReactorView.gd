extends PanelContainer

@export var fuel_value_path: NodePath
@export var coolant_value_path: NodePath
@export var heat_value_path: NodePath      # optional if you have a heat number label

@onready var fuel_value: Label    = get_node(fuel_value_path) as Label
@onready var coolant_value: Label = get_node(coolant_value_path) as Label
@onready var heat_value: Label    = get_node(heat_value_path) as Label

var _acc := 0.0

func _ready() -> void:
	set_process(true)
	_refresh()

func _process(d: float) -> void:
	_acc += d
	if _acc >= 0.25:
		_acc = 0.0
		_refresh()

func _refresh() -> void:
	fuel_value.text = "%0.0f ml" % GameState.fuel
	coolant_value.text = "%0.0f ml" % GameState.coolant
	heat_value.text = "%0.0f f" % GameState.temp
