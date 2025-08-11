extends PanelContainer

@onready var ignite_btn: Button         = $VBoxContainer/HBoxContainer2/IgniteBtn
@onready var ignite_upgrade_btn: Button = $VBoxContainer/HBoxContainer2/IgniteUpgradeBtn
@onready var vent_btn: Button           = $VBoxContainer/HBoxContainer/VentBtn
@onready var temp_bar: Range            = $VBoxContainer/HBoxContainer/TempBar
@onready var pillar_grid: GridContainer = $VBoxContainer/PillarGrid

const HEAT_PULSE_PER_IGNITE: float = 6.0

var ignite_level: int = 0
var ignite_base: float = 2.0
var ignite_upgrade_cost: float = 50.0
var ignite_cost_mult: float = 1.6

func _ready() -> void:
	GameState.ensure_pillars(PILLAR_COUNT)
	ignite_btn.pressed.connect(_on_ignite)
	ignite_upgrade_btn.pressed.connect(_on_ignite_upgrade)
	vent_btn.pressed.connect(_on_vent)

	if GameState.has_signal("eu_changed"):
		GameState.connect("eu_changed", Callable(self, "_on_eu_bump"))

	if GameState.has_signal("heat_changed"):
		GameState.heat_changed.connect(_on_heat_changed)
	_on_heat_changed(GameState.heat)
	
	_refresh_buttons()
	_build_pillars()

func _on_ignite() -> void:
	GameState.add_fuel(-GameState.FUEL_PER_IGNITE)
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
	var mult: float = GameState.heat_rate_mult()
	var eu_gain: float = _ignite_delta() * mult
	GameState.add_eu(eu_gain)	

func _on_heat_changed(v: float) -> void:
	# Keep the Production panel TempBar in sync (0..100)
	if temp_bar:
		temp_bar.value = int(round(v))

func _on_eu_bump(_v := 0.0) -> void:
	_refresh_buttons()

func _refresh_buttons() -> void:
	ignite_btn.text = "Ignite (+%s Eu)" % str(_ignite_delta())
	ignite_upgrade_btn.text = "Upgrade (Eu %d)" % int(ignite_upgrade_cost)
	ignite_upgrade_btn.disabled = GameState.eu < ignite_upgrade_cost

func _on_vent() -> void:
	GameState.start_venting(2.0)  # simple stub; see GameState.gd
	vent_btn.disabled = true
	if GameState.has_signal("vent_finished"):
		GameState.connect("vent_finished", Callable(self, "_on_vent_finished"))

func _on_vent_finished() -> void:
	vent_btn.disabled = false

const PILLAR_SCENE := preload("res://scenes/ReactionPillar.tscn")
const PILLAR_COUNT := 6
var _pillars: Array = []

func _build_pillars() -> void:
	GameState.ensure_pillars(PILLAR_COUNT)

	# clear grid
	for c in pillar_grid.get_children():
		c.queue_free()
	_pillars.clear()

	# add pillars
	for i in range(PILLAR_COUNT):
		var p := PILLAR_SCENE.instantiate()
		pillar_grid.add_child(p)
		_pillars.append(p)

		# hand the index to the instance
		if p.has_method("set_pillar_index"):
			p.set_pillar_index(i)
		else:
			# fallback if you exported a var
			p.set("idx", i)  # works if you have @export var idx: int

