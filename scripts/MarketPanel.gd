extends Control

@onready var slider: HSlider = $VBoxContainer/SellSlider
@onready var label: Label = $VBoxContainer/Label
@onready var save_btn: Button = $VBoxContainer/Button

func _ready() -> void:
	slider.value_changed.connect(_on_change)
	save_btn.pressed.connect(_on_save)
	_on_change(slider.value)

func _on_change(v: float) -> void:
	GameState.flags["auto_sell_ratio"] = v / 100.0
	label.text = "Sell: %d%% auto (Price/10Eu: $%.2f)" % [int(v), GameState.current_price()]

func _on_save() -> void:
	GameState.save_game()
