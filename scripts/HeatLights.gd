extends VBoxContainer

@onready var GS = get_node("/root/GameState")
@onready var light_cold: ColorRect = %TooColdLight
@onready var light_hot: ColorRect  = %TooHotLight

# Tunables (change in Inspector or here)
@export var sweet_min: float = 25.0
@export var sweet_max: float = 75.0
@export var off_dim: float = 0.18

# Colors for ON state
@export var cold_on: Color = Color(0.35, 0.65, 1.0)  # blue-ish
@export var hot_on: Color  = Color(1.0, 0.35, 0.35)  # red-ish

func _ready() -> void:
	if GS.has_signal("heat_changed"):
		GS.heat_changed.connect(_on_heat_changed)
	_on_heat_changed(GS.heat)

func _on_heat_changed(v: float) -> void:
	var h: float = v
	if h <= 1.0:
		h = clamp(h, 0.0, 1.0) * 100.0

	var too_cold := h < sweet_min
	var too_hot  := h > sweet_max

	_set_light(light_cold, cold_on, too_cold)
	_set_light(light_hot,  hot_on,  too_hot)

func _set_light(rect: ColorRect, on_color: Color, on: bool) -> void:
	if rect == null:
		return
	if on:
		rect.color = on_color
	else:
		var c := on_color
		c.a = off_dim
		rect.color = c
