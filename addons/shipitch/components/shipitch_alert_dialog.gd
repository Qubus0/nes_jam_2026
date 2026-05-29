@tool
class_name ItchExportAlertDialog
extends AcceptDialog

func show_in_parent(parent: Node, alert_title: String, message: String) -> void:
	title = alert_title
	dialog_text = message
	confirmed.connect(func(): queue_free(), CONNECT_ONE_SHOT)
	canceled.connect(func(): queue_free(), CONNECT_ONE_SHOT)
	parent.add_child(self)
	popup_centered()
