
extends PanelContainer

@onready var fuel_value: Label    = %FStorLabel
@onready var coolant_value: Label = %CStorLabel
@onready var heat_value: Label    = %HStorLabel

@onready var fuel_bar: ProgressBar    = %FuelBar
@onready var coolant_bar: ProgressBar = %CoolBar
@onready var heat_bar: ProgressBar    = %HeatBar

@onready var fuel_drain: Label    = %FDrainLabel
@onready var coolant_drain: Label = %CDrainLabel

@onready var fuel_warn: Label    = %FWarningLabel
@onready var coolant_warn: Label = %CWarningLabel
@onready var heat_warn: Label    = %HWarningLabel

@onready var warnings: WarningsPanel = %WarningsPanel
@onready var GS = get_node("/root/GameState")

# Thresholds: green for 25–100%, yellow for 10–25%, red for <10%
const GREEN_MIN := 0.25
const YELLOW_MIN := 0.10

var _acc: float = 0.0
var _prev_fuel: float = 0.0
var _prev_coolant: float = 0.0

func _ready() -> void:
	set_process(true)

	if heat_bar:
		heat_bar.min_value = 0
		heat_bar.max_value = 100
		heat_bar.step = 1.0
		heat_bar.page = 0.0
		heat_bar.allow_greater = false
		heat_bar.allow_lesser = false

	if fuel_bar:
		fuel_bar.min_value = 0
		fuel_bar.step = 1.0
		fuel_bar.allow_greater = false

	if coolant_bar:
		coolant_bar.min_value = 0
		coolant_bar.step = 1.0
		coolant_bar.allow_greater = false
		
	if GS.has_signal("fuel_changed"):
		GS.fuel_changed.connect(_on_fuel_changed)
	if GS.has_signal("coolant_changed"):
		GS.coolant_changed.connect(_on_coolant_changed)
	if GS.has_signal("heat_changed"):
		GS.heat_changed.connect(_on_heat_changed)
	
	_prev_fuel = GS.fuel
	_prev_coolant = GS.coolant
	
	_on_heat_changed(GS.heat)
	_on_fuel_changed(GS.fuel)
	_on_coolant_changed(GS.coolant)

	_refresh()
	
	if warnings:
		warnings.register_system("heat",    $ReactorView/MarginContainer/VBoxContainer/HeatPanel)
		warnings.register_system("fuel",    $ReactorView/MarginContainer/VBoxContainer/FuelPanel)
		warnings.register_system("cooling", $ReactorView/MarginContainer/VBoxContainer/CoolPanel)
		warnings.hook_standard_events()  # wires HEAT (venting) + FUEL
		
	# TEMP: prove UI shows — remove after you see it
		warnings.add_message("heat", "(test) warnings panel alive", "info")
	
	if warnings != null and warnings.has_method("add_light"):
		# Update these child paths to your actual rows under the warnings panel
		var row_heat := warnings.get_node_or_null("VBoxContainer/HeatPanel")
		var row_fuel := warnings.get_node_or_null("VBoxContainer/FuelPanel")
		var row_cooling := warnings.get_node_or_null("VBoxContainer/CoolPanel")
		if row_heat != null:
			warnings.call("add_light", "heat", row_heat)
		if row_fuel != null:
			warnings.call("add_light", "fuel", row_fuel)
		if row_cooling != null:
			warnings.call("add_light", "cooling", row_cooling)
		warnings.call("hook_standard_events")

func set_cooling_warning(on: bool, text: String) -> void:
	if warnings != null and warnings.has_method("set_cooling"):
		warnings.call("set_cooling", on, text)

var _dbg_left := 10

func _on_heat_changed(v: float) -> void:
	var hp: float
	if _dbg_left > 0:
		_dbg_left -= 1
	if v > 1.0:
		hp = clamp(v / 100.0, 0.0, 1.0)
	else:
		hp = clamp(v, 0.0, 1.0)
	var hv: int = int(round(hp * 100.0))
	if heat_bar:
		heat_bar.value = hv
		_tint_progress_bar(heat_bar, _color_by_pct(hp, true))

func _update_drain_label(lbl: Label, prev_value: float, new_value: float, unit: String) -> float:
	var diff: float = prev_value - new_value
	if lbl:
		if diff > 0.0:
			lbl.text = "-%0.2f %s/tick" % [diff, unit]
		elif diff < 0.0:
			lbl.text = "+%0.2f %s/tick" % [abs(diff), unit]
		else:
			lbl.text = "0.00 %s/tick" % unit
	return new_value

func _on_fuel_changed(v: float) -> void:
	# update drain label first, then UI text/bar
	_prev_fuel = _update_drain_label(fuel_drain, _prev_fuel, v, "ml")

	if fuel_value:
		fuel_value.text = "%0.0f ml" % v
	if fuel_bar:
		fuel_bar.max_value = GS.fuel_cap
		fuel_bar.value = clamp(v, 0.0, GS.fuel_cap)
		_tint_progress_bar(fuel_bar, _color_by_pct(v / max(1.0, GS.fuel_cap), false))

func _on_coolant_changed(v: float) -> void:
	_prev_coolant = _update_drain_label(coolant_drain, _prev_coolant, v, "ml")

	if coolant_value:
		coolant_value.text = "%0.0f ml" % v
	if coolant_bar:
		coolant_bar.max_value = GS.coolant_cap
		coolant_bar.value = clamp(v, 0.0, GS.coolant_cap)
		_tint_progress_bar(coolant_bar, _color_by_pct(v / max(1.0, GS.coolant_cap), false))

func _process(delta: float) -> void:
	_acc += delta
	if _acc >= 0.25:
		_acc = 0.0
		_refresh()

func _refresh() -> void:
	var fuel_cap: float = 100.0
	if "fuel_cap" in GS:
		fuel_cap = float(GS.fuel_cap)
	var coolant_cap: float = 100.0
	if "coolant_cap" in GS:
		coolant_cap = float(GS.coolant_cap)

	# numbers
	if fuel_value:
		fuel_value.text = "%0.0f ml" % GS.fuel
	if coolant_value:
		coolant_value.text = "%0.0f ml" % GS.coolant
	if heat_value:
		var hp: float = _heat_pct()
		heat_value.text = "%d%%" % int(round(hp * 100.0))

	# bars
	if fuel_bar:
		fuel_bar.max_value = fuel_cap
		fuel_bar.value = clamp(GS.fuel, 0.0, fuel_cap)
		_tint_progress_bar(fuel_bar, _color_by_pct(GS.fuel / max(1.0, fuel_cap), false))
	if coolant_bar:
		coolant_bar.max_value = coolant_cap
		coolant_bar.value = clamp(GS.coolant, 0.0, coolant_cap)
		_tint_progress_bar(coolant_bar, _color_by_pct(GS.coolant / max(1.0, coolant_cap), false))
	var hp: float = _heat_pct()
	var hv: int = int(round(hp * 100.0))
	if heat_bar:
		heat_bar.value = hv
		_tint_progress_bar(heat_bar, _color_by_pct(hp, true))

# --- helpers ---
func _heat_pct() -> float:
	if "heat" in GS:
		var h: float = float(GS.heat)
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
