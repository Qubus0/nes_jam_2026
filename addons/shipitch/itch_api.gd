@tool
class_name ItchAPI
extends Node
## Wraps itch.io server-side API calls using HTTPRequest nodes.
## Handles key validation and game listing.

signal key_validated(username: String)
signal games_fetched(games: Array)
signal request_failed(error: String)

const BASE_URL := "https://itch.io/api/1"

var _http_request: HTTPRequest


func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

## Current pending request type
var _pending_request: String = ""


## Validate the API key by fetching the authenticated user info.
func validate_key(api_key: String) -> void:
	if _pending_request != "":
		request_failed.emit("A request is already in progress.")
		return
	_pending_request = "validate"
	var url := "%s/%s/me" % [BASE_URL, api_key]
	var err := _http_request.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		_pending_request = ""
		request_failed.emit("HTTP request failed to start (error %d)." % err)


## Fetch the list of games for the authenticated user.
func fetch_games(api_key: String) -> void:
	if _pending_request != "":
		request_failed.emit("A request is already in progress.")
		return
	_pending_request = "games"
	var url := "%s/%s/my-games" % [BASE_URL, api_key]
	var err := _http_request.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		_pending_request = ""
		request_failed.emit("HTTP request failed to start (error %d)." % err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var request_type := _pending_request
	_pending_request = ""

	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("HTTP request failed (result %d)." % result)
		return

	if response_code != 200:
		request_failed.emit("itch.io returned HTTP %d. Check your API key." % response_code)
		return

	var body_text := body.get_string_from_utf8()
	var json = JSON.parse_string(body_text)
	if json == null:
		request_failed.emit("Failed to parse JSON response.")
		return

	if json is Dictionary and json.has("errors"):
		request_failed.emit("itch.io error: %s" % str(json["errors"]))
		return

	match request_type:
		"validate":
			_handle_validate(json)
		"games":
			_handle_games(json)
		_:
			request_failed.emit("Unknown request type.")


func _handle_validate(json) -> void:
	if not json is Dictionary:
		request_failed.emit("Unexpected response: expected object, got %s." % typeof(json))
		return
	var d: Dictionary = json
	if d.has("user"):
		var user = d["user"]
		if user is Dictionary:
			var username: String = user.get("username", "unknown")
			key_validated.emit(username)
			return
		else:
			# Some API versions return user as a nested structure
			key_validated.emit(str(user))
			return
	request_failed.emit("Unexpected response format for user validation. Keys: %s" % str(d.keys()))


func _handle_games(json) -> void:
	if not json is Dictionary:
		request_failed.emit("Unexpected response: expected object, got %s." % typeof(json))
		return
	var d: Dictionary = json
	if d.has("games"):
		var games_data = d["games"]
		if games_data is Array:
			games_fetched.emit(games_data)
		else:
			request_failed.emit("Games field has unexpected type: %s (typeof=%d). Raw: %s" % [str(type_string(typeof(games_data))), typeof(games_data), str(games_data).left(200)])
		return
	else:
		request_failed.emit("Response missing 'games' key. Keys found: %s" % str(d.keys()))
