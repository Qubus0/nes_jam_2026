extends PanelContainer




func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://game/game.tscn")


func _on_settings_pressed() -> void:
	PauseSettings.toggle_menu()
