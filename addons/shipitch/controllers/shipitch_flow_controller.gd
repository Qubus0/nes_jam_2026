@tool
class_name ItchExportFlowController
extends Node
## Handles batch export + optional push workflow.
## Emits UI-facing signals so the dock script can stay focused on orchestration.

signal log_message(msg: String, log_level: int)
signal row_status_changed(row_idx: int, status: String)
signal ui_lock_changed(locked: bool)
signal action_text_changed(text: String)
signal action_icon_changed(icon_name: String)
signal loading_state_changed(active: bool)
signal flow_finished(alert_title: String, alert_message: String)

var _butler_manager: ButlerManager

var _api_key: String = ""
var _games: Array = []
var _selected_game_idx: int = -1

var _is_running: bool = false
var _pending_export_count: int = 0
var _failed_export_count: int = 0
var _successful_export_count: int = 0
var _successful_exports: Array = [] # [{row_idx, preset, output_path, channel, version}]
var _active_threads: Array = []
var _pending_push_queue: Array = []
var _current_push_item: Dictionary = { }
var _push_success_count: int = 0
var _push_fail_count: int = 0


func _exit_tree() -> void:
	if _butler_manager and _butler_manager.push_completed.is_connected(_on_push_completed):
		_butler_manager.push_completed.disconnect(_on_push_completed)


func setup(butler_manager: ButlerManager) -> void:
	if _butler_manager and _butler_manager.push_completed.is_connected(_on_push_completed):
		_butler_manager.push_completed.disconnect(_on_push_completed)

	_butler_manager = butler_manager
	if _butler_manager and not _butler_manager.push_completed.is_connected(_on_push_completed):
		_butler_manager.push_completed.connect(_on_push_completed)


func is_running() -> bool:
	return _is_running


func start_export_batch(export_jobs: Array, push_after: bool, api_key: String, games: Array, selected_game_idx: int) -> void:
	if _is_running:
		return

	if export_jobs.is_empty():
		flow_finished.emit("No Export Preset", "Select one or more export presets first.")
		return

	_api_key = api_key
	_games = games
	_selected_game_idx = selected_game_idx
	_is_running = true
	_pending_export_count = export_jobs.size()
	_failed_export_count = 0
	_successful_export_count = 0
	_successful_exports.clear()
	_pending_push_queue.clear()
	_current_push_item = { }
	_push_success_count = 0
	_push_fail_count = 0

	ui_lock_changed.emit(true)
	action_text_changed.emit("⏳ Exporting...")
	loading_state_changed.emit(true)
	log_message.emit("--- Starting batch export (%d preset(s)) ---" % export_jobs.size(), 0)

	for export_job in export_jobs:
		_start_single_export(export_job, push_after)


func _start_single_export(export_job: Dictionary, push_after: bool) -> void:
	var row_idx := int(export_job.get("row_idx", -1))
	var preset: ExportHelper.PresetInfo = export_job.get("preset")
	var output_path: String = str(export_job.get("output_path", ""))
	var channel: String = str(export_job.get("channel", ""))
	var version: String = str(export_job.get("version", ""))

	row_status_changed.emit(row_idx, "loading")
	log_message.emit("Preset: %s -> %s" % [preset.name, output_path], 0)

	var thread := Thread.new()
	var err := thread.start(_export_thread_func.bind(row_idx, preset, output_path, push_after, channel, version, thread))
	if err != OK:
		log_message.emit("Failed to start export thread for %s (error %d)." % [preset.name, err], 2)
		row_status_changed.emit(row_idx, "error")
		_failed_export_count += 1
		_pending_export_count -= 1
		_finalize_exports_if_done(push_after)
		return

	_active_threads.append(thread)


func _export_thread_func(row_idx: int, preset: ExportHelper.PresetInfo, output_path: String, push_after: bool, channel: String, version: String, thread: Thread) -> void:
	var result := ExportHelper.run_export(preset.name, output_path)
	call_deferred("_on_single_export_done", row_idx, preset, result, output_path, push_after, channel, version, thread)


func _on_single_export_done(row_idx: int, preset: ExportHelper.PresetInfo, result: Dictionary, output_path: String, push_after: bool, channel: String, version: String, thread: Thread) -> void:
	thread.wait_to_finish()
	_active_threads.erase(thread)

	var exit_code := int(result.get("exit_code", -1))
	var output_text := str(result.get("output", ""))
	if exit_code != 0:
		row_status_changed.emit(row_idx, "error")
		_failed_export_count += 1
		log_message.emit("Export failed: %s (exit code %d)." % [preset.name, exit_code], 2)
		if output_text != "":
			log_message.emit(output_text, 2)
	else:
		row_status_changed.emit(row_idx, "success")
		_successful_export_count += 1
		log_message.emit("✓ Export completed: %s" % preset.name, 0)
		_successful_exports.append(
			{
				"row_idx": row_idx,
				"preset": preset,
				"output_path": output_path,
				"channel": channel,
				"version": version,
			},
		)
		if output_text.strip_edges() != "":
			log_message.emit(output_text, 0)

	_pending_export_count -= 1
	_finalize_exports_if_done(push_after)


