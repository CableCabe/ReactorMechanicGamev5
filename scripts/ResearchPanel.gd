# Drop-in patch for your current ResearchPanel.gd
# Focus: remove references to `_all_item_rows` and define `_apply_item`
# Assumes you have GameState as an autoload with `eu` and `research_db`

extends PanelContainer

var _rows: Dictionary = {}  # key -> {meta, buy_button, cost_label, row}

# Using explicit path so you don't need the Unique Name toggle right now
@onready var list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/List

signal research_loaded
var research_db: Dictionary = {}

func _ready() -> void:
	# Always build once (shows placeholder if DB empty), then listen for updates
	GameState.eu_changed.connect(_refresh_affordability)
	assert(list != null, "ResearchPanel: List container not found at $MarginContainer/VBoxContainer/ScrollContainer/List")
	_build()
	_load_research()
	_refresh_affordability(GameState.eu)
	# If GameState emits `research_loaded` after loading JSON, hook it up.
	if GameState.has_signal("research_loaded"):
		GameState.connect("research_loaded", Callable(self, "_on_research_loaded"))

func _load_research() -> void:
	var path = "res://data/research.json"
	if not FileAccess.file_exists(path):
		push_error("Missing research.json at " + path)
		research_loaded.emit()
		return

	var f = FileAccess.open(path, FileAccess.READ)
	var raw = f.get_as_text()
	var parsed = JSON.parse_string(raw)  # untyped on purpose to avoid warnings-as-errors

	if typeof(parsed) == TYPE_DICTIONARY:
		research_db = parsed
	elif typeof(parsed) == TYPE_ARRAY:
		var d = {}
		for e in parsed:
			var k = e.get("key", e.get("id", e.get("name", "item_%d" % d.size())))
			d[k] = e
		research_db = d
	else:
		push_error("Unexpected JSON shape in " + path)

	print("Loaded research entries:", research_db.size())
	research_loaded.emit()

func _build() -> void:
	# safety: bail if db not ready
	if GameState.research_db.size() == 0:
		# optional: show a placeholder row so we know UI is alive
		list.add_child(Label.new())
		(list.get_child(list.get_child_count()-1) as Label).text = "Research data not loaded"
		return
	# Clear UI & data
	for c in list.get_children():
		c.queue_free()
	_rows.clear()

	# Build from research db
	for key in GameState.research_db.keys():
		var meta: Dictionary = GameState.research_db[key]
		_make_row(key, meta)
	print("ResearchPanel built rows:", _rows.size(), "list children:", list.get_child_count())

