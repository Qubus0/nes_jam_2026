@tool
class_name ItchExportPresetRows
extends RefCounted
## Manages dynamic preset-row widgets in the dock preset section.

signal selection_changed

const PRESET_ROW_SCENE := preload("res://addons/shipitch/components/shipitch_preset_row.tscn")

var _preset_list: VBoxContainer
var _rows: Array = [] # [{preset, row, status}]
var _loading_icon_names: Array = []
var _icon_getter: Callable


func _init(preset_list: VBoxContainer, icon_getter: Callable, loading_icon_names: Array) -> void:
	_preset_list = preset_list
	_icon_getter = icon_getter
	_loading_icon_names = loading_icon_names.duplicate()


func clear_rows() -> void:
	for child in _preset_list.get_children():
		child.queue_free()
	_rows.clear()


func add_preset_row(preset: ExportHelper.PresetInfo, checked: bool) -> void:
	var row := PRESET_ROW_SCENE.instantiate() as ItchExportPresetRow
	if row == null:
		return
	_preset_list.add_child(row)
	row.configure(preset, checked)
	row.selection_changed.connect(_on_row_selection_changed)
	_rows.append(
		{
			"preset": preset,
			"row": row,
			"status": "idle",
		},
	)
	set_row_status(_rows.size() - 1, "idle", 0)


func get_selected_row_indices() -> Array:
	var selected: Array = []
	for i in _rows.size():
		var row_data: Dictionary = _rows[i]
		var row: ItchExportPresetRow = row_data["row"]
		if row.is_selected():
			selected.append(i)
	return selected


func get_row(row_idx: int) -> Dictionary:
	if row_idx < 0 or row_idx >= _rows.size():
		return { }
	return _rows[row_idx]


func set_row_status(row_idx: int, status: String, loading_icon_index: int) -> void:
	if row_idx < 0 or row_idx >= _rows.size():
		return

	var row_data: Dictionary = _rows[row_idx]
	row_data["status"] = status

	var row: ItchExportPresetRow = row_data["row"]
	match status:
		"idle":
			row.set_status_texture(null)
		"loading":
			row.set_status_texture(_get_loading_icon(loading_icon_index))
		"success":
			row.set_status_texture(_get_icon("StatusSuccess"))
		"error":
			row.set_status_texture(_get_icon("StatusError"))
		_:
			row.set_status_texture(null)


func update_loading_icons(loading_icon_index: int) -> void:
	var loading_icon := _get_loading_icon(loading_icon_index)
	for row_data in _rows:
		if row_data.get("status", "") != "loading":
			continue
		var row: ItchExportPresetRow = row_data["row"]
		row.set_status_texture(loading_icon)


func set_rows_interactable(enabled: bool) -> void:
	for row_data in _rows:
		var row: ItchExportPresetRow = row_data["row"]
		row.set_interactable(enabled)


func _get_loading_icon(loading_icon_index: int) -> Texture2D:
	if _loading_icon_names.is_empty():
		return null
	var icon_name: String = str(_loading_icon_names[loading_icon_index % _loading_icon_names.size()])
	return _get_icon(icon_name)


func _get_icon(icon_name: String) -> Texture2D:
	if not _icon_getter.is_valid():
		return null
	var icon = _icon_getter.call(icon_name)
	if icon is Texture2D:
		return icon
	return null


func _on_row_selection_changed() -> void:
	selection_changed.emit()
