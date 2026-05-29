@tool
class_name ItchExportPresetRow
extends PanelContainer

signal selection_changed

@export var panel_normal: StyleBox
@export var panel_selected: StyleBox

@onready var _preset_checkbox: CheckBox = $RowHBox/PresetCheckbox
@onready var _status_icon: TextureRect = $RowHBox/StatusIcon


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_icon.custom_minimum_size = Vector2(18, 18)
	_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_preset_checkbox.toggled.connect(_on_checkbox_toggled)
	_refresh_visual_state()


func configure(preset: ExportHelper.PresetInfo, checked: bool) -> void:
	_preset_checkbox.button_pressed = checked
	_preset_checkbox.text = "%s (%s)" % [preset.name, preset.platform]
	_refresh_visual_state()


func is_selected() -> bool:
	return _preset_checkbox.button_pressed


func set_interactable(enabled: bool) -> void:
	_preset_checkbox.disabled = not enabled
	modulate = Color(1, 1, 1, 1) if enabled else Color(0.75, 0.75, 0.75, 1)


func set_status_texture(texture: Texture2D) -> void:
	_status_icon.texture = texture


func _on_checkbox_toggled(_pressed: bool) -> void:
	_refresh_visual_state()
	selection_changed.emit()


func _refresh_visual_state() -> void:
	if panel_normal == null or panel_selected == null:
		return
	add_theme_stylebox_override("panel", panel_selected if _preset_checkbox.button_pressed else panel_normal)
