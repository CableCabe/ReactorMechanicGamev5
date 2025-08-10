class_name ReactionPillar
extends Control

@export var idx: int = 0

@onready var name_label: Label  = $Row/NameLabel
@onready var level_label: Label = $Row/LevelLabel
@onready var toggle: CheckBox   = $Row/OnToggle
@onready var up_btn: Button     = $Row/UpgradeBtn
@onready var unlock_btn: Button = $Row/UnlockBtn
@onready var pulse_label: Label = $Row/PulseLabel     
@onready var flash: ColorRect   = $Flash 

var _tween: Tween

func _ready() -> void:
	custom_minimum_size.y = max(32.0, $Row.get_combined_minimum_size().y)
	name_label.text = "Pillar %d" % (idx + 1)
	toggle.toggled.connect(_on_toggle)
	up_btn.pressed.connect(_on_upgrade)
	unlock_btn.pressed.connect(_on_unlock)
	GameState.state_changed.connect(_refresh)
	GameState.pillar_fired.connect(_on_pillar_fired)
	_refresh()

func _refresh() -> void:
	var p: Dictionary = GameState.pillars[idx]
	var is_unlocked: bool = bool(p.get("unlocked", false))

	toggle.visible = is_unlocked
	up_btn.visible = is_unlocked
	unlock_btn.visible = not is_unlocked

	if is_unlocked:
		level_label.text = "Lv. %d" % int(p.get("level", 0))
		toggle.button_pressed = bool(p.get("enabled", false))

		var cost: Dictionary = GameState.pillar_upgrade_cost(int(p.get("level", 0)))
		up_btn.text = "Upgrade (Eu %.0f)" % float(cost.get("eu", 0.0))
		up_btn.disabled = not GameState.can_afford(cost)

		# NEW: per-pulse readout
		var pulse := GameState.pillar_pulse_eu(idx)
		pulse_label.text = "+%.2f Eu | " % pulse
	else:
		var uc: Dictionary = GameState.unlock_cost(idx)
		unlock_btn.text = "Unlock (Eu %.0f)" % float(uc.get("eu", 0.0))
 

func _on_toggle(on: bool) -> void:
	GameState.toggle_pillar(idx, on)

func _on_upgrade() -> void:
	GameState.upgrade_pillar(idx)

func _on_unlock() -> void:
	GameState.unlock_pillar(idx)

func _on_pillar_fired(fired_idx: int) -> void:
	if fired_idx != idx:
		return
	# quick flash
	if _tween and _tween.is_running():
		_tween.kill()
	flash.modulate.a = 0.8
	flash.visible = true
	_tween = create_tween()
	_tween.tween_property(flash, "modulate:a", 0.0, 0.15)
	_tween.tween_callback(Callable(self, "_hide_flash"))

func _hide_flash() -> void:
	flash.visible = false
