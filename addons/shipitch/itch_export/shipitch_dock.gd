@tool
extends Control
## Main dock panel for the itch.io export addon.
## Orchestrates API key management, game selection, export, and upload.

# --- Child node references (bound from itch_export_dock.tscn) ---
@onready var _setup_section_toggle: Button = $Scroll/DockMargin/MainVBox/SetupSectionToggle
@onready var _setup_section_body: VBoxContainer = $Scroll/DockMargin/MainVBox/SetupSectionBody

@onready var _api_key_edit: LineEdit = $Scroll/DockMargin/MainVBox/SetupSectionBody/ApiKeyHBox/ApiKeyEdit
@onready var _api_key_toggle: Button = $Scroll/DockMargin/MainVBox/SetupSectionBody/ApiKeyHBox/ApiKeyToggleBtn
@onready var _get_key_btn: Button = $Scroll/DockMargin/MainVBox/SetupSectionBody/ApiButtonsHBox/GetKeyBtn
@onready var _validate_btn: Button = $Scroll/DockMargin/MainVBox/SetupSectionBody/ApiButtonsHBox/ValidateBtn
@onready var _status_label: RichTextLabel = $Scroll/DockMargin/MainVBox/SetupSectionBody/StatusLabel

@onready var _games_dropdown: OptionButton = $Scroll/DockMargin/MainVBox/GameHBox/GamesDropdown
@onready var _refresh_games_btn: Button = $Scroll/DockMargin/MainVBox/GameHBox/RefreshGamesBtn
@onready var _create_game_btn: Button = $Scroll/DockMargin/MainVBox/CreateGameBtn

@onready var _preset_list: VBoxContainer = $Scroll/DockMargin/MainVBox/PresetHBox/PresetList
@onready var _refresh_presets_btn: Button = $Scroll/DockMargin/MainVBox/PresetHBox/RefreshPresetsBtn
@onready var _version_edit: LineEdit = $Scroll/DockMargin/MainVBox/VersionEdit

@onready var _export_push_btn: Button = $Scroll/DockMargin/MainVBox/ExportPushBtn

@onready var _view_github_btn: Button = $Scroll/DockMargin/MainVBox/HeaderTop/ViewGithubBtn
@onready var _output_log_checkbox: CheckBox = $Scroll/DockMargin/MainVBox/SetupSectionBody/OutputLogCheckbox

@onready var _butler_status_label: RichTextLabel = $Scroll/DockMargin/MainVBox/SetupSectionBody/ButlerStatusLabel
@onready var _install_butler_btn: Button = $Scroll/DockMargin/MainVBox/SetupSectionBody/InstallButlerBtn
@onready var _butler_progress_bar: ProgressBar = $Scroll/DockMargin/MainVBox/SetupSectionBody/ButlerProgressBar
@onready var _butler_progress_label: Label = $Scroll/DockMargin/MainVBox/SetupSectionBody/ButlerProgressLabel

# --- Internal state ---
@onready var _itch_api: ItchAPI = $ItchApi
@onready var _butler_manager: ButlerManager = $ButlerManager
@onready var _export_flow: ItchExportFlowController = $ExportFlowController
var _preset_rows: ItchExportPresetRows
var _api_key: String = ""
var _username: String = ""
var _games: Array = []
var _saved_game_token: String = ""
var _is_downloading_butler: bool = false
var _is_operation_loading: bool = false
var _is_setup_section_collapsed: bool = false
var _loading_icon_index: int = 0
var _loading_icon_elapsed: float = 0.0

const SETTINGS_KEY := "shipitch/api_key"
const SETTINGS_SELECTED_GAME_KEY := "shipitch/selected_game"
const SETTINGS_SELECTED_PRESETS_KEY := "shipitch/selected_presets"
const SETTINGS_OUTPUT_LOGS_KEY := "shipitch/output_logs"
const LOADING_ICON_INTERVAL := 0.12
const GITHUB_URL := "https://github.com/Lighar/ioj"
const LOADING_ICON_NAMES := [
	"Progress1",
	"Progress2",
	"Progress3",
	"Progress4",
	"Progress5",
	"Progress6",
	"Progress7",
	"Progress8",
]