func _finalize_exports_if_done(push_after: bool) -> void:
	if _pending_export_count > 0:
		return

	if _failed_export_count > 0:
		action_icon_changed.emit("StatusError")
	else:
		action_icon_changed.emit("StatusSuccess")

	if not push_after:
		_finish_flow(
			"Export Finished",
			"Exported %d preset(s), failed %d." % [_successful_export_count, _failed_export_count],
		)
		return

	if _successful_exports.is_empty():
		_finish_flow("Export Failed", "All exports failed. Nothing to upload.")
		return

	action_text_changed.emit("⏳ Pushing to itch.io...")
	_pending_push_queue = _successful_exports.duplicate()
	log_message.emit("--- Starting batch butler push ---", 0)
	_start_next_push()


func _start_next_push() -> void:
	if _pending_push_queue.is_empty():
		if _push_fail_count > 0:
			action_icon_changed.emit("StatusError")
		else:
			action_icon_changed.emit("StatusSuccess")
		_finish_flow(
			"Upload Finished",
			"Pushed %d preset(s), failed %d." % [_push_success_count, _push_fail_count],
		)
		return

	_current_push_item = _pending_push_queue.pop_front()
	var row_idx := int(_current_push_item.get("row_idx", -1))
	var output_path: String = str(_current_push_item.get("output_path", ""))
	var channel: String = str(_current_push_item.get("channel", ""))
	var version: String = str(_current_push_item.get("version", ""))
	var push_dir := output_path.get_base_dir()
	_current_push_item["push_dir"] = push_dir
	row_status_changed.emit(row_idx, "loading")

	if _selected_game_idx < 0 or _selected_game_idx >= _games.size():
		_push_fail_count += 1
		row_status_changed.emit(row_idx, "error")
		log_message.emit("No valid game selected for push.", 2)
		_current_push_item = { }
		_start_next_push()
		return

	if _butler_manager == null:
		_push_fail_count += 1
		row_status_changed.emit(row_idx, "error")
		log_message.emit("Butler manager is not available.", 2)
		_current_push_item = { }
		_start_next_push()
		return

	var preset: ExportHelper.PresetInfo = _current_push_item.get("preset")
	var game: Dictionary = _games[_selected_game_idx]
	var target := ItchExportUtils.get_butler_target(game)
	if target == "":
		_push_fail_count += 1
		row_status_changed.emit(row_idx, "error")
		log_message.emit("Push failed: selected game has no valid itch.io URL.", 2)
		_current_push_item = { }
		_start_next_push()
		return

	log_message.emit("Pushing %s -> %s:%s" % [preset.name, target, channel], 0)
	_butler_manager.push_build(push_dir, target, channel, _api_key, version)


func _on_push_completed(success: bool, output: String) -> void:
	if not _is_running or _current_push_item.is_empty():
		return

	var row_idx := int(_current_push_item.get("row_idx", -1))
	var cleanup_dir: String = str(_current_push_item.get("push_dir", ""))
	var preset: ExportHelper.PresetInfo = _current_push_item.get("preset")
	var preset_name := preset.name

	if success:
		_push_success_count += 1
		row_status_changed.emit(row_idx, "success")
		log_message.emit("✓ Push succeeded: %s" % preset_name, 0)
		if output.strip_edges() != "":
			log_message.emit(output, 0)
		if cleanup_dir != "":
			if ItchExportUtils.remove_path_recursive(cleanup_dir):
				log_message.emit("Local build removed: %s" % cleanup_dir, 0)
			else:
				log_message.emit("Upload succeeded, but local build cleanup failed: %s" % cleanup_dir, 1)
	else:
		_push_fail_count += 1
		row_status_changed.emit(row_idx, "error")
		log_message.emit("✗ Push failed: %s" % preset_name, 2)
		log_message.emit(_format_push_error(output), 2)

	_current_push_item = { }
	_start_next_push()


func _finish_flow(alert_title: String, alert_message: String) -> void:
	_is_running = false
	loading_state_changed.emit(false)
	ui_lock_changed.emit(false)
	action_text_changed.emit("🚀  Export & Push to itch.io")
	flow_finished.emit(alert_title, alert_message)


func _format_push_error(output: String) -> String:
	var cleaned := output.strip_edges()
	if cleaned.find("HTTP 403") != -1:
		return "%s\n\nHint: itch.io denied this upload request (HTTP 403). Your key may validate and list games but still lack publish access. Create a fresh API key on itch.io with full upload/publish permissions, validate it again in this dock, then retry." % cleaned
	return cleaned
