extends HBoxContainer

@onready var GS = get_node("/root/GameState")

@onready var eu_label: Label    = $EuLabel
@onready var money_label: Label = $MoneyLabel

# Optional: set this in the Inspector; if blank we’ll try %EURateLabel, then deep search.
@export var eu_rate_label_path: NodePath
var EURateLabel: Label = null

var _accum := 0.0
var _warned := false
var _dbg_once := true

func _ready() -> void:
	# Resolve rate label robustly
	if not eu_rate_label_path.is_empty():
		EURateLabel = get_node_or_null(eu_rate_label_path) as Label
	if EURateLabel == null and has_node("%EURateLabel"):
		EURateLabel = %EURateLabel
	if EURateLabel == null:
		EURateLabel = find_child("EURateLabel", true, false) as Label
	if EURateLabel == null and !_warned:
		_warned = true
		push_warning("[HUD] Could not find Eu/t label. Set 'eu_rate_label_path' or give the label the unique name 'EURateLabel'.")

	_refresh_numbers()
	_refresh_rate()

	if GS.has_signal("eu_changed"):
		GS.eu_changed.connect(func(_v): _refresh_numbers())
	if GS.has_signal("money_changed"):
		GS.money_changed.connect(func(_v): _refresh_numbers())

	set_process(true)

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 0.15:
		_accum = 0.0
		_refresh_numbers()
		_refresh_rate()

func _refresh_numbers() -> void:
	if eu_label:
		eu_label.text = "Eu: %.1f" % GS.eu
	if money_label:
		money_label.text = "$$: %.1f" % GS.money

func _refresh_rate() -> void:
	var ept: float = 0.0
	if GS.has_method("get_eu_last_tick"):
		ept = float(GS.get_eu_last_tick())

	if EURateLabel:
		EURateLabel.text = "%0.2f Eu/tick" % ept
