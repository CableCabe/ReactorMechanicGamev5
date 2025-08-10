extends PanelContainer

@onready var ignite_btn: Button         = $VBoxContainer/HBoxContainer2/IgniteBtn
@onready var ignite_upgrade_btn: Button = $VBoxContainer/HBoxContainer2/IgniteUpgradeBtn
@onready var vent_btn: Button           = $VBoxContainer/HBoxContainer/VentBtn
@onready var temp_bar: Range            = $VBoxContainer/HBoxContainer/TempBar


var ignite_level: int = 0
var ignite_base: float = 2.0
var ignite_upgrade_cost: float = 50.0
var ignite_cost_mult: float = 1.6

func _ready() -> void:
	ignite_btn.pressed.connect(_on_ignite)
	ignite_upgrade_btn.pressed.connect(_on_ignite_upgrade)
	vent_btn.pressed.connect(_on_vent)

	if GameState.has_signal("eu_changed"):
		GameState.connect("eu_changed", Callable(self, "_on_eu_bump"))

	_refresh_buttons()

func _on_ignite() -> void:
	GameState.add_eu(_ignite_delta())

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

func _on_vent() -> void:
	GameState.start_venting(2.0)  # simple stub; see GameState.gd
	vent_btn.disabled = true
	if GameState.has_signal("vent_finished"):
		GameState.connect("vent_finished", Callable(self, "_on_vent_finished"))

func _on_vent_finished() -> void:
	vent_btn.disabled = false
