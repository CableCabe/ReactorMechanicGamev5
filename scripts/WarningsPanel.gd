extends PanelContainer
class_name WarningsPanel

const MAX_MESSAGES_DEFAULT := 50
var _systems := {}  # key -> { light: TextureRect, vbox: VBoxContainer, scroll: ScrollContainer, max: int }

func register_system(key: String, row: HBoxContainer, max_messages: int = MAX_MESSAGES_DEFAULT) -> void:
	if row == null:
		push_error("WarningsPanel.register_system: row is null for key '%s'" % key)
		return

	# Light
	var light := row.get_node_or_null("Light") as TextureRect
	if light == null:
		push_error("WarningsPanel.register_system: '%s' missing child 'Light'" % row.name)

	# Ensure MessageBox/Scroll/VBox exist; tolerate variant names
	var msg_box := row.get_node_or_null("MessageBox") as PanelContainer
	if msg_box == null:
		msg_box = PanelContainer.new()
		msg_box.name = "MessageBox"
		row.add_child(msg_box)

	var scroll := msg_box.get_node_or_null("Scroll") as ScrollContainer
	if scroll == null:
		scroll = ScrollContainer.new()
		scroll.name = "Scroll"
		msg_box.add_child(scroll)

	var vbox := scroll.get_node_or_null("VBox") as VBoxContainer
	if vbox == null:
		vbox = scroll.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox == null:
		vbox = VBoxContainer.new()
		vbox.name = "VBox"
		scroll.add_child(vbox)

	_systems[key] = {
		"light": light,
		"vbox": vbox,
		"scroll": scroll,
		"max": max_messages
	}
	set_light(key, false)
	clear_messages(key)

func set_light(key: String, on: bool) -> void:
	if _systems.has(key) == false:
		return
	var light := _systems[key]["light"] as TextureRect
	if on:
		light.self_modulate = Color(1, 0.4, 0.2)  # warm warning
	else:
		light.self_modulate = Color(0.3, 0.3, 0.3)

func clear_messages(key: String) -> void:
	if _systems.has(key) == false:
		return
	var vbox := _systems[key]["vbox"] as VBoxContainer
	for c in vbox.get_children():
		vbox.remove_child(c)
		c.queue_free()

func add_message(key: String, text: String, severity: String = "warn") -> void:
	if _systems.has(key) == false:
		return
	var vbox := _systems[key]["vbox"] as VBoxContainer
	var scroll := _systems[key]["scroll"] as ScrollContainer
	# Create a wrapped label line for the message
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.clip_text = false
	lbl.text = text
	# Severity tint (optional)
	var col := Color(1,1,1)
	if severity == "info":
		col = Color(0.85, 0.9, 1)
	elif severity == "warn":
		col = Color(1, 0.95, 0.85)
	elif severity == "error":
		col = Color(1, 0.85, 0.85)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	# Add the label as a line
	vbox.add_child(lbl)
	var line := lbl  # for scroll target
	# Trim if necessary
	var max_count := int(_systems[key]["max"])
	while vbox.get_child_count() > max_count:
		var first := vbox.get_child(0)
		vbox.remove_child(first)
		first.queue_free()
	# Scroll to bottom to reveal the latest message
	await get_tree().process_frame
	scroll.ensure_control_visible(line)

# Convenience: set a one-line status + log an entry
func set_status_and_log(key: String, status_text: String, severity: String = "warn") -> void:
	set_light(key, true)
	add_message(key, status_text, severity)

# --- Built-in wiring for heat+fuel; cooling is external ---
func hook_standard_events() -> void:
	# Be robust: only connect if the signal exists on GameState.
	if GameState.has_signal("venting_started"):
		GameState.venting_started.connect(func():
			set_light("heat", true)
			add_message("heat", "Venting heat…", "info")
		)
	else:
		push_warning("WarningsPanel: GameState missing signal 'venting_started' — HEAT light will only update on finish.")

	if GameState.has_signal("venting_finished"):
		GameState.venting_finished.connect(func():
			set_light("heat", false)
			add_message("heat", "Venting complete.", "info")
		)
	else:
		push_warning("WarningsPanel: GameState missing signal 'venting_finished'.")

	if GameState.has_signal("fuel_empty"):
		GameState.fuel_empty.connect(func():
			set_light("fuel", true)
			add_message("fuel", "Fuel depleted.", "error")
		)
	else:
		push_warning("WarningsPanel: GameState missing signal 'fuel_empty'.")

	if GameState.has_signal("fuel_changed"):
		GameState.fuel_changed.connect(func(_f: float):
			if GameState.fuel > 0.0:
				set_light("fuel", false)
		)
	else:
		push_warning("WarningsPanel: GameState missing signal 'fuel_changed'.")

# External API for cooling warnings (call from your cooling logic)
func set_cooling_warning(on: bool, text: String, severity: String = "warn") -> void:
	set_light("cooling", on)
	if text != "":
		add_message("cooling", text, severity)
