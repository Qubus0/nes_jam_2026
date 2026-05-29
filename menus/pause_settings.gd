extends CanvasLayer


@export var volume_master: HSlider
@export var volume_music: HSlider
@export var volume_sounds: HSlider
@export var fullscreen_toggle: CheckBox


func _ready() -> void:
	hide()
	volume_master.value_changed.connect(_on_volume_slider_changed.bind(&"Master"))
	volume_music.value_changed.connect(_on_volume_slider_changed.bind(&"Music"))
	volume_sounds.value_changed.connect(_on_volume_slider_changed.bind(&"Sounds"))
	volume_master.value_changed.emit(volume_master.value)
	volume_music.value_changed.emit(volume_music.value)
	volume_sounds.value_changed.emit(volume_sounds.value)

	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)


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


func _on_fullscreen_toggled(toggled_on: bool) -> void:
	if toggled_on:
		get_window().mode = Window.MODE_FULLSCREEN
	else:
		get_window().mode = Window.MODE_WINDOWED


func _on_volume_slider_changed(value: int, bus_name := &"Master") -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(bus, value <= 0)
	AudioServer.set_bus_volume_linear(bus, value)
