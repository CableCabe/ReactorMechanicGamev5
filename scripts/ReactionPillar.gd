class_name ReactionPillar
extends Control

@export var idx: int = 0

@onready var name_label: Label  = $Row/NameLabel
@onready var level_label: Label = $Row/LevelLabel
@onready var toggle: CheckBox   = $Row/OnToggle
@onready var up_btn: Button     = $Row/UpgradeBtn
@onready var unlock_btn: Button = %UnlockBtn
@onready var pulse_label: Label = $Row/PulseLabel     
@onready var flash: ColorRect   = $Flash 
@export var fuel_per_pulse: float = 1.0
@export var pulse_eu: float = 2.0
@export var pulse_interval: float = 1.0
@onready var GS: Node = (
	get_tree().root.get_node_or_null("GS") 
	if get_tree().root.has_node("GS") 
	else get_tree().root.get_node_or_null("GameState")
)

var _ui_resolved := false
var _tween: Tween
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
	
	toggle.toggled.connect(_on_toggle)
	up_btn.pressed.connect(_on_upgrade)
	unlock_btn.pressed.connect(_on_unlock)
	
	if GS.has_signal("state_changed"):
		GS.connect("state_changed", Callable(self, "_refresh"))
	if GS.has_signal("eu_changed"):
		GS.connect("eu_changed",   Callable(self, "_refresh"))
	
	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 100

	if GS.has_signal("state_changed"):
		GS.connect("state_changed", Callable(self, "_refresh"))

	if GS.has_signal("pillar_fired"):
		GS.connect("pillar_fired", Callable(self, "_on_pillar_fired").bind(idx))

	if GS.has_signal("venting_started"):
		GS.connect("venting_started", Callable(self, "_on_vent_start"))
	if GS.has_signal("venting_finished"):
		GS.connect("venting_finished", Callable(self, "_on_vent_end"))
	if GS.has_signal("pillar_no_fuel"):
		GS.connect("pillar_no_fuel", Callable(self, "_on_pillar_no_fuel"))
	
	if toggle:     toggle.toggled.connect(_on_toggle)
	if up_btn:     up_btn.pressed.connect(_on_upgrade)
	if unlock_btn: unlock_btn.pressed.connect(_on_unlock)

	add_to_group("reaction_pillars")
	_refresh()  # initial sync
	
	# Future timer
	
#	_pulse_timer = Timer.new()
#	_pulse_timer.autostart = false
#	_pulse_timer.one_shot = false
#	_pulse_timer.wait_time = pulse_interval
#	add_child(_pulse_timer)
#	_pulse_timer.timeout.connect(_on_pulse)

func _refresh() -> void:
	var p: Dictionary = GS.get_pillar(idx)
	var is_unlocked: bool = bool(p.get("unlocked", false))
	var is_enabled  := bool(p.get("enabled", false))
	
	toggle.visible = is_unlocked
	up_btn.visible = is_unlocked
	unlock_btn.visible = not is_unlocked
	
	if toggle:     toggle.visible     = is_unlocked
	if up_btn:     up_btn.visible     = is_unlocked
	if unlock_btn: unlock_btn.visible = not is_unlocked

	if is_unlocked:
		# level & upgrade price
		if level_label:
			level_label.text = "Lv. %d" % int(p.get("level", 0))
		var cost: Dictionary = GS.pillar_upgrade_cost(int(p.get("level", 0)))
		if up_btn:
			up_btn.text = "Upgrade (Eu %.0f)" % float(cost.get("eu", 0.0))
			up_btn.disabled = not GS.can_afford(cost)

		# per-pulse EU readout
		if pulse_label:
			var pulse_val: float = GS.pillar_pulse_eu(idx)
			pulse_label.text = "+%.2f Eu" % pulse_val
	else:
		# locked: show unlock price (and grey when unaffordable)
		var uc: Dictionary = GS.unlock_cost(idx)
		if unlock_btn:
			var price := float(uc.get("eu", 0.0))
			unlock_btn.text = "Unlock (Eu %.0f)" % price
			unlock_btn.disabled = not GS.can_afford(uc)
		if pulse_label:
			pulse_label.text = ""  # or "Locked"

	# keep checkbox in sync without firing its signal
	if toggle:
		toggle.set_pressed_no_signal(is_enabled)

	# drive local active so flash gating works
	if is_unlocked and is_enabled:
		if not _active: turn_on()
	else:
		if _active: turn_off()
 
