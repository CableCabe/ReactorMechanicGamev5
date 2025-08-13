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
var _dbg_left := 8

var _last_eu: float = 0.0
var _sample_accum: float = 0.0
var _tick_len: float = 0.1  # will read GS.STEP if present

func _ready() -> void:
	_refresh()
	
	if "STEP" in GS:
		_tick_len = float(GS.STEP)

	_last_eu = GS.eu

	# EU value updates
	if GS.has_signal("eu_changed") and not GS.eu_changed.is_connected(Callable(self, "_on_state_bump")):
		GS.eu_changed.connect(_on_state_bump)

	# Eu/tick stream
	if GS.has_signal("eu_tick_generated") and not GS.eu_tick_generated.is_connected(Callable(self, "_on_eu_tick")):
		GS.eu_tick_generated.connect(_on_eu_tick)
	# Optional Eu/s stream
	if GS.has_signal("eu_rate_changed") and not GS.eu_rate_changed.is_connected(Callable(self, "_on_eu_rate")):
		GS.eu_rate_changed.connect(_on_eu_rate)

	_update_rate_text(GS.get_eu_last_tick())
	set_process(true)

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 0.15:
		_accum = 0.0
		_refresh()
	
	_sample_accum += delta
	if _sample_accum >= _tick_len:
		_sample_accum -= _tick_len
		var cur: float = GS.eu
		var d: float = cur - _last_eu
		if d < 0.0:
			d = 0.0  # ignore sinks (selling, spending) for Eu/t production
		_last_eu = cur
		if d > 0.0:
			_add_sample(d)
			_update_rate_text(_avg_samples())
		elif _samples.is_empty():
			# keep label from sitting at stale 0 when nothing produced yet
			_update_rate_text(GS.get_eu_last_tick())

func _on_state_bump(_v := 0.0) -> void:
	_refresh()

func _refresh() -> void:
	if eu_label:
		eu_label.text = "Eu: %.1f" % GS.eu
	if money_label:
		money_label.text = "$$: %.1f" % GS.money

func _on_eu_tick(amount: float) -> void:
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