enum LogLevel { INFO, WARNING, ERROR }
const ALERT_DIALOG_SCENE := preload("res://addons/shipitch/components/shipitch_alert_dialog.tscn")


func _ready() -> void:
	_connect_ui_signals()
	_apply_static_icons()
	_butler_progress_bar.show_percentage = false
	_setup_managers()
	_preset_rows = ItchExportPresetRows.new(_preset_list, _get_editor_icon, LOADING_ICON_NAMES)
	_preset_rows.selection_changed.connect(_save_selected_presets)
	_set_setup_section_collapsed(false)


## Called explicitly by the EditorPlugin to load user data.
## This prevents dynamic data like API keys from being serialized
## into the scene file if you open the dock in the Godot scene editor.
func initialize_dock() -> void:
	_load_api_key()
	_load_output_log_setting()
	if _api_key == "":
		_set_richtext(_status_label, "[color=#95a8c0]Paste your API key, then click [b]Validate & Save[/b] to start.[/color]")
	_load_saved_game_token()
	_auto_validate_saved_api_key()
	_refresh_presets()
	_butler_manager.find_butler()


func _process(_delta: float) -> void:
	if _is_operation_loading:
		_loading_icon_elapsed += _delta
		if _loading_icon_elapsed >= LOADING_ICON_INTERVAL:
			_loading_icon_elapsed = 0.0
			_loading_icon_index = (_loading_icon_index + 1) % LOADING_ICON_NAMES.size()
			_export_push_btn.icon = _get_editor_icon(LOADING_ICON_NAMES[_loading_icon_index])
			_preset_rows.update_loading_icons(_loading_icon_index)

	if _is_downloading_butler:
		var progress_data := _butler_manager.get_download_progress()
		if progress_data.is_empty():
			return
		var body_size: int = progress_data["body_size"]
		var downloaded: int = progress_data["downloaded"]
		if body_size > 0:
			var progress := float(downloaded) / float(body_size) * 100.0
			_butler_progress_bar.value = progress
			_butler_progress_label.text = "Downloading: %s / %s" % [ItchExportUtils.format_bytes(downloaded), ItchExportUtils.format_bytes(body_size)]


func _connect_ui_signals() -> void:
	_api_key_toggle.pressed.connect(_on_toggle_key_visibility)
	_get_key_btn.pressed.connect(func() -> void: OS.shell_open("https://itch.io/user/settings/api-keys"))
	_validate_btn.pressed.connect(_on_validate_pressed)
	_games_dropdown.item_selected.connect(_on_game_selected)
	_refresh_games_btn.pressed.connect(_on_refresh_games_pressed)
	_create_game_btn.pressed.connect(func() -> void: OS.shell_open("https://itch.io/game/new"))
	_refresh_presets_btn.pressed.connect(_refresh_presets)
	_export_push_btn.pressed.connect(_do_export)
	_install_butler_btn.pressed.connect(_on_install_butler_pressed)
	_view_github_btn.pressed.connect(func() -> void: OS.shell_open(GITHUB_URL))
	_output_log_checkbox.toggled.connect(func(enabled: bool) -> void: ItchExportSettings.save_bool(SETTINGS_OUTPUT_LOGS_KEY, enabled))
	_setup_section_toggle.pressed.connect(func() -> void: _set_setup_section_collapsed(not _is_setup_section_collapsed))


func _set_setup_section_collapsed(collapsed: bool) -> void:
	_is_setup_section_collapsed = collapsed
	_setup_section_body.visible = not collapsed
	_setup_section_toggle.button_pressed = not collapsed
	_setup_section_toggle.text = "Settings ▸" if collapsed else "Settings ▾"


func _apply_static_icons() -> void:
	var base_control := EditorInterface.get_base_control()
	if base_control == null:
		return
	_apply_button_icon(_refresh_games_btn, "RotateLeft", true)
	_apply_button_icon(_refresh_presets_btn, "RotateLeft", true)
	_apply_button_icon(_get_key_btn, "ExternalLink")
	_apply_button_icon(_validate_btn, "GuiChecked")
	_apply_button_icon(_create_game_btn, "Add")
	_apply_button_icon(_install_butler_btn, "Download")
	_apply_button_icon(_export_push_btn, "FileExport")
	_update_api_key_toggle_icon()


