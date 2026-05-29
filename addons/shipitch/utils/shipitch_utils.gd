@tool
class_name ItchExportUtils
extends RefCounted

static func get_project_scoped_setting_key(base_key: String) -> String:
	var project_id := ProjectSettings.globalize_path("res://").md5_text()
	return "%s/%s" % [base_key, project_id]


static func get_game_token(game: Dictionary) -> String:
	if game.has("id"):
		return "id:%s" % str(game["id"])
	var url: String = game.get("url", "")
	if url != "":
		return "url:%s" % url
	return "title:%s" % str(game.get("title", ""))


static func get_butler_target(game: Dictionary) -> String:
	var url: String = game.get("url", "")
	if url != "":
		url = url.replace("https://", "").replace("http://", "")
		var parts := url.split("/")
		if parts.size() >= 2:
			var domain_parts := parts[0].split(".")
			if domain_parts.size() >= 1:
				var extracted_username := domain_parts[0]
				var slug := parts[1]
				return "%s/%s" % [extracted_username, slug]

	return ""


static func globalize_if_needed(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


static func remove_path_recursive(path: String) -> bool:
	if path == "":
		return false

	var absolute_path := globalize_if_needed(path)

	if FileAccess.file_exists(absolute_path):
		return DirAccess.remove_absolute(absolute_path) == OK

	if not DirAccess.dir_exists_absolute(absolute_path):
		return true

	var dir := DirAccess.open(absolute_path)
	if dir == null:
		return false

	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name == "." or name == "..":
			continue
		var child_path := absolute_path.path_join(name)
		if dir.current_is_dir():
			if not remove_path_recursive(child_path):
				dir.list_dir_end()
				return false
		else:
			if DirAccess.remove_absolute(child_path) != OK:
				dir.list_dir_end()
				return false
	dir.list_dir_end()

	return DirAccess.remove_absolute(absolute_path) == OK


static func format_bytes(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	else:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
