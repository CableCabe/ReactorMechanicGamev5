extends Button

func _ready() -> void:
	if GameState.has_signal("venting_started"):
		GameState.connect("venting_started", _lock)
	if GameState.has_signal("venting_finished"):
		GameState.connect("venting_finished", _unlock)
	if GameState.has_signal("venting_ended"): # temporary alias
		GameState.connect("venting_ended", _unlock)
	_sync_from_state()

func _pressed() -> void:
	if GameState.is_venting: return
	if not GameState.manual_ignite_enabled: return
	get_tree().call_group("reaction_pillars", "manual_ignite")

func _lock() -> void: disabled = true
func _unlock() -> void: _sync_from_state()
func _sync_from_state() -> void:
	disabled = GameState.is_venting or (not GameState.manual_ignite_enabled)