func _apply_button_icon(button: Button, icon_name: String, icon_only: bool = false) -> void:
	var icon := _get_editor_icon(icon_name)
	if icon == null:
		return
	button.icon = icon
	if icon_only:
		button.text = ""

# ==========================================================================
# MANAGERS SETUP
# ==========================================================================


func _setup_managers() -> void:
	_itch_api.key_validated.connect(_on_key_validated)
	_itch_api.games_fetched.connect(_on_games_fetched)
	_itch_api.request_failed.connect(
		func(error: String) -> void:
			_set_richtext(_status_label, "[color=red]%s[/color]" % error)
			_log("API Error: %s" % error, LogLevel.ERROR)
	)

	_butler_manager.butler_found.connect(
		func(path: String, version: String) -> void:
			_set_richtext(_butler_status_label, "[color=green]✓ Butler found: [b]%s[/b][/color]" % version)
			_install_butler_btn.visible = false
			_log("Butler found: %s (%s)" % [path, version])
	)
	_butler_manager.butler_not_found.connect(
		func() -> void:
			_set_richtext(_butler_status_label, "[color=red]✗ Butler not found[/color]")
			_install_butler_btn.visible = true
			_log("Butler not found on PATH or local install.", LogLevel.ERROR)
	)
	_butler_manager.butler_downloaded.connect(_on_butler_downloaded)
	_butler_manager.download_failed.connect(_on_butler_download_failed)
	_butler_manager.log_message.connect(func(msg: String, level: int) -> void: _log(msg, level as LogLevel))

	_export_flow.setup(_butler_manager)
	_export_flow.log_message.connect(func(msg: String, level: int) -> void: _log(msg, level as LogLevel))
	_export_flow.row_status_changed.connect(func(row_idx: int, status: String) -> void: _preset_rows.set_row_status(row_idx, status, _loading_icon_index))
	_export_flow.ui_lock_changed.connect(
		func(locked: bool) -> void:
			_export_push_btn.disabled = locked
			_preset_rows.set_rows_interactable(not locked)
	)
	_export_flow.action_text_changed.connect(func(text: String) -> void: _export_push_btn.text = text)
	_export_flow.action_icon_changed.connect(func(icon_name: String) -> void: _export_push_btn.icon = _get_editor_icon(icon_name))
	_export_flow.loading_state_changed.connect(_on_flow_loading_state_changed)
	_export_flow.flow_finished.connect(
		func(title: String, message: String) -> void:
			var lower_title := title.to_lower()
			var level := LogLevel.ERROR if "fail" in lower_title else LogLevel.INFO
			_log("%s: %s" % [title, message], level)
	)

# ==========================================================================
# API KEY
# ==========================================================================


func _load_api_key() -> void:
	_api_key = ItchExportSettings.load_string(SETTINGS_KEY)
	_api_key_edit.text = _api_key


func _auto_validate_saved_api_key() -> void:
	if _api_key == "":
		return
	_set_richtext(_status_label, "[color=yellow]Validating saved API key...[/color]")
	_itch_api.validate_key(_api_key)


func _save_api_key(key: String) -> void:
	_api_key = key
	ItchExportSettings.save_string(SETTINGS_KEY, key)


func _load_saved_game_token() -> void:
	_saved_game_token = ItchExportSettings.load_scoped_string(SETTINGS_SELECTED_GAME_KEY)


func _save_selected_game_token(token: String) -> void:
	_saved_game_token = token
	ItchExportSettings.save_scoped_string(SETTINGS_SELECTED_GAME_KEY, token)


func _load_output_log_setting() -> void:
	_output_log_checkbox.button_pressed = ItchExportSettings.load_bool(SETTINGS_OUTPUT_LOGS_KEY, true)


func _on_toggle_key_visibility() -> void:
	_api_key_edit.secret = !_api_key_edit.secret
	_update_api_key_toggle_icon()


func _on_validate_pressed() -> void:
	var key := _api_key_edit.text.strip_edges()
	if key == "":
		_set_richtext(_status_label, "[color=red]Please enter an API key first.[/color]")
		return
	_set_richtext(_status_label, "[color=yellow]Validating...[/color]")
	_itch_api.validate_key(key)