# -- internal: build one row --
func _make_row(key: String, meta: Dictionary) -> void:
	var h := HBoxContainer.new()

	var cost_lbl := Label.new()
	var cost_eu := _cost_eu_for_next_level(key, meta)
	cost_lbl.text = "%d Eu" % int(cost_eu)

	var name_lbl := Label.new()
	name_lbl.text = meta.get("name", key)

	var btn := Button.new()
	btn.text = "Buy"
	btn.pressed.connect(_on_buy.bind(key))

	btn.mouse_entered.connect(_on_row_hover.bind(key, true))
	btn.mouse_exited.connect(_on_row_hover.bind(key, false))
	h.mouse_entered.connect(_on_row_hover.bind(key, true))
	h.mouse_exited.connect(_on_row_hover.bind(key, false))

	h.add_child(name_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	h.add_child(cost_lbl)
	h.add_child(btn)
	list.add_child(h)

	_rows[key] = {
		"meta": meta,
		"buy_button": btn,
		"cost_label": cost_lbl,
		"row": h,
		"level": _get_next_level_index(key),
	}

func _on_row_hover(key: String, inside: bool) -> void:
	var item: Dictionary = _rows.get(key)
	if item == null: return
	var meta: Dictionary = item["meta"]
	var cost_eu := _cost_eu_from(meta)
	var afford_ok := GameState.eu >= cost_eu
	var lbl := item["cost_label"] as Label

	if not afford_ok and inside:
		lbl.modulate = Color(1, 0.6, 0.6)  # soft red on hover when can't afford
	else:
		lbl.modulate = Color(1, 1, 1)      # reset when leaving or if affordable


# -- internal: enable/disable buttons based on EU --
func _refresh_affordability(_v: float) -> void:
	for item_key in _rows.keys():
		var row: Dictionary = _rows[item_key]
		var meta: Dictionary = row["meta"]
		var cost_eu := _cost_eu_for_next_level(item_key, meta)
		var afford_ok := GameState.eu >= cost_eu

		(row["buy_button"] as Button).disabled = not afford_ok
		(row["buy_button"] as Button).tooltip_text = "Need %d Eu | Have %d Eu" % [int(cost_eu), int(GameState.eu)]
		(row["cost_label"] as Label).modulate = Color(1,1,1)

# -- internal: handle Buy click --
func _on_buy(key: String) -> void:
	var row: Dictionary = _rows.get(key)
	if row == null: return

	var meta: Dictionary = row["meta"]
	var cost_eu := _cost_eu_for_next_level(key, meta)

	if GameState.spend_eu(cost_eu):
		# advance level
		var new_lvl := _get_next_level_index(key) + 1
		_set_level_index(key, new_lvl)

		# update label to show next level's price (or 0 if maxed)
		var next_cost := _cost_eu_for_next_level(key, meta)
		(row["cost_label"] as Label).text = "%d Eu" % int(next_cost)

		_apply_item(key)  # your real effect hook
		_refresh_affordability(GameState.eu)
	else:
		# optional: flash not-enough
		pass

# -- internal: apply the effect of a research --
func _apply_item(key: String) -> void:
	# TODO: call into your real application logic.
	# Example: GameState.apply_research(key)
	# For now, just log and refresh the button state
	print("Applied research:", key)
	_refresh_affordability(GameState.eu)

# -- callbacks --
func _on_research_loaded() -> void:
	# Rebuild once data arrives
	_build()
	_refresh_affordability(GameState.eu)

# --- helpers: robust cost parsing ---
func _parse_number_any(s: String) -> float:
	var re := RegEx.new()
	re.compile("-?\\d+(?:\\.\\d+)?")
	var m := re.search(s)
	if m and m.get_string() != null:
		return float(m.get_string())
	return 0.0

func _extract_eu_any(v) -> float:
	var t := typeof(v)
	if t == TYPE_INT or t == TYPE_FLOAT:
		return float(v)
	if t == TYPE_STRING:
		return _parse_number_any(v)
	if t == TYPE_DICTIONARY:
		# prefer likely keys first
		for k in v.keys():
			var key := String(k).to_lower()
			if key in ["eu","cost_eu","price_eu","price","amount","value","cost","unlock","upgrade","unlock_cost"]:
				var n := _extract_eu_any(v[k])
				if n != 0.0:
					return n
		# fallback: scan all values
		for val in v.values():
			var n2 := _extract_eu_any(val)
			if n2 != 0.0:
				return n2
	if t == TYPE_ARRAY:
		for val in v:
			var n3 := _extract_eu_any(val)
			if n3 != 0.0:
				return n3
	return 0.0

func _cost_eu_from(meta: Dictionary) -> float:
	var n := 0.0
	if meta.has("cost"):
		n = _extract_eu_any(meta["cost"])
	if n == 0.0 and meta.has("eu"):
		n = _extract_eu_any(meta["eu"])
	if n == 0.0 and meta.has("EU"):
		n = _extract_eu_any(meta["EU"])
	if n == 0.0 and meta.has("price"):
		n = _extract_eu_any(meta["price"])
	if n == 0.0 and meta.has("unlock"):
		n = _extract_eu_any(meta["unlock"])
	if n == 0.0 and meta.has("unlock_cost"):
		n = _extract_eu_any(meta["unlock_cost"])
	if n == 0.0 and meta.has("cost_eu"):
		n = _extract_eu_any(meta["cost_eu"])
	return n

func _get_next_level_index(key: String) -> int:
	# prefer GameState storage if you have it; fall back to per-row memory; else 0
	if "research_levels" in GameState:
		return int(GameState.research_levels.get(key, 0))
	if _rows.has(key) and _rows[key].has("level"):
		return int(_rows[key]["level"])
	return 0

func _set_level_index(key: String, lvl: int) -> void:
	if "research_levels" in GameState:
		GameState.research_levels[key] = lvl
	else:
		if _rows.has(key):
			_rows[key]["level"] = lvl

func _cost_eu_for_next_level(key: String, item: Dictionary) -> float:
	var levels = item.get("levels", [])
	if typeof(levels) != TYPE_ARRAY or levels.size() == 0:
		return 0.0
	var idx := _get_next_level_index(key)
	if idx >= levels.size():
		return 0.0
	var lvl: Dictionary = levels[idx]
	var cost = lvl.get("cost", {})
	if typeof(cost) == TYPE_DICTIONARY:
		return float(cost.get("eu", 0))
	return float(cost)  # number fallback


