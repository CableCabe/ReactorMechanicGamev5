# scripts/Main.gd
extends Control

func _ready() -> void:
	GameState.load_game()
	GameState.init_pillars()