func _on_key_validated(username: String) -> void:
	_username = username
	var key := _api_key_edit.text.strip_edges()
	_save_api_key(key)
	_set_richtext(_status_label, "[color=green]✓ Authenticated as [b]%s[/b][/color]" % username)
	_log("API key validated. User: %s" % username)
	# Auto-fetch games
	_itch_api.fetch_games(_api_key)

# ==========================================================================
# GAMES
# ==========================================================================


func _on_refresh_games_pressed() -> void:
	if _api_key == "":
		_set_richtext(_status_label, "[color=red]Validate your API key first.[/color]")
		return
	_itch_api.fetch_games(_api_key)


func _on_games_fetched(games: Array) -> void:
	_games = games
	_games_dropdown.clear()

	if games.is_empty():
		_games_dropdown.add_item("No games found")
		_log("No games found on your account.", LogLevel.WARNING)
		return

	for game in games:
		var title: String = game.get("title", "Untitled")
		_games_dropdown.add_item(title)

	var restore_idx := -1
	for i in games.size():
		var game: Dictionary = games[i]
		if ItchExportUtils.get_game_token(game) == _saved_game_token:
			restore_idx = i
			break

	if restore_idx < 0:
		restore_idx = 0

	_games_dropdown.select(restore_idx)
	_on_game_selected(restore_idx)


func _on_game_selected(idx: int) -> void:
	if idx >= 0 and idx < _games.size():
		var game: Dictionary = _games[idx]
		_save_selected_game_token(ItchExportUtils.get_game_token(game))
		_log("Selected: %s (%s)" % [game.get("title", ""), game.get("url", "")])

# ==========================================================================
# EXPORT PRESETS
# ==========================================================================


func _refresh_presets() -> void:
	var presets := ExportHelper.get_export_presets()
	_preset_rows.clear_rows()

	if presets.is_empty():
		_log("No export presets found. Configure them in Project > Export.", LogLevel.WARNING)
		return

	var saved_tokens := _load_saved_preset_tokens()
	var has_saved_tokens := not saved_tokens.is_empty()
	for i in presets.size():
		var preset: ExportHelper.PresetInfo = presets[i]
		var is_checked := saved_tokens.has(_get_preset_token(preset)) if has_saved_tokens else i == 0
		_preset_rows.add_preset_row(preset, is_checked)

	_save_selected_presets()

# ==========================================================================
# BUTLER
# ==========================================================================


func _on_install_butler_pressed() -> void:
	_install_butler_btn.disabled = true
	_install_butler_btn.text = "Downloading..."
	_butler_progress_bar.value = 0
	_butler_progress_bar.visible = true
	_butler_progress_label.text = "Starting download..."
	_butler_progress_label.visible = true
	_is_downloading_butler = true
	_butler_manager.download_butler()


func _on_butler_downloaded(_path: String) -> void:
	_is_downloading_butler = false
	_install_butler_btn.visible = false
	_butler_progress_bar.value = 100
	_butler_progress_label.text = "Done!"
	# Hide progress after a short delay
	get_tree().create_timer(1.5).timeout.connect(
		func():
			_butler_progress_bar.visible = false
			_butler_progress_label.visible = false
	)
	_butler_manager.find_butler()


func _on_butler_download_failed(error: String) -> void:
	_is_downloading_butler = false
	_install_butler_btn.disabled = false
	_install_butler_btn.text = "Download Butler"
	_butler_progress_bar.visible = false
	_butler_progress_label.visible = false
	_log("Butler download failed: %s" % error, LogLevel.ERROR)

# ==========================================================================
# EXPORT & PUSH
# ==========================================================================


