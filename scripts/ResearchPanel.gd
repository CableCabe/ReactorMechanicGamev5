class_name ResearchPanel
extends PanelContainer

var _rows: Dictionary = {}   # key -> {row, name, level, cost, btn}

@onready var list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/List
@onready var GS = get_node("/root/GameState")

func _ready() -> void:
	GameState._load_research_db()
	_build()
	_refresh()

#func GS() -> Node:
#	return get_node("/root/GameState")  # explicit autoload instance

func _build() -> void:
	# clear
	for c in list.get_children():
		c.queue_free()
	_rows.clear()

	# build, grouped by tier
	var tiers := []
	for key in GameState.research_db.keys():
		var t := int(GameState.research_db[key].get("tier", 1))
		if t not in tiers:
			tiers.append(t)
	tiers.sort()

	for tier in tiers:
		var header := Label.new()
		header.text = "Tier %d" % tier
		header.add_theme_color_override("font_color", Color(0.9,0.9,1))
		list.add_child(header)

		for key in GameState.research_db.keys():
			var node: Dictionary = GameState.research_db[key]
			if int(node.get("tier", 1)) != tier:
				continue
			var row := _make_row(key, node)
			list.add_child(row)

func _make_row(key: String, node: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)

	var name_lbl := Label.new()
	name_lbl.text = String(node.get("name", key))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var level_lbl := Label.new()
	row.add_child(level_lbl)

	var cost_lbl := Label.new()
	cost_lbl.modulate = Color(0.8,0.8,0.9)
	row.add_child(cost_lbl)

	var btn := Button.new()
	btn.text = "Buy"
	btn.pressed.connect(_on_buy.bind(key))
	row.add_child(btn)

	_rows[key] = {
		"row": row,
		"name": name_lbl,
		"level": level_lbl,
		"cost": cost_lbl,
		"btn": btn
	}
	return row


func _refresh() -> void:
	for key in _rows.keys():
		var lvl      = GS.research_level(key)
		var max_lvl  = GS.research_max_level(key)
		var cost     = GS.research_cost(key)

		var parts: Array = []
		if cost.has("eu"): parts.append("Eu %.0f" % float(cost["eu"]))
		if cost.has("money"): parts.append("$ %.0f" % float(cost["money"]))

		var r: Dictionary = _rows[key]
		(r["level"] as Label).text = "Lv %d/%d" % [lvl, max_lvl]
		(r["cost"] as Label).text = ("( " + ", ".join(parts) + " )") if parts.size() > 0 else ""

		# NEW: diagnose availability
		var deps_ok  = GS.research_deps_satisfied(key)
		var lvl_ok: bool = lvl < max_lvl
		var afford_ok= GS.can_afford(cost)

		var btn := r["btn"] as Button
		btn.disabled = not (deps_ok and lvl_ok and afford_ok)

		# tooltip explains why
		var reasons: Array = []
		if not deps_ok:
			var deps: Array = GameState.research_db.get(key, {}).get("deps", [])
			reasons.append("Requires: " + ", ".join(deps))
		if not lvl_ok: reasons.append("Already maxed")
		if not afford_ok: reasons.append("Not enough currency")

		# reasons was built above (deps/maxed/afford)
		var need_bits: Array = []
		if cost.has("eu"):
			need_bits.append("Eu: %.2f / %.2f" % [GS.eu, float(cost["eu"])])
		if cost.has("money"):
			need_bits.append("$: %.2f / %.2f" % [GS.money, float(cost["money"])])

		var left := (", ".join(reasons)) if reasons.size() > 0 else ""
		var right := (", ".join(need_bits)) if need_bits.size() > 0 else ""
		btn.tooltip_text = (left + (" • " if left != "" and right != "" else "") + right)
		
		# btn.tooltip_text = (", ".join(reasons)) if reasons.size() > 0 \
		#	else String(GameState.research_db.get(key, {}).get("desc", ""))


		# optional: red cost when unaffordable
		(r["cost"] as Label).modulate = Color(0.8, 0.8, 0.9) if afford_ok else Color(1, 0.6, 0.6)


# on buy
func _on_buy(key: String) -> void:
	GS.buy_research(key)
	_refresh()
