extends PanelContainer

## 公告条目：时间 + 富文本正文（样式由 [UiStyle] 提供）。

@onready var nTime: Label = $Box/Time
@onready var nContent: RichTextLabel = $Box/Content


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.notice_item_style())


func init(time: String, content: String) -> void:
	nTime.text = time if time != null else tr("NOTICE_TIME_UNKNOWN")
	nContent.text = content if content != null else tr("NOTICE_EMPTY_ITEM")
