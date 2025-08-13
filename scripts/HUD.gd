# Drop-in replacement for your current HUD.gd
# Fixes top bar stuck at 0 by:
#  - formatting the labels consistently
#  - listening to GS.eu_changed if present
#  - adding a tiny throttled _process() refresh so values update even if other code sets GS fields directly

extends HBoxContainer

@onready var eu_label: Label = $EuLabel
@onready var money_label: Label = $MoneyLabel
@onready var GS = get_node("/root/GameState")
#@onready var ept_label: Label = $EuRateLabel
@onready var EURateLabel: Label = %EURateLabel

const MA_WINDOW: int = 10   # keep last 10 ticks

var _samples: Array = []     # Array<float>
var _accum := 0.0

func _ready() -> void:
	# Update immediately
	_refresh()
	# If GS emits a signal when EU changes, hook it to refresh instantly
	if GS.has_signal("eu_changed"):
		GS.connect("eu_changed", Callable(self, "_on_state_bump"))
	# Low-cost polling as a safety net (covers money/fuel/coolant changes too)
	set_process(true)
	if GS.has_signal("eu_tick_generated"):
		GS.eu_tick_generated.connect(_on_eu_tick)
	if GS.has_signal("eu_rate_changed"):
		GS.eu_rate_changed.connect(_on_eu_rate)
	# seed UI from current state
	_update_rate_text(GS.get_eu_last_tick())

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 0.15:
		_accum = 0.0
		_refresh()

func _on_state_bump(_v := 0.0) -> void:
	_refresh()

func _refresh() -> void:
	eu_label.text = "Eu: %.1f" % GS.eu
	money_label.text = "$$: %.1f" % GS.money
	# ept_label.text = "Eu/t: %.1f" % GS._eu

func _on_eu_tick(amount: float) -> void:
	# amount is Eu produced THIS sim tick (pillars). Convert to display per tick.
	_add_sample(amount)
	_update_rate_text(_avg_samples())

func _on_eu_rate(per_sec: float) -> void:
	# If you prefer showing Eu/s somewhere else, you can hook here.
	pass

func _add_sample(v: float) -> void:
	_samples.append(v)
	if _samples.size() > MA_WINDOW:
		_samples.pop_front()

func _avg_samples() -> float:
	if _samples.is_empty():
		return 0.0
	var sum: float = 0.0
	for x in _samples:
		sum += float(x)
	return sum / float(_samples.size())

func _update_rate_text(eu_per_tick: float) -> void:
	if EURateLabel:
		EURateLabel.text = "%0.2f Eu/tick" % eu_per_tick
