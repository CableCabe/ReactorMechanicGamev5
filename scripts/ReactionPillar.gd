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
@export var fuel_per_pulse: float = 1.0
@export var pulse_eu: float = 2.0
@export var pulse_interval: float = 1.0

var _tween: Tween
var _active: bool = false
var _pulse_timer: Timer

signal pillar_state_changed(active: bool)
signal show_no_fuel_flag
signal hide_no_fuel_flag

func _ready() -> void:
	custom_minimum_size.y = max(32.0, $Row.get_combined_minimum_size().y)
	name_label.text = "Pillar %d" % (idx + 1)
	toggle.toggled.connect(_on_toggle)
	up_btn.pressed.connect(_on_upgrade)
	unlock_btn.pressed.connect(_on_unlock)
	GameState.state_changed.connect(_refresh)
	GameState.pillar_fired.connect(_on_pillar_fired)
	_refresh()
	_pulse_timer = Timer.new()
	_pulse_timer.wait_time = pulse_interval
	_pulse_timer.autostart = false
	add_child(_pulse_timer)
	_pulse_timer.timeout.connect(_on_pulse)

	if GameState.has_signal("venting_started"):
		GameState.connect("venting_started", Callable(self, "_on_vent_start"))
	if GameState.has_signal("venting_finished"):
		GameState.connect("venting_finished", Callable(self, "_on_vent_end"))
	if GameState.has_signal("pillar_no_fuel"):
		GameState.connect("pillar_no_fuel", Callable(self, "_on_pillar_no_fuel"))
	
	add_to_group("reaction_pillars")

func _refresh() -> void:
	var p: Dictionary = GameState.get_pillar(idx)
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
 
func set_pillar_index(i: int) -> void:
	idx = i
	_refresh()

func _on_toggle(on: bool) -> void:
	GameState.set_pillar_enabled(idx, on)
	_refresh()

func _on_upgrade() -> void:
	GameState.upgrade_pillar(idx)

func _on_unlock() -> void:
	GameState.unlock_pillar(idx)

func _on_pillar_fired(fired_idx: int) -> void:
	 if not _active:
		return
	if GameState.is_venting:
		return
	if not GameState.consume_fuel(fuel_per_pulse, self):
		turn_off()
		emit_signal("show_no_fuel_flag")
		return
	
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

func turn_on() -> void:
	if _active:
		return
	_active = true
	emit_signal("pillar_state_changed", true)
	_update_timer()

func turn_off() -> void:
	if _active == false:
		return
	_active = false
	emit_signal("pillar_state_changed", false)
	_pulse_timer.stop()

func _update_timer() -> void:
	if _active == false:
		return
	if GameState.is_venting:
		_pulse_timer.stop()
		return
	if GameState.auto_ignite_enabled:
		_pulse_timer.start()
	else:
		_pulse_timer.stop()

func _on_vent_start() -> void:
	_pulse_timer.stop()

func _on_vent_end() -> void:
	_update_timer()

func manual_ignite() -> void:
	if _active == false:
		return
	if GameState.is_venting:
		return
	if GameState.manual_ignite_enabled:
		_on_pulse()

func _on_pulse() -> void:
	if GameState.is_venting:
		return
	var ok := GameState.consume_fuel(fuel_per_pulse, self)
	if ok == false:
		turn_off()
		emit_signal("show_no_fuel_flag")
		return
	# Successful pulse → integrate with your EU/heat logic here
	# Example: GameState.add_eu(pulse_eu)
	emit_signal("hide_no_fuel_flag")

func _on_pillar_no_fuel(path: NodePath) -> void:
	if get_path() == path:
		turn_off()
		emit_signal("show_no_fuel_flag")
