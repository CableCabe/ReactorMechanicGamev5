# Drop-in replacement for your current HUD.gd
# Fixes top bar stuck at 0 by:
#  - formatting the labels consistently
#  - listening to GS.eu_changed if present
#  - adding a tiny throttled _process() refresh so values update even if other code sets GS fields directly

extends HBoxContainer

@onready var eu_label: Label = $EuLabel
@onready var money_label: Label = $MoneyLabel
@onready var GS = get_node("/root/GameState")
# @onready var fuel_label: Label = $Fuel
# @onready var coolant_label: Label = $Coolant

var _accum := 0.0

func _ready() -> void:
	# Update immediately
	_refresh()
	# If GS emits a signal when EU changes, hook it to refresh instantly
	if GS.has_signal("eu_changed"):
		GS.connect("eu_changed", Callable(self, "_on_state_bump"))
	# Low-cost polling as a safety net (covers money/fuel/coolant changes too)
	set_process(true)

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 0.25: # refresh ~4 times per second
		_accum = 0.0
		_refresh()

func _on_state_bump(_v := 0.0) -> void:
	_refresh()

func _refresh() -> void:
	eu_label.text = "Eu: %.1f" % GS.eu
	money_label.text = "$$: %.1f" % GS.money
	# fuel_label.text = "Fuel: %.1f" % GS.fuel
	# coolant_label.text = "Coolant: %.1f" % GS.coolant
