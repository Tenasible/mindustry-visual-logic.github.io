extends Window

## 公告窗：从 textdb.online 拉取公告并逐条展示。内嵌脚本的样式已移到 [UiStyle]。

var NoticeItem := preload("res://srcs/windows/notice_item.tscn")

@onready var Request: HTTPRequest = $Request
@onready var nList: VBoxContainer = $Container/Scroll/Margin/NoticeList


func _ready() -> void:
	var panel := get_node_or_null("Container")
	if panel is PanelContainer:
		panel.add_theme_stylebox_override("panel", UiStyle.panel_style())
	var bottom := get_node_or_null("Container/BottonBox")
	if bottom is PanelContainer:
		bottom.add_theme_stylebox_override("panel", UiStyle.bar_style())
	Request.request("https://textdb.online/MindVisualLogic")


func _on_request_completed(result: int, _response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result != OK:
		return
	if body.is_empty():
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json is not Dictionary:
		return
	title = json.get("title", title)
	for msg in json.get("messages", []):
		var item = NoticeItem.instantiate()
		nList.add_child(item)
		item.init(msg.get("time"), msg.get("message"))


func _on_close_requested() -> void:
	hide()
