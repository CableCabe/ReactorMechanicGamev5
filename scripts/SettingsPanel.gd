extends PanelContainer

@onready var save_btn: Button    = $MarginContainer/VBoxContainer/HBoxContainer/SaveBtn
@onready var load_btn: Button    = $MarginContainer/VBoxContainer/HBoxContainer/LoadBtn
@onready var reset_btn: Button   = $MarginContainer/VBoxContainer/HBoxContainer/ResetBtn
@onready var confirm: ConfirmationDialog = $MarginContainer/VBoxContainer/ConfirmReset
@onready var GS = get_node("/root/GameState")

func _ready() -> void:
	assert(save_btn and load_btn and reset_btn and confirm, "SettingsPanel node path mismatch")
	save_btn.pressed.connect(_on_save)
	load_btn.pressed.connect(_on_load)
	reset_btn.pressed.connect(_on_reset)
	confirm.confirmed.connect(_on_confirm_reset)

func _on_save() -> void:
	GS.save_game()

func _on_load() -> void:
	var ok: bool = GS.load_game()
	if not ok:
		print("No save found.")

func _on_reset() -> void:
	confirm.popup_centered(Vector2i(360, 120))

func _on_confirm_reset() -> void:
	GS.reset_save()
