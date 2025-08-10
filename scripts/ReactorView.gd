class_name ReactorView
extends PanelContainer

@onready var fuel_bar: ProgressBar    = $MarginContainer/VBoxContainer/FuelBar
@onready var coolant_bar: ProgressBar = $MarginContainer/VBoxContainer/CoolantBar
@onready var heat_bar: ProgressBar    = $MarginContainer/VBoxContainer/HeatBar

# Caps (we’ll tie these to research later)
@export var fuel_cap: float = 1000.0
@export var coolant_cap: float = 1000.0

func _ready() -> void:
	GameState.state_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:

	# Bars
	fuel_bar.max_value = fuel_cap
	fuel_bar.value = GameState.fuel

	coolant_bar.max_value = coolant_cap
	coolant_bar.value = GameState.coolant

	heat_bar.max_value = GameState.OVERHEAT
	heat_bar.value = GameState.temp

	# Optional: warning thresholds for Heat
	# if heat_bar.value >= GameState.OVERHEAT * 0.9:
	#     heat_bar.add_theme_color_override("fg_color", Color(1,0.2,0.2))
	# elif heat_bar.value >= GameState.OVERHEAT * 0.7:
	#     heat_bar.add_theme_color_override("fg_color", Color(1,0.8,0.2))
	# else:
	#     heat_bar.remove_theme_color_override("fg_color")
