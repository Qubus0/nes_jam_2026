@tool
class_name ButlerManager
extends Node
## Manages the Butler CLI: detection, download, and push operations.

signal butler_found(path: String, version: String)
signal butler_not_found()
signal butler_downloaded(path: String)
signal download_failed(error: String)
signal push_completed(success: bool, output: String)
signal log_message(msg: String, log_level: int)

const BUTLER_DOWNLOAD_URLS := {
	"linux": "https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default",
	"windows": "https://broth.itch.zone/butler/windows-amd64/LATEST/archive/default",
	"macos": "https://broth.itch.zone/butler/darwin-amd64/LATEST/archive/default",
}

var _butler_path: String = ""
var _http_download: HTTPRequest


func _ready() -> void:
	_http_download = HTTPRequest.new()
	_http_download.max_redirects = 12
	add_child(_http_download)


## Return the cached butler path, or empty string if not found yet.
func get_butler_path() -> String:
	return _butler_path


## Return current download progress as {body_size, downloaded}, or empty if no active download.
func get_download_progress() -> Dictionary:
	if _http_download == null:
		return { }
	var body_size := _http_download.get_body_size()
	var downloaded := _http_download.get_downloaded_bytes()
	return { "body_size": body_size, "downloaded": downloaded }


## Try to locate butler on the system.
func find_butler() -> void:
	# Check if user has a custom path stored
	var custom_path := _get_local_butler_path()
	if FileAccess.file_exists(custom_path):
		_butler_path = custom_path
		var version := _get_butler_version(_butler_path)
		butler_found.emit(_butler_path, version)
		return

	# Check PATH
	var output: Array = []
	var exit_code: int
	if OS.get_name() == "Windows":
		exit_code = OS.execute("where", ["butler"], output, true)
	else:
		exit_code = OS.execute("which", ["butler"], output, true)

	if exit_code == 0 and output.size() > 0:
		_butler_path = output[0].strip_edges()
		if _butler_path != "":
			var version := _get_butler_version(_butler_path)
			butler_found.emit(_butler_path, version)
			return

	butler_not_found.emit()


var _download_zip_path: String = ""
var _download_dir: String = ""
var _redirect_count: int = 0
const MAX_REDIRECTS := 10


## Download butler to a local addon directory.
func download_butler() -> void:
	var os_name := OS.get_name().to_lower()
	var key := ""
	if "linux" in os_name:
		key = "linux"
	elif "windows" in os_name:
		key = "windows"
	elif "mac" in os_name or "osx" in os_name:
		key = "macos"
	else:
		download_failed.emit("Unsupported OS: %s" % os_name)
		return

	var url: String = BUTLER_DOWNLOAD_URLS[key]
	_download_dir = _get_local_butler_dir()

	if not DirAccess.dir_exists_absolute(_download_dir):
		DirAccess.make_dir_recursive_absolute(_download_dir)

	_download_zip_path = _download_dir.path_join("butler.zip")
	_redirect_count = 0

	log_message.emit("Downloading butler from %s..." % url, 0)
	_start_download(url)


func _start_download(url: String) -> void:
	# Recreate HTTP request node to avoid reuse issues after redirects
	if _http_download:
		_http_download.cancel_request()
		_http_download.queue_free()
		remove_child(_http_download)

	_http_download = HTTPRequest.new()
	_http_download.max_redirects = 0 # We handle redirects manually
	_http_download.download_file = _download_zip_path
	_http_download.use_threads = true
	add_child(_http_download)
	_http_download.request_completed.connect(_on_download_completed, CONNECT_ONE_SHOT)

	var err := _http_download.request(url)
	if err != OK:
		download_failed.emit("Failed to start download (error %d)." % err)


