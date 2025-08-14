# scripts/ReactionPillar.gd
# Adds: title, 2x2 light board, fill-to-pulse progress bar, toggle-as-button skin
# Tabs-only indentation. No question-mark ternaries.

class_name ReactionPillar
extends Control

@export var idx: int = 0
@export var fuel_per_pulse: float = 1.0
@export var pulse_eu: float = 2.0
@export var pulse_interval: float = 1.0 # fallback if GS doesn't expose a period/rate

@onready var name_label: Label = $VBoxContainer/HBoxContainer/NameLabel
@onready var level_label: Label = $VBoxContainer/HBoxContainer/LevelLabel

@onready var progress: ProgressBar = $VBoxContainer/HBoxContainer2/PanelContainer2/ChargeBar
@onready var pulse_label: Label = $VBoxContainer/HBoxContainer2/PanelContainer2/PulseLabel
@onready var flash: ColorRect = $HBoxContainer/VBoxContainer/HBoxContainer2/PanelContainer/Flash

@onready var toggle_btn: Button = $VBoxContainer/HBoxContainer3/OnButton
@onready var up_btn: Button = $VBoxContainer/HBoxContainer3/UpgradeBtn
@onready var unlock_btn: Button = $VBoxContainer/HBoxContainer3/UnlockBtn2

# 2×3 light board (you have 6 lights visible)
@onready var light_enabled: ColorRect = $GridContainer/LightEnabled
@onready var light_fired: ColorRect = $GridContainer/LightFired
@onready var light_heat: ColorRect = $GridContainer/LightHeat
@onready var light_vent: ColorRect = $GridContainer/LightVent
@onready var light_fuel: ColorRect = $GridContainer/LightFuel
@onready var light_cool: ColorRect = $GridContainer/LightCool

@onready var GS: Node = (
	get_tree().root.get_node_or_null("GS") if get_tree().root.has_node("GS")
	else get_tree().root.get_node_or_null("GameState")
)

var _ui_resolved := false
var _tween: Tween
var _progress_tween: Tween
var _active: bool = false
var _pulse_timer: Timer
var _vent_locked: bool = false

signal pillar_state_changed(active: bool)
signal show_no_fuel_flag
signal hide_no_fuel_flag

func _ready() -> void:
	if GS == null:
		push_error("ReactionPillar: no '/root/GS' or '/root/GameState' autoload found.")
		return
	_resolve_ui()
	# Hook UI
	if toggle_btn:
		toggle_btn.pressed.connect(_on_toggle_btn)
	if up_btn:
		up_btn.pressed.connect(_on_upgrade)
	if unlock_btn:
		unlock_btn.pressed.connect(_on_unlock)
	# Hook model
	if GS.has_signal("state_changed"):
		GS.connect("state_changed", Callable(self, "_refresh"))
	if GS.has_signal("eu_changed"):
		GS.connect("eu_changed", Callable(self, "_refresh"))
	if GS.has_signal("pillar_fired"):
		GS.connect("pillar_fired", Callable(self, "_on_pillar_fired").bind(idx))
	if GS.has_signal("venting_started"):
		GS.connect("venting_started", Callable(self, "_on_vent_start"))
	if GS.has_signal("venting_finished"):
		GS.connect("venting_finished", Callable(self, "_on_vent_end"))
	if GS.has_signal("pillar_no_fuel"):
		GS.connect("pillar_no_fuel", Callable(self, "_on_pillar_no_fuel"))

	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 100
	
	if progress:
		progress.min_value = 0.0
		progress.max_value = 1.0
		progress.value = 0.0

	add_to_group("reaction_pillars")
	_refresh() # initial sync

	# Optional local timer remains disabled; central sim drives pulses.
	# _pulse_timer = Timer.new()
	# _pulse_timer.autostart = false
	# _pulse_timer.one_shot = false
	# _pulse_timer.wait_time = _pillar_period()
	# add_child(_pulse_timer)
	# _pulse_timer.timeout.connect(_on_pulse)

func _pillar_period() -> float:
	# Prefer model-provided period or rate if available; otherwise use export.
	if GS and GS.has_method("pillar_period"):
		return max(0.05, float(GS.pillar_period(idx)))
	if GS and GS.has_method("pillar_rate"):
		var r := float(GS.pillar_rate(idx))
		if r <= 0.0:
			return pulse_interval
		return 1.0 / r
	return pulse_interval

