extends PanelContainer

@onready var ignite_upgrade_btn: Button = $VBoxContainer/HBoxContainer2/IgniteUpgradeBtn
@onready var pillar_grid: GridContainer = $VBoxContainer/PillarGrid
@onready var GS = get_node("/root/GameState")

@export var vent_btn_path: NodePath
#@onready var vent_btn: Button = get_node(vent_btn_path)
@export var ignite_btn_path: NodePath
#@onready var ignite_btn: Button = get_node(ignite_btn_path)

@onready var vent_btn: Button = (
	(get_node_or_null(vent_btn_path) as Button)
	if not vent_btn_path.is_empty()
	else (find_child("VentBtn", true, false) as Button)
)

@onready var ignite_btn: Button = (
	(get_node_or_null(ignite_btn_path) as Button)
	if not ignite_btn_path.is_empty()
	else (find_child("IgniteBtn", true, false) as Button)
)

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
	
	if vent_btn and not vent_btn.pressed.is_connected(Callable(self, "_on_vent")):
		vent_btn.pressed.connect(_on_vent)
	
	GS.ensure_pillars(PILLAR_COUNT)
	ignite_btn.pressed.connect(_on_ignite)
	ignite_upgrade_btn.pressed.connect(_on_ignite_upgrade)

	if GS.has_signal("eu_changed"):
		GS.connect("eu_changed", Callable(self, "_on_eu_bump"))
	if GS.has_signal("venting_started"):
		GS.connect("venting_started", Callable(self, "_on_vent_started"))
	if GS.has_signal("venting_finished"):
		GS.connect("venting_finished", Callable(self, "_on_vent_finished"))
	
	_apply_venting_state()
	_refresh_buttons()
	_build_pillars()
	
	
func _process(delta: float) -> void:
	if vent_btn and _vent_timer and _vent_timer.is_inside_tree():
		var left: float = _vent_timer.time_left
		if left > 0.0:
			vent_btn.text = "Venting… %ds" % int(ceil(left))
		elif vent_btn.text != "VENT":
			vent_btn.text = "VENT"

func _on_ignite() -> void:
	if GS.is_venting or (not GS.manual_ignite_enabled):
		return
	if GS.coolant < GS.COOLANT_PER_IGNITE:
		return
	if GS.has_method("add_fuel"):
		GS.add_fuel(-GS.FUEL_PER_IGNITE)
	if GS.has_method("add_coolant"):
		GS.add_coolant(-GS.COOLANT_PER_IGNITE)
	var mult: float = GS.heat_rate_mult()
	GS.add_eu(_ignite_delta() * mult)
	GS.add_heat_pulse(GS.IGNITE_HEAT_PULSE)

func _ignite_delta() -> float:
	return ignite_base + float(ignite_level)

func _on_ignite_upgrade() -> void:
	if GS.spend_eu(ignite_upgrade_cost):
		ignite_level += 1
		ignite_upgrade_cost = ceil(ignite_upgrade_cost * ignite_cost_mult)
		_refresh_buttons()	

func _on_eu_bump(_v := 0.0) -> void:
	_refresh_buttons()

func _refresh_buttons() -> void:
	ignite_btn.text = "Ignite (+%s Eu)" % str(_ignite_delta())
	ignite_upgrade_btn.text = "Upgrade (Eu %d)" % int(ignite_upgrade_cost)
	ignite_upgrade_btn.disabled = GS.eu < ignite_upgrade_cost
	
	if vent_btn:
		vent_btn.disabled = GS.is_venting
	if ignite_btn:
		ignite_btn.disabled = GS.is_venting or (not GS.manual_ignite_enabled)
	
	# keep vent button in sync with model even if a signal was missed
	if (not GS.has_method("is_venting") or not GS.is_venting):
		if not _vent_timer or _vent_timer.time_left <= 0.0:
			vent_btn.text = "VENT"


func _on_vent() -> void:
	if GS.is_venting:
		return
	if vent_btn:
		vent_btn.disabled = true  # immediate UI feedback
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("start_vent"):
		gs.start_vent()
	# local countdown timer (unchanged)
	if not _vent_timer:
		_vent_timer = Timer.new()
		_vent_timer.one_shot = true
		add_child(_vent_timer)
	_vent_timer.stop()
	_vent_timer.wait_time = float(GS.vent_duration)
	if not _vent_timer.timeout.is_connected(_on_local_vent_timer_timeout):
		_vent_timer.timeout.connect(_on_local_vent_timer_timeout)
	_vent_timer.start()

func _on_vent_started() -> void:
	if vent_btn:   vent_btn.disabled = true
	if ignite_btn: ignite_btn.disabled = true

func _on_vent_finished() -> void:
	_apply_venting_state()
	if vent_btn:
		vent_btn.text = "VENT"

func _on_local_vent_timer_timeout() -> void:
	# Fallback UI sync: if GameState is still venting, stay disabled; else re-enable
	if "is_venting" in GameState and GameState.is_venting:
		vent_btn.disabled = true
		vent_btn.text = "Venting…"
	else:
		vent_btn.disabled = false
		vent_btn.text = "VENT"

func _apply_venting_state() -> void:
	if vent_btn:
		vent_btn.disabled = GS.is_venting
	if ignite_btn:
		ignite_btn.disabled = GS.is_venting or (not GS.manual_ignite_enabled)

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