func _on_download_completed(result: int, response_code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	# Handle redirects (301, 302, 303, 307, 308)
	if response_code >= 300 and response_code < 400:
		_redirect_count += 1
		if _redirect_count > MAX_REDIRECTS:
			download_failed.emit("Too many redirects (%d)." % _redirect_count)
			return

		# Find the Location header
		var redirect_url := ""
		for header in headers:
			if header.to_lower().begins_with("location:"):
				redirect_url = header.substr(header.find(":") + 1).strip_edges()
				break

		if redirect_url == "":
			download_failed.emit("HTTP %d redirect but no Location header found." % response_code)
			return

		# Defer the retry to ensure the old HTTPRequest is fully cleaned up
		call_deferred("_start_download", redirect_url)
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		download_failed.emit("Download failed (result: %d, HTTP: %d)." % [result, response_code])
		return

	log_message.emit("Download complete. Extracting...", 0)

	# Extract zip
	var reader := ZIPReader.new()
	var err := reader.open(_download_zip_path)
	if err != OK:
		download_failed.emit("Failed to open downloaded zip (error %d)." % err)
		return

	var files := reader.get_files()
	for file_name in files:
		var data := reader.read_file(file_name)
		var out_path := _download_dir.path_join(file_name.get_file())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_buffer(data)
			f.close()
	reader.close()

	# Clean up zip
	DirAccess.remove_absolute(_download_zip_path)

	# Make executable on unix
	var butler_path := _get_local_butler_path()
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", ItchExportUtils.globalize_if_needed(butler_path)], [], true)

	_butler_path = butler_path
	log_message.emit("Butler installed at: %s" % butler_path, 0)
	butler_downloaded.emit(butler_path)


## Push a build directory to itch.io (runs in background thread).
func push_build(build_dir: String, target: String, channel: String, api_key: String, version: String = "") -> void:
	if _butler_path == "":
		push_completed.emit(false, "Butler not found. Please install it first.")
		return

	var butler_real_path := ItchExportUtils.globalize_if_needed(_butler_path)

	var args: PackedStringArray = ["push", build_dir, "%s:%s" % [target, channel]]
	if version != "":
		args.append("--userversion")
		args.append(version)

	log_message.emit("Running: butler %s" % " ".join(args), 0)

	# Run in a background thread to avoid freezing the editor
	var thread := Thread.new()
	thread.start(_push_thread_func.bind(butler_real_path, args, api_key, thread))


func _push_thread_func(butler_real_path: String, args: PackedStringArray, api_key: String, thread: Thread) -> void:
	var output: Array = []
	var exit_code: int
	var had_existing_api_key := OS.has_environment("BUTLER_API_KEY")
	var previous_api_key := OS.get_environment("BUTLER_API_KEY") if had_existing_api_key else ""

	# Execute butler directly instead of shell-wrapping the command to avoid quoting/env issues.
	OS.set_environment("BUTLER_API_KEY", api_key)
	exit_code = OS.execute(butler_real_path, args, output, true)
	if had_existing_api_key:
		OS.set_environment("BUTLER_API_KEY", previous_api_key)
	else:
		OS.set_environment("BUTLER_API_KEY", "")

	var output_lines := PackedStringArray()
	for chunk in output:
		output_lines.append(str(chunk))
	var output_text := "\n".join(output_lines)
	output_text = output_text.replace("âˆ™", "•")

	# Emit results back on the main thread
	if exit_code == 0:
		call_deferred("_on_push_thread_done", true, output_text, thread)
	else:
		call_deferred("_on_push_thread_done", false, "Exit code %d:\n%s" % [exit_code, output_text], thread)


func _on_push_thread_done(success: bool, output_text: String, thread: Thread) -> void:
	thread.wait_to_finish()
	push_completed.emit(success, output_text)


func _get_butler_version(path: String) -> String:
	var real_path := ItchExportUtils.globalize_if_needed(path)
	var output: Array = []
	var exit_code := OS.execute(real_path, ["version"], output, true)
	if exit_code == 0 and output.size() > 0:
		return output[0].strip_edges()
	return "unknown"


func _get_local_butler_dir() -> String:
	return "user://butler"


func _get_local_butler_path() -> String:
	if OS.get_name() == "Windows":
		return "user://butler/butler.exe"
	return "user://butler/butler"
