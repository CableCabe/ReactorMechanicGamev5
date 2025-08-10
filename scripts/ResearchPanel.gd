# Drop-in patch for your current ResearchPanel.gd
# Focus: remove references to `_all_item_rows` and define `_apply_item`
# Assumes you have GameState as an autoload with `eu` and `research_db`

extends PanelContainer

var _rows: Dictionary = {}  # key -> {meta, buy_button, cost_label, row}

@onready var list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/List

func _ready() -> void:
	GameState.eu_changed.connect(_refresh_affordability)
	_build()
	_refresh_affordability(GameState.eu)

func _build() -> void:
	# Clear UI & data
	for c in list.get_children():
		c.queue_free()
	_rows.clear()

	# Build from research db
	for key in GameState.research_db.keys():
		var meta: Dictionary = GameState.research_db[key]
		_make_row(key, meta)

func _make_row(key: String, meta: Dictionary) -> void:
	var h := HBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = meta.get("name", key)

	var cost_lbl := Label.new()
	var cost_eu := float(meta.get("cost", {}).get("eu", 0))
	cost_lbl.text = "%d EU" % int(cost_eu)

	var btn := Button.new()
	btn.text = "Buy"
	btn.pressed.connect(_on_buy.bind(key))

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
	}

func _refresh_affordability(_v: float) -> void:
	# FIX: iterate current rows instead of `_all_item_rows`
	for item in _rows.values():
		var meta: Dictionary = item["meta"]
		var cost_eu: float = float(meta.get("cost", {}).get("eu", 0))
		var afford_ok := GameState.eu >= cost_eu
		item["buy_button"].disabled = not afford_ok
		item["buy_button"].tooltip_text = "Need %d EU | Have %d EU" % [int(cost_eu), int(GameState.eu)]
		# optional visual: dim cost label if unaffordable
		(item["cost_label"] as Label).modulate = Color(1,1,1) if afford_ok else Color(1,0.6,0.6)

func _on_buy(key: String) -> void:
	var item: Dictionary = _rows.get(key)
	if item == null:
		return
	var cost_eu: float = float(item["meta"].get("cost", {}).get("eu", 0))
	if GameState.spend_eu(cost_eu):
		_apply_item(key)  # see below
	else:
		# TODO: flash not-enough animation
		pass

func _apply_item(key: String) -> void:
	# TODO: call into your real application logic.
	# Example: GameState.apply_research(key)
	# For now, just log and refresh the button state
	print("Applied research:", key)
	_refresh_affordability(GameState.eu)