func set_pillar_index(i: int) -> void:
	idx = i
	_refresh()

func _resolve_ui() -> void:
	if _ui_resolved: return
	var row := $Row
	if row == null: return
	
	var places: Array = [row]
	for base in places:
		if base == null: continue
		if pulse_label == null:
			pulse_label = base.get_node_or_null("PulseLabel") as Label
		if name_label == null:
			name_label  = base.get_node_or_null("NameLabel")  as Label
		if level_label == null:
			level_label = base.get_node_or_null("LevelLabel") as Label
		if toggle == null:
			toggle      = base.get_node_or_null("OnToggle")   as CheckBox
		if up_btn == null:
			up_btn      = base.get_node_or_null("UpgradeBtn") as Button
		if unlock_btn == null:
			unlock_btn  = base.get_node_or_null("UnlockBtn")  as Button
	
	if pulse_label:
		pulse_label.custom_minimum_size.x = 32

	_ui_resolved = true

func _on_toggle(on: bool) -> void:
	GS.set_pillar_enabled(idx, on)
	_refresh()

func _on_upgrade() -> void:
	GS.upgrade_pillar(idx)
	_refresh()

func _vent_lock() -> void:
	_vent_locked = true
	if _pulse_timer: _pulse_timer.stop()
	set_process(false)

func _on_unlock() -> void:
	GS.unlock_pillar(idx)
	_vent_locked = false
	_update_timer()
	_refresh()
	set_process(true)

func _on_pillar_fired(i: int, _payload: Variant = null) -> void:
	if i != idx: return
	if not _active: return
	if GS.is_venting: return

	# Per-pulse fuel consumption; shut down on empty
	if not GS.consume_fuel(fuel_per_pulse, self):
		turn_off()
		emit_signal("show_no_fuel_flag")
		return
	# quick flash
	if _tween and _tween.is_running(): _tween.kill()
	flash.modulate.a = 0.8
	_tween = create_tween()
	_tween.tween_property(flash, "modulate:a", 0.0, 0.15)

func _hide_flash() -> void:
	flash.visible = false

func turn_on() -> void:
	if _active:
		return
	_active = true
	emit_signal("pillar_state_changed", true)
	_update_timer()

func turn_off() -> void:
	if _active == false: return
	_active = false
	emit_signal("pillar_state_changed", false)
	if _pulse_timer: _pulse_timer.stop()   # ← guard

func _update_timer() -> void:
	# Central sim handles auto pulses now. Keep this a no-op or guard the timer.
	if _pulse_timer == null:
		return
	if GS.is_venting:
		_pulse_timer.stop()
		return
	if GS.auto_ignite_enabled:
		_pulse_timer.start()
	else:
		_pulse_timer.stop()

func manual_ignite() -> void:
	if _active == false:
		return
	if GS.is_venting:
		return
	#if GS.manual_ignite_enabled:
		#_on_pulse()
	if _vent_locked or not _active or GS.is_venting: return
	_on_pulse()

func _on_pulse() -> void:
	if _vent_locked or GS.is_venting: 
		return
	else:
		var ok : bool = GS.consume_fuel(fuel_per_pulse, self)
		if ok == false:
			turn_off()
			emit_signal("show_no_fuel_flag")
			return
	# Successful pulse → integrate with your EU/heat logic here
	# Example: GS.add_eu(pulse_eu)
		emit_signal("hide_no_fuel_flag")

func _on_pillar_no_fuel(path: NodePath) -> void:
	if get_path() == path:
		turn_off()
		emit_signal("show_no_fuel_flag")
