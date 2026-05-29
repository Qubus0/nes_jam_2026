@tool
class_name ItchExportSettings
extends RefCounted
## EditorSettings-backed persistence for dock-specific addon values.

static func _settings() -> EditorSettings:
	return EditorInterface.get_editor_settings()


static func load_string(settings_key: String) -> String:
	var settings := _settings()
	if settings and settings.has_setting(settings_key):
		return str(settings.get_setting(settings_key))
	return ""


static func save_string(settings_key: String, key: String) -> void:
	var settings := _settings()
	if settings:
		settings.set_setting(settings_key, key)


static func load_scoped_string(base_key: String) -> String:
	var settings := _settings()
	var scoped_key := ItchExportUtils.get_project_scoped_setting_key(base_key)
	if settings and settings.has_setting(scoped_key):
		return str(settings.get_setting(scoped_key))
	return ""


static func save_scoped_string(base_key: String, value: String) -> void:
	var settings := _settings()
	if settings:
		var scoped_key := ItchExportUtils.get_project_scoped_setting_key(base_key)
		settings.set_setting(scoped_key, value)


static func load_string_array(base_key: String) -> PackedStringArray:
	var settings := _settings()
	var scoped_key := ItchExportUtils.get_project_scoped_setting_key(base_key)
	if settings and settings.has_setting(scoped_key):
		var raw_value = settings.get_setting(scoped_key)
		var out := PackedStringArray()
		if raw_value is PackedStringArray:
			out = raw_value
		elif raw_value is Array:
			for item in raw_value:
				out.append(str(item))
		return out
	return PackedStringArray()


static func save_string_array(base_key: String, values: PackedStringArray) -> void:
	var settings := _settings()
	if settings:
		var scoped_key := ItchExportUtils.get_project_scoped_setting_key(base_key)
		settings.set_setting(scoped_key, values)


static func load_bool(base_key: String, default_value: bool = false) -> bool:
	var settings := _settings()
	var scoped_key := ItchExportUtils.get_project_scoped_setting_key(base_key)
	if settings and settings.has_setting(scoped_key):
		return bool(settings.get_setting(scoped_key))
	return default_value


static func save_bool(base_key: String, value: bool) -> void:
	var settings := _settings()
	if settings:
		var scoped_key := ItchExportUtils.get_project_scoped_setting_key(base_key)
		settings.set_setting(scoped_key, value)
