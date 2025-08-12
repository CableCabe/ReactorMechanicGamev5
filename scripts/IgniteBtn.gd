extends Button

@onready var GS = get_node("/root/GameState")

func _ready() -> void:
	if GS.has_signal("venting_started"):
		GS.connect("venting_started", _lock)
	if GS.has_signal("venting_finished"):
		GS.connect("venting_finished", _unlock)
	if GS.has_signal("venting_ended"): # temporary alias
		GS.connect("venting_ended", _unlock)
	_sync_from_state()

func _pressed() -> void:
	if GS.is_venting: return
	if not GS.manual_ignite_enabled: return
	get_tree().call_group("reaction_pillars", "manual_ignite")

func _lock() -> void: disabled = true
func _unlock() -> void: _sync_from_state()
func _sync_from_state() -> void:
	disabled = GS.is_venting or (not GS.manual_ignite_enabled)
