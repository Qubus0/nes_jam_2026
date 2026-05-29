extends CanvasLayer


@export var volume_master: HSlider
@export var volume_music: HSlider
@export var volume_sounds: HSlider


func _ready() -> void:
	hide()
	volume_master.value_changed.connect(_set_volume.bind(&"Master"))
	volume_music.value_changed.connect(_set_volume.bind(&"Music"))
	volume_sounds.value_changed.connect(_set_volume.bind(&"Sounds"))
	volume_master.value_changed.emit(volume_master.value)
	volume_music.value_changed.emit(volume_music.value)
	volume_sounds.value_changed.emit(volume_sounds.value)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key: return
	if key.is_action_pressed(&"start"):
		toggle_menu()


func toggle_menu() -> void:
	visible = not visible
	get_tree().paused = not get_tree().paused
	if visible:
		volume_master.grab_focus()


func _set_volume(value: int, name := &"Master") -> void:
	var bus := AudioServer.get_bus_index(name)
	AudioServer.set_bus_mute(bus, value <= 0)
	AudioServer.set_bus_volume_linear(bus, value)