func _refresh() -> void:
	var p: Dictionary = GS.get_pillar(idx)
	var is_unlocked: bool = bool(p.get("unlocked", false))
	var is_enabled := bool(p.get("enabled", false))

	# Title
	if name_label:
		name_label.text = "Ignition Pillar %d" % int(idx + 1)

	# Show/Hide
	if toggle_btn:
		toggle_btn.visible = is_unlocked
	if up_btn:
		up_btn.visible = is_unlocked
	if unlock_btn:
		unlock_btn.visible = not is_unlocked
	if pulse_label and not is_unlocked:
		pulse_label.text = ""

	if is_unlocked:
		# Level & upgrade price
		if level_label:
			level_label.text = "Lv. %d" % int(p.get("level", 0))
		var cost: Dictionary = GS.pillar_upgrade_cost(int(p.get("level", 0)))
		if up_btn:
			up_btn.text = "Upgrade (Eu %.0f)" % float(cost.get("eu", 0.0))
			up_btn.disabled = not GS.can_afford(cost)
		# Per-pulse EU readout
		if pulse_label:
			var pulse_val: float = GS.pillar_pulse_eu(idx) if GS.has_method("pillar_pulse_eu") else pulse_eu
			pulse_label.text = "+%.2f Eu" % pulse_val
	else:
		# locked: show unlock price
		var uc: Dictionary = GS.unlock_cost(idx)
		if unlock_btn:
			var price := float(uc.get("eu", 0.0))
			unlock_btn.text = "Unlock (Eu %.0f)" % price
			unlock_btn.disabled = not GS.can_afford(uc)

	_update_toggle_btn_visual(is_enabled)

	# Drive local active for flash/progress gating
	if is_unlocked and is_enabled:
		if not _active:
			turn_on()
	else:
		if _active:
			turn_off()

	# Lights
	_update_lights()

func set_pillar_index(i: int) -> void:
	idx = i
	_refresh()

func _resolve_ui() -> void:
	if _ui_resolved:
		return
	# Try to find fallbacks if paths shifted
	var row := $Row
	if row == null:
		return
	if pulse_label == null:
		pulse_label = row.get_node_or_null("PulseLabel") as Label
	if name_label == null:
		name_label = row.get_node_or_null("NameLabel") as Label
	if level_label == null:
		level_label = row.get_node_or_null("LevelLabel") as Label
	if toggle_btn == null:
		toggle_btn = row.get_node_or_null("OnButton") as Button
	if up_btn == null:
		up_btn = row.get_node_or_null("UpgradeBtn") as Button
	if unlock_btn == null:
		unlock_btn = row.get_node_or_null("UnlockBtn") as Button
	
	# Minimal width so text isn't jittered by flash overlay
	if pulse_label:
		pulse_label.custom_minimum_size.x = 32
	
	# Progress defaults
	if progress:
		progress.min_value = 0
		progress.max_value = 1.0
		progress.value = 0.0
	
	_ui_resolved = true

# --- Toggle handling ---

func _on_toggle(on: bool) -> void:
	GS.set_pillar_enabled(idx, on)
	_refresh()

func _on_toggle_btn() -> void:
	var p: Dictionary = GS.get_pillar(idx) as Dictionary
	var on := not bool(p.get("enabled", false))
	GS.set_pillar_enabled(idx, on)
	_update_toggle_btn_visual(on)
	_refresh()

func _update_toggle_btn_visual(on: bool) -> void:
	if toggle_btn == null:
		return
	# Simple red/green feedback using self_modulate; themeable later.
	toggle_btn.text = "ON" if on else "OFF"
	toggle_btn.self_modulate = Color(0.6, 1.0, 0.6) if on else Color(1.0, 0.45, 0.45)

# --- Buttons ---

func _on_upgrade() -> void:
	GS.upgrade_pillar(idx)
	_refresh()

func _on_unlock() -> void:
	GS.unlock_pillar(idx)
	_vent_locked = false
	_restart_progress()
	_refresh()

# --- Light board ---

