extends Control

@onready var grid: GridContainer = $VBoxContainer/PillarGrid
@onready var click_btn: Button = $VBoxContainer/ClickButton
@onready var temp_bar: ProgressBar = $VBoxContainer/HBoxContainer/TempBar

var PillarScene := preload("res://scenes/ReactionPillar.tscn")

func _ready() -> void:
	GameState.init_pillars()
	click_btn.pressed.connect(GameState.do_click)
	GameState.state_changed.connect(_refresh)
	_spawn_pillars()
	_refresh()

func _spawn_pillars() -> void:
	for i in range(GameState.pillars.size()):
		var p: ReactionPillar = PillarScene.instantiate()
		p.idx = i
		grid.add_child(p)

func _refresh() -> void:
	temp_bar.max_value = GameState.OVERHEAT  # optional: line up with your threshold
	temp_bar.value = GameState.temp