func _do_export() -> void:
	if _export_flow.is_running():
		_show_alert("Please Wait", "An operation is already in progress.")
		return

	# Validate settings with visible popup feedback
	if _api_key == "":
		_show_alert("API Key Required", "Please enter and validate your itch.io API key first.\n\nClick 'Get API Key' to open itch.io, then paste your key and click 'Validate & Save'.")
		return
	if _games.is_empty() or _games_dropdown.selected < 0:
		_show_alert("No Game Selected", "Please select an itch.io game project first.\n\nIf you don't have one yet, click 'Create New on itch.io', then refresh the list.")
		return
	if _butler_manager.get_butler_path() == "":
		_show_alert("Butler Not Found", "Butler CLI is required to upload to itch.io.\n\nClick 'Download Butler' at the bottom of this panel to install it automatically.")
		return

	var selected_rows := _preset_rows.get_selected_row_indices()
	if selected_rows.is_empty():
		_show_alert("No Export Preset", "Select one or more export presets first.")
		return

	var version := _version_edit.text.strip_edges()

	var export_jobs: Array = []
	for row_idx in selected_rows:
		var row: Dictionary = _preset_rows.get_row(row_idx)
		if row.is_empty():
			continue
		var preset: ExportHelper.PresetInfo = row["preset"]
		var output_path := ExportHelper.get_default_output_path(preset)
		export_jobs.append(
			{
				"row_idx": row_idx,
				"preset": preset,
				"output_path": output_path,
				"channel": ExportHelper.guess_channel(preset.platform),
				"version": version,
			},
		)

	if export_jobs.is_empty():
		_show_alert("Preset Data Error", "Selected presets could not be resolved. Refresh export presets and try again.")
		_log("Selected preset rows were missing data. Refresh presets and try again.", LogLevel.ERROR)
		return

	_export_flow.start_export_batch(
		export_jobs,
		true,
		_api_key,
		_games,
		_games_dropdown.selected,
	)

# ==========================================================================
# HELPERS
# ==========================================================================


func _set_richtext(label: RichTextLabel, bbcode_text: String) -> void:
	label.clear()
	label.append_text(bbcode_text)


func _log(text: String, level: LogLevel = LogLevel.INFO) -> void:
	if not _output_log_checkbox.button_pressed:
		return
	var time_str := Time.get_time_string_from_system()
	var message := "[shipitch][%s] %s" % [time_str, text]
	match level:
		LogLevel.ERROR:
			push_error(message)
		LogLevel.WARNING:
			push_warning(message)
		_:
			print(message)


func _show_alert(title: String, message: String) -> void:
	var base_control := EditorInterface.get_base_control()
	if base_control == null:
		return
	var dialog := ALERT_DIALOG_SCENE.instantiate() as ItchExportAlertDialog
	if dialog == null:
		return
	dialog.show_in_parent(base_control, title, message)


func _start_loading_icon() -> void:
	_is_operation_loading = true
	_loading_icon_elapsed = 0.0
	_loading_icon_index = 0
	_export_push_btn.icon = _get_editor_icon(LOADING_ICON_NAMES[_loading_icon_index])


func _stop_loading_icon() -> void:
	_is_operation_loading = false
	_loading_icon_elapsed = 0.0


func _get_editor_icon(icon_name: String) -> Texture2D:
	var base_control := EditorInterface.get_base_control()
	if base_control == null:
		return null
	if not base_control.has_theme_icon(icon_name, "EditorIcons"):
		return null
	return base_control.get_theme_icon(icon_name, "EditorIcons")


func _on_flow_loading_state_changed(active: bool) -> void:
	if active:
		_start_loading_icon()
	else:
		_stop_loading_icon()


func _load_saved_preset_tokens() -> PackedStringArray:
	return ItchExportSettings.load_string_array(SETTINGS_SELECTED_PRESETS_KEY)


func _save_selected_presets() -> void:
	var selected_tokens := PackedStringArray()
	for row_idx in _preset_rows.get_selected_row_indices():
		var row: Dictionary = _preset_rows.get_row(row_idx)
		if row.is_empty():
			continue
		var preset: ExportHelper.PresetInfo = row["preset"]
		selected_tokens.append(_get_preset_token(preset))
	ItchExportSettings.save_string_array(SETTINGS_SELECTED_PRESETS_KEY, selected_tokens)


func _get_preset_token(preset: ExportHelper.PresetInfo) -> String:
	return "%s|%s" % [preset.name, preset.platform]


func _update_api_key_toggle_icon() -> void:
	var icon_name := "GuiVisibilityHidden" if _api_key_edit.secret else "GuiVisibilityVisible"
	var icon := _get_editor_icon(icon_name)
	if icon != null:
		_api_key_toggle.icon = icon
		_api_key_toggle.text = ""
