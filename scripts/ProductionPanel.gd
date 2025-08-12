extends PanelContainer

@onready var ignite_btn: Button         = $VBoxContainer/HBoxContainer2/IgniteBtn
@onready var ignite_upgrade_btn: Button = $VBoxContainer/HBoxContainer2/IgniteUpgradeBtn
@onready var vent_btn: Button           = $VBoxContainer/HBoxContainer/VentBtn
@onready var pillar_grid: GridContainer = $VBoxContainer/PillarGrid
@export var ignite_button_path: NodePath
@onready var ignite_button: Button = get_node(ignite_button_path)
@onready var GS = get_node("/root/GameState")

const HEAT_PULSE_PER_IGNITE: float = 6.0
const PILLAR_SCENE := preload("res://scenes/ReactionPillar.tscn")
const PILLAR_COUNT := 6
const COOLANT_PER_IGNITE: float = 2.0   # ml per manual ignite (tweak)
var _pillars: Array = []

var ignite_level: int = 0
var ignite_base: float = 2.0
var ignite_upgrade_cost: float = 50.0
var ignite_cost_mult: float = 1.6
var _vent_timer: Timer

func _ready() -> void:
	vent_btn.pressed.connect(_on_vent)  # ensure this connect exists
	if GS.has_signal("venting_started"):
		GS.connect("venting_started", Callable(self, "_on_vent_started"))
	if GS.has_signal("venting_finished"):
		GS.connect("venting_finished", Callable(self, "_on_vent_finished"))

	_apply_venting_state()
	GS.ensure_pillars(PILLAR_COUNT)
	ignite_btn.pressed.connect(_on_ignite)
	ignite_upgrade_btn.pressed.connect(_on_ignite_upgrade)
	vent_btn.pressed.connect(_on_vent)

	if GS.has_signal("eu_changed"):
		GS.connect("eu_changed", Callable(self, "_on_eu_bump"))
	if GS.has_signal("vent_started"):
		GS.connect("vent_started", Callable(self, "_on_vent_started"))
	if GS.has_signal("vent_finished"):
		GS.connect("vent_finished", Callable(self, "_on_vent_finished"))
	
	_refresh_buttons()
	_build_pillars()
	
	
func _process(delta: float) -> void:
	if _vent_timer and _vent_timer.is_inside_tree():
		var left: float = _vent_timer.time_left
		if left > 0.0:
			vent_btn.text = "Venting… %ds" % int(ceil(left))

func _on_ignite() -> void:
	# Spend a little fuel and add EU using your heat multiplier if desired
	if GS.coolant < GS.COOLANT_PER_IGNITE:
		return
	if GameState.has_method("add_fuel"):
		GameState.add_fuel(-GameState.FUEL_PER_IGNITE)
	if GameState.has_method("add_coolant"):
		GameState.add_coolant(-GameState.COOLANT_PER_IGNITE)
	
	var mult: float = GameState.heat_rate_mult()
	GameState.add_eu(_ignite_delta() * mult)
	GameState.add_heat_pulse(GameState.IGNITE_HEAT_PULSE)

func _ignite_delta() -> float:
	return ignite_base + float(ignite_level)

func _on_ignite_upgrade() -> void:
	if GameState.spend_eu(ignite_upgrade_cost):
		ignite_level += 1
		ignite_upgrade_cost = ceil(ignite_upgrade_cost * ignite_cost_mult)
		_refresh_buttons()	

func _on_eu_bump(_v := 0.0) -> void:
	_refresh_buttons()

func _refresh_buttons() -> void:
	ignite_btn.text = "Ignite (+%s Eu)" % str(_ignite_delta())
	ignite_upgrade_btn.text = "Upgrade (Eu %d)" % int(ignite_upgrade_cost)
	ignite_upgrade_btn.disabled = GameState.eu < ignite_upgrade_cost

	# keep vent button in sync with model even if a signal was missed
	if "is_venting" in GameState:
		vent_btn.disabled = GameState.is_venting
	if (not GameState.has_method("is_venting") or not GameState.is_venting):
		if not _vent_timer or _vent_timer.time_left <= 0.0:
			vent_btn.text = "VENT"

func _on_vent() -> void:
	print("[UI] Vent button pressed")
	var gs := get_node_or_null("/root/GameState")
	print("[UI] GS node =", gs, " id=", (gs and gs.get_instance_id()))
	if gs and gs.has_method("start_vent"):
		gs.start_vent()
	else:
		print("[UI] ERROR: '/root/GameState' not found or start_vent missing")

	# start a local timer so we can show a countdown on the button
	if not _vent_timer:
		_vent_timer = Timer.new()
		_vent_timer.one_shot = true
		add_child(_vent_timer)
	_vent_timer.stop()
	_vent_timer.wait_time = 2.0
	_vent_timer.start()
	# connect local timeout once as a safety net, in case the model signal is missed
	if not _vent_timer.timeout.is_connected(_on_local_vent_timer_timeout):
		_vent_timer.timeout.connect(_on_local_vent_timer_timeout)
	_vent_timer.start()

func _on_vent_started() -> void:
	GS.start_vent()
	ignite_btn.disabled = true  # immediate lock
	vent_btn.disabled = true
	vent_btn.text = "Venting…"
	if ignite_button != null:
		ignite_button.disabled = true

func _on_vent_finished() -> void:
	vent_btn.disabled = false
	vent_btn.text = "VENT"
	_apply_venting_state()

func _on_local_vent_timer_timeout() -> void:
	# Fallback UI sync: if GameState is still venting, stay disabled; else re-enable
	if "is_venting" in GameState and GameState.is_venting:
		vent_btn.disabled = true
		vent_btn.text = "Venting…"
	else:
		vent_btn.disabled = false
		vent_btn.text = "VENT"

func _apply_venting_state() -> void:
	# Disable while venting or when manual ignition is not allowed
	if ignite_button == null:
		return
	if GameState.is_venting:
		ignite_button.disabled = true
		return
	ignite_button.disabled = not GameState.manual_ignite_enabled

func _build_pillars() -> void:
	# clear grid
	for c in pillar_grid.get_children():
		c.queue_free()
	_pillars.clear()

	# add pillars and hand each its index so it can talk to GameState
	for i in range(PILLAR_COUNT):
		var p: Node = PILLAR_SCENE.instantiate()
		pillar_grid.add_child(p)
		_pillars.append(p)
		if p.has_method("set_pillar_index"):
			p.set_pillar_index(i)
		elif "idx" in p:
			p.set("idx", i)