func _update_lights() -> void:
	_set_light(light_enabled, _active and not GS.is_venting)
	_set_light(light_fuel, GS.has_fuel(fuel_per_pulse) if GS.has_method("has_fuel") else true)
	_set_light(light_vent, GS.is_venting)
	_set_light(light_heat, GS.is_hot() if GS.has_method("is_hot") else false)
	# Optional: show coolant sufficiency if you track it
	_set_light(light_cool, GS.has_coolant() if GS.has_method("has_coolant") else true)

func _set_light(cr: ColorRect, on: bool) -> void:
	if cr == null:
		return
	# Dim when off; bright when on.
	cr.self_modulate = Color(1,1,1,1) if on else Color(1,1,1,0.25)

# --- Venting gates ---

func _on_vent_start() -> void:
	_pause_progress()
	_update_lights()

func _on_vent_end() -> void:
	_resume_progress()
	_update_lights()

# --- Pulse & progress integration ---

func _on_pillar_fired(i: int, _payload: Variant = null) -> void:
	if i != idx or not _active or GS.is_venting:
		return
	# Consume fuel (model also enforces); shut down on empty
	if not GS.consume_fuel(fuel_per_pulse, self):
		turn_off()
		emit_signal("show_no_fuel_flag")
		return
	# Quick flash
	if _tween and _tween.is_running():
		_tween.kill()
	flash.modulate.a = 0.8
	_tween = create_tween()
	_tween.tween_property(flash, "modulate:a", 0.0, 0.15)
	# Reset progress after a successful pulse
	_restart_progress()
	emit_signal("hide_no_fuel_flag")
	
	if light_fired:
		light_fired.self_modulate.a = 1.0
		var t := create_tween()
		t.tween_property(light_fired, "self_modulate:a", 0.25, 0.15)

	_restart_progress()
	emit_signal("hide_no_fuel_flag")

func _restart_progress() -> void:
	if progress == null:
		return
	if _progress_tween and _progress_tween.is_running():
		_progress_tween.kill()
	progress.value = 0.0
	if not _active or GS.is_venting:
		return
	var period := _pillar_period()
	_progress_tween = create_tween()
	_progress_tween.set_trans(Tween.TRANS_LINEAR)
	_progress_tween.set_ease(Tween.EASE_IN_OUT)
	_progress_tween.tween_property(progress, "value", 1.0, period)

func _pause_progress() -> void:
	if _progress_tween and _progress_tween.is_running():
		_progress_tween.pause()

func _resume_progress() -> void:
	if _progress_tween and _progress_tween.is_valid():
		_progress_tween.play()
	else:
		_restart_progress()

# Manual ignite for early-game (optional)
func manual_ignite() -> void:
	if _active == false:
		return
	if GS.is_venting:
		return
	if _vent_locked or not _active or GS.is_venting:
		return
	_on_pulse()

func _on_pulse() -> void:
	if _vent_locked or GS.is_venting:
		return
	var ok: bool = GS.consume_fuel(fuel_per_pulse, self)
	if ok == false:
		turn_off()
		emit_signal("show_no_fuel_flag")
		return
	# Example of local EU contribution if central sim doesn't add it
	if GS and GS.has_method("add_eu"):
		GS.add_eu(pulse_eu)
	_restart_progress()
	emit_signal("hide_no_fuel_flag")

func _on_pillar_no_fuel(path: NodePath) -> void:
	if get_path() == path:
		turn_off()
		emit_signal("show_no_fuel_flag")

# --- Active state & timer ---

func turn_on() -> void:
	if _active:
		return
	_active = true
	emit_signal("pillar_state_changed", true)
	_update_timer()
	_restart_progress()
	_update_lights()

func turn_off() -> void:
	if _active == false:
		return
	_active = false
	emit_signal("pillar_state_changed", false)
	if _pulse_timer:
		_pulse_timer.stop()
	if _progress_tween and _progress_tween.is_running():
		_progress_tween.kill()
	if progress:
		progress.value = 0.0
	_update_lights()

func _update_timer() -> void:
	# Central sim handles pulses now — keep guard.
	if _pulse_timer == null:
		return
	if GS.is_venting:
		_pulse_timer.stop()
		return
	if GS.auto_ignite_enabled:
		_pulse_timer.wait_time = _pillar_period()
		_pulse_timer.start()
	else:
		_pulse_timer.stop()
