# scripts/ReactionPillar.gd
# Phase-locked progress bar using a local Timer; synced to real pillar_fired cadence.
# Tabs-only indentation. No ?: ternaries. No tween-based progress.

class_name ReactionPillar
extends Control

@export var idx: int = 0
@export var fuel_per_pulse: float = 1.0
@export var pulse_eu: float = 2.0
@export var pulse_interval: float = 1.0

# --- UI ---
@onready var name_label: Label = %NameLabel
@onready var level_label: Label = %LevelLabel
@onready var progress: ProgressBar = %ChargeBar
@onready var pulse_label: Label = %PulseLabel
@onready var flash: ColorRect = %Flash
@onready var toggle_btn: Button = %OnButton
@onready var up_btn: Button = %UpgradeBtn
@onready var unlock_btn: Button = %UnlockBtn2
# Light board
@onready var light_enabled: ColorRect = %LightEnabled
@onready var light_fired: ColorRect = %LightFired
@onready var light_heat: ColorRect = %LightHeat
@onready var light_vent: ColorRect = %LightVent
@onready var light_fuel: ColorRect = %LightFuel
@onready var light_cool: ColorRect = %LightCool

# Autoload detection (supports either GS or GameState)
@onready var GS: Node = (
	get_tree().root.get_node_or_null("GS") if get_tree().root.has_node("GS")
	else get_tree().root.get_node_or_null("GameState")
)

# --- Phase lock timing ---
var _active: bool = false
var _expected_period_s: float = 1.0
#var _last_fire_ms: int = 0
#var _phase: Timer

# Visual flash tween (not used for progress)
var _flash_tween: Tween

#signal pillar_state_changed(active: bool)
signal show_no_fuel_flag
signal hide_no_fuel_flag

func _ready() -> void:
	if GS == null:
		push_error("ReactionPillar: missing GameState autoload.")
		return

	custom_minimum_size = Vector2(560, 120)
	if progress:
		progress.min_value = 0.0
		progress.max_value = 1.0
		progress.value = 0.0

	_phase = Timer.new()
	_phase.one_shot = true
	_phase.autostart = false
	add_child(_phase)

	if toggle_btn:
		toggle_btn.pressed.connect(_on_toggle_btn)
	if up_btn:
		up_btn.pressed.connect(_on_upgrade)
	if unlock_btn:
		unlock_btn.pressed.connect(_on_unlock)

	if GS.has_signal("state_changed"):
		GS.connect("state_changed", Callable(self, "_refresh"))
	if GS.has_signal("eu_changed"):
		GS.connect("eu_changed", Callable(self, "_refresh"))
#	if GS.has_signal("pillar_fired"):
#		GS.connect("pillar_fired", Callable(self, "_on_pillar_fired").bind(idx))
#	if GS.has_signal("venting_started"):
#		GS.connect("venting_started", Callable(self, "_on_vent_start"))
#	if GS.has_signal("venting_finished"):
#		GS.connect("venting_finished", Callable(self, "_on_vent_end"))
#	if GS.has_signal("pillar_no_fuel"):
#		GS.connect("pillar_no_fuel", Callable(self, "_on_pillar_no_fuel"))

	_seed_expected_period()
	set_process(true)
	_refresh()

# ---- Helpers ----
#func _seed_expected_period() -> void:
#	_expected_period_s = pulse_interval
#	if GS and GS.has_method("pillar_period"):
#		var per := float(GS.pillar_period(idx))
#		if per > 0.0:
#			_expected_period_s = per
#	else:
#		if GS and GS.has_method("pillar_rate"):
#			var r := float(GS.pillar_rate(idx))
#			if r > 0.0:
#				_expected_period_s = 1.0 / r
#
#func set_pillar_index(i: int) -> void:
#	idx = i
#	_seed_expected_period()
#	_refresh()

# ---- Frame sync for progress: driven by timer ----
func _process(_delta: float) -> void:
	if not _active:
		return
	if progress == null:
		return
	if _phase == null or _phase.is_stopped():
		return
	var wt: float = max(0.001, _phase.wait_time)
	var tl: float = clamp(_phase.time_left, 0.0, wt)
	var ratio: float = (wt - tl) / wt
	if ratio > 0.999:
		ratio = 0.999
	progress.value = ratio

# ---- Refresh from model ----
func _refresh() -> void:
	

#	if is_unlocked:
#		if pulse_label and GS and GS.has_method("pillar_pulse_eu"):
#			var pe: float = _eu_per_pulse()
#			pulse_label.text = "+%.2f Eu" % [pe]
#		var cost: Dictionary = GS.pillar_upgrade_cost(int(p.get("level", 1)))
#		if up_btn:
#			up_btn.text = "Upgrade (Eu %.0f)" % float(cost.get("eu", 0.0))
#			up_btn.disabled = not GS.can_afford(cost)
#		if unlock_btn:
#			unlock_btn.visible = false
#		if toggle_btn:
#			toggle_btn.visible = true
#	else:
#		if pulse_label:
#			pulse_label.text = ""
#		if up_btn:
#			up_btn.visible = false
#		if toggle_btn:
#			toggle_btn.visible = false
#		if unlock_btn:
#			var uc: Dictionary = GS.unlock_cost(idx)
#			unlock_btn.text = "Unlock (Eu %.0f)" % float(uc.get("eu", 0.0))
#			unlock_btn.disabled = not GS.can_afford(uc)
#			unlock_btn.visible = true
#
#	_update_toggle_btn_visual(is_enabled)
#
#	if is_unlocked and is_enabled:
#		if not _active:
#			turn_on()
#	else:
#		if _active:
#			turn_off()
#
#	_update_lights()

