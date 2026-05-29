@tool
extends EditorPlugin
## Main entry point for the ShipItch addon.
## Adds a dock panel.

const DOCK_SCENE := preload("res://addons/shipitch/shipitch_dock.tscn")

var _dock: Control


func _enter_tree() -> void:
	# Create the dock instance
	_dock = DOCK_SCENE.instantiate()
	_dock.name = "ShipItch"

	# Add dock to the right side
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)

	if _dock.has_method("initialize_dock"):
		_dock.initialize_dock()

	print("[ShipItch] Plugin enabled.")


func _exit_tree() -> void:
	# Remove and free the dock
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

	print("[ShipItch] Plugin disabled.")
