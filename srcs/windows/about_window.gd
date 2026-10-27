class_name AboutWindow
extends Window

## 关于窗（帮助 → About）。版本号与引擎版本都是运行期读的，正文链接可点。

const REPOSITORY: String = "https://github.com/LittleFishStars/mindustry-visual-logic"
const DISPLAY_NAME: String = "Mindustry Visual Logic"

@onready var nVersion: Label = %Version
@onready var nBody: RichTextLabel = %Body


func _ready() -> void:
	_apply_styles()
	refresh_language()


## 语言变了（应用在 [Main]）：版本行与正文重取一遍。
func refresh_language() -> void:
	var version := String(ProjectSettings.get_setting("application/config/version", "?"))
	var engine := String(Engine.get_version_info().get("string", "Godot"))
	nVersion.text = tr("ABOUT_VERSION") % [version, engine]
	nBody.text = tr("ABOUT_BODY") % [DISPLAY_NAME, REPOSITORY]


func open() -> void:
	popup_centered()




func _on_meta_clicked(meta: Variant) -> void:
	var url := String(meta)
	if url.begins_with("http://") or url.begins_with("https://"):
		OS.shell_open(url)


func _on_close_pressed() -> void:
	hide()


## 样式统一由 [UiStyle] 提供（场景里不再内联 StyleBox）。
func _apply_styles() -> void:
	var panel := get_node_or_null("Panel")
	if panel is PanelContainer:
		panel.add_theme_stylebox_override("panel", UiStyle.panel_style())
	var bottom := get_node_or_null("Panel/Layout/BottomBar")
	if bottom is PanelContainer:
		bottom.add_theme_stylebox_override("panel", UiStyle.bar_style())