# ---- Toggle handling ----
#func _on_toggle_btn() -> void:
#	var p: Dictionary = GS.get_pillar(idx) as Dictionary
#	var on_now: bool = not bool(p.get("enabled", false))
#	GS.set_pillar_enabled(idx, on_now)
#	_update_toggle_btn_visual(on_now)
#	_refresh()

#func _update_toggle_btn_visual(on: bool) -> void:
#	if toggle_btn == null:
#		return
#	if on:
#		toggle_btn.text = "ON"
#		toggle_btn.self_modulate = Color(0.6, 1.0, 0.6)
#	else:
#		toggle_btn.text = "OFF"
#		toggle_btn.self_modulate = Color(1.0, 0.45, 0.45)

# ---- Buttons ----
#func _on_upgrade() -> void:
#	GS.upgrade_pillar(idx)
#	_seed_expected_period()
#	_refresh()
#
#func _on_unlock() -> void:
#	GS.unlock_pillar(idx)
#	_seed_expected_period()
#	# do not start timer yet; wait for first fire so we phase-lock cleanly
#	if progress:
#		progress.value = 0.0
#	_refresh()

# ---- Light board ----
#func _update_lights() -> void:
#	_set_light(light_enabled, _active and not GS.is_venting)
#	var has_f: bool = true
#	if GS and GS.has_method("has_fuel"):
#		has_f = GS.has_fuel(fuel_per_pulse)
#	_set_light(light_fuel, has_f)
#	_set_light(light_vent, GS.is_venting)
#	var hot: bool = false
#	if GS and GS.has_method("is_hot"):
#		hot = GS.is_hot()
#	_set_light(light_heat, hot)
#	var cool_ok: bool = true
#	if GS and GS.has_method("has_coolant"):
#		cool_ok = GS.has_coolant()
#	_set_light(light_cool, cool_ok)
#
#func _set_light(cr: ColorRect, on: bool) -> void:
#	if cr == null:
#		return
#	cr.self_modulate = Color(1,1,1,1) if on else Color(1,1,1,0.25)

## ---- Venting gates ----
#func _on_vent_start() -> void:
#	if _phase:
#		_phase.paused = true
#	_update_lights()
#
#func _on_vent_end() -> void:
#	if _phase:
#		_phase.paused = false
#	_update_lights()

# ---- Ignites / Phase clock ----
#func _on_pillar_fired(i: int, _payload: Variant = null) -> void:
#	if i != idx:
#		return
#	if not _active:
#		return
#	if GS.is_venting:
#		return
#
#	# Blink fired light and overlay
#	if light_fired:
#		light_fired.self_modulate.a = 1.0
#		var t := create_tween()
#		t.tween_property(light_fired, "self_modulate:a", 0.25, 0.15)
#	if flash:
#		if _flash_tween and _flash_tween.is_running():
#			_flash_tween.kill()
#		flash.modulate.a = 0.8
#		_flash_tween = create_tween()
#		_flash_tween.tween_property(flash, "modulate:a", 0.0, 0.15)
#
#	# Derive next period: prefer GS, else use measured interval
#	var next_period := _pillar_period()
#	var now_ms := Time.get_ticks_msec()
#	if _last_fire_ms > 0:
#		var measured_s := float(now_ms - _last_fire_ms) / 1000.0
#		if measured_s > 0.05:
#			next_period = measured_s
#	_last_fire_ms = now_ms
#
#	_start_phase_timer(next_period)
#	if progress:
#		progress.value = 0.0
#
#	emit_signal("hide_no_fuel_flag")
#
#func _pillar_period() -> float:
#	if GS and GS.has_method("pillar_period"):
#		var per := float(GS.pillar_period(idx))
#		return max(0.05, per)
#	if GS and GS.has_method("pillar_rate"):
#		var r := float(GS.pillar_rate(idx))
#		if r > 0.0:
#			return 1.0 / r
#	return pulse_interval

#func _start_phase_timer(per: float) -> void:
#	if _phase == null:
#		return
#	var p := per
#	if p <= 0.0:
#		p = 0.001
#	_phase.stop()
#	_phase.wait_time = p
#	_phase.start()
#
## --- EU display helpers ---
#func _eu_per_pulse() -> float:
#	if GS and GS.has_method("pillar_pulse_eu"):
#		return float(GS.pillar_pulse_eu(idx))
#	return pulse_eu
#
## ---- Active state ----
#func turn_on() -> void:
#	if _active:
#		return
#	_active = true
#	emit_signal("pillar_state_changed", true)
#	# wait for first fire to lock phase
#	if progress:
#		progress.value = 0.0
#	_update_lights()

#func turn_off() -> void:
#	if not _active:
#		return
#	_active = false
#	emit_signal("pillar_state_changed", false)
#	if _phase:
#		_phase.stop()
#	if progress:
#		progress.value = 0.0
#	_update_lights()

# ---- No fuel handling ----
#func _on_pillar_no_fuel(path: NodePath) -> void:
#	if get_path() == path:
#		turn_off()
#		emit_signal("show_no_fuel_flag")
