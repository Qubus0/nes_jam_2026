@tool
class_name ExportHelper
extends RefCounted
## Helpers for reading Godot export presets and triggering CLI exports.

## Represents a single export preset.
class PresetInfo:
	var name: String
	var platform: String
	var export_path: String
	var index: int


	func _to_string() -> String:
		return "%s (%s)" % [name, platform]


## Parse export_presets.cfg and return an array of PresetInfo.
static func get_export_presets() -> Array[PresetInfo]:
	var presets: Array[PresetInfo] = []
	var cfg_path := "res://export_presets.cfg"

	if not FileAccess.file_exists(cfg_path):
		return presets

	# Parse using ConfigFile
	var config := ConfigFile.new()
	var err := config.load(cfg_path)
	if err != OK:
		return presets

	# Export presets are stored as sections like [preset.0], [preset.1], etc.
	var idx := 0
	while true:
		var section := "preset.%d" % idx
		if not config.has_section(section):
			break

		var preset := PresetInfo.new()
		preset.index = idx
		preset.name = config.get_value(section, "name", "Unnamed Preset %d" % idx)
		preset.platform = config.get_value(section, "platform", "Unknown")
		preset.export_path = config.get_value(section, "export_path", "")
		presets.append(preset)
		idx += 1

	return presets


## Guess the itch.io channel name from a Godot export preset platform string.
static func guess_channel(platform: String) -> String:
	var p := platform.to_lower()
	if "windows" in p:
		return "windows"
	elif "linux" in p:
		return "linux"
	elif "mac" in p or "osx" in p or "macos" in p:
		return "mac"
	elif "web" in p or "html" in p:
		return "html5"
	elif "android" in p:
		return "android"
	elif "ios" in p:
		return "ios"
	return p.replace(" ", "-").to_lower()


## Run the Godot export via CLI.
## Returns [exit_code: int, output: String].
static func run_export(preset_name: String, output_path: String) -> Dictionary:
	# Find the Godot binary
	var godot_path := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")

	# Ensure the output directory exists
	var output_dir := output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)

	var args: PackedStringArray = [
		"--headless",
		"--path",
		project_path,
		"--export-release",
		preset_name,
		output_path,
	]

	var output: Array = []
	var exit_code := OS.execute(godot_path, args, output, true)
	var output_text := ""
	if output.size() > 0:
		output_text = output[0]

	return { "exit_code": exit_code, "output": output_text }


## Build a sensible default output path for a given preset.
static func get_default_output_path(preset: PresetInfo) -> String:
	var project_name := ProjectSettings.get_setting("application/config/name", "game")
	var base_dir := ProjectSettings.globalize_path("res://").path_join("builds")
	var channel := guess_channel(preset.platform)

	match channel:
		"windows":
			return base_dir.path_join(channel).path_join("%s.exe" % project_name)
		"linux":
			return base_dir.path_join(channel).path_join("%s.x86_64" % project_name)
		"mac":
			return base_dir.path_join(channel).path_join("%s.zip" % project_name)
		"html5":
			return base_dir.path_join(channel).path_join("index.html")
		"android":
			return base_dir.path_join(channel).path_join("%s.apk" % project_name)
		_:
			return base_dir.path_join(channel).path_join(project_name)
