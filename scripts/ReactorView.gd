# ReactorView.gd — sidebar counters + live progress bars with color states
# Assign the exported NodePaths in the Inspector to your right-justified labels
# and to the three ProgressBars for Fuel, Coolant, and Heat.

extends PanelContainer

@export var fuel_value_path: NodePath
@export var coolant_value_path: NodePath
@export var heat_value_path: NodePath      # optional, numeric % label next to HEAT

@export var fuel_bar_path: NodePath
@export var coolant_bar_path: NodePath
@export var heat_bar_path: NodePath

@onready var fuel_value: Label    = get_node(fuel_value_path) as Label
@onready var coolant_value: Label = get_node(coolant_value_path) as Label
@onready var heat_value: Label    = get_node_or_null(heat_value_path) as Label

@onready var fuel_bar: ProgressBar    = get_node(fuel_bar_path) as ProgressBar
@onready var coolant_bar: ProgressBar = get_node(coolant_bar_path) as ProgressBar
@onready var heat_bar: ProgressBar    = get_node(heat_bar_path) as ProgressBar

# Thresholds: green for 25–100%, yellow for 10–25%, red for <10%
const GREEN_MIN := 0.25
const YELLOW_MIN := 0.10

var _acc: float = 0.0

func _ready() -> void:
	set_process(true)
	_refresh()

func _process(delta: float) -> void:
	_acc += delta
	if _acc >= 0.25:
		_acc = 0.0
		_refresh()

func _refresh() -> void:
	var fuel_cap: float = 100.0
	if "fuel_cap" in GameState:
		fuel_cap = float(GameState.fuel_cap)
	var coolant_cap: float = 100.0
	if "coolant_cap" in GameState:
		coolant_cap = float(GameState.coolant_cap)

	# numbers
	if fuel_value:
		fuel_value.text = "%0.0f ml" % GameState.fuel
	if coolant_value:
		coolant_value.text = "%0.0f ml" % GameState.coolant
	if heat_value:
		var hp: float = _heat_pct()
		heat_value.text = "%d%%" % int(round(hp * 100.0))

	# bars
	if fuel_bar:
		fuel_bar.max_value = fuel_cap
		fuel_bar.value = clamp(GameState.fuel, 0.0, fuel_cap)
		_tint_progress_bar(fuel_bar, _color_by_pct(GameState.fuel / max(1.0, fuel_cap), false))
	if coolant_bar:
		coolant_bar.max_value = coolant_cap
		coolant_bar.value = clamp(GameState.coolant, 0.0, coolant_cap)
		_tint_progress_bar(coolant_bar, _color_by_pct(GameState.coolant / max(1.0, coolant_cap), false))
	if heat_bar:
		heat_bar.max_value = 100.0
		var hpct: float = _heat_pct()
		heat_bar.value = hpct * 100.0
		_tint_progress_bar(heat_bar, _color_by_pct(hpct, true))

# --- helpers ---
func _heat_pct() -> float:
	if "heat" in GameState:
		var h: float = float(GameState.heat)
		if h > 1.0:
			return clamp(h / 100.0, 0.0, 1.0)
		return clamp(h, 0.0, 1.0)
	return 0.0

func _color_by_pct(pct: float, invert: bool) -> Color:
	var p: float = clamp(pct, 0.0, 1.0)
	if invert:
		p = 1.0 - p
	if p >= GREEN_MIN:
		return Color(0.40, 0.80, 0.50)  # green
	elif p >= YELLOW_MIN:
		return Color(0.86, 0.74, 0.31)  # yellow
	return Color(0.85, 0.35, 0.35)      # red

func _tint_progress_bar(bar: ProgressBar, color: Color) -> void:
	# Override the fill style color so we don't need custom themes.
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", fill)
