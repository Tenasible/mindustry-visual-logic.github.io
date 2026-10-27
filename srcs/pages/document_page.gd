class_name DocumentPage
extends Control

## 应用内文档页（帮助 → Document）：左边章节，右边富文本。
##
## 正文不在代码里：每页一个文件放在 [constant DOCS_DIR]/<locale>/，文件名排序决定章节顺序，
## 首行是章节名、其余是 BBCode 正文 —— 加一页（或加一种语言）只需往那个文件夹里丢文件。
## 它不是 [LogicEditorTab]（存盘 / 导出 / 撤销在它上面是空操作）。

const DOCS_DIR: String = "res://docs"
const EXTENSION: String = "bbcode"
## 没有对应语言目录时回落到的那一套。
const FALLBACK_LOCALE: String = "en_US"

@onready var nChapters: VBoxContainer = %Chapters
@onready var nTitle: Label = %Title
@onready var nBody: RichTextLabel = %Body

## 章节：`{"title": …, "body": …}`，按文件名排序。
var _sections: Array[Dictionary] = []
var _current: int = -1


func _ready() -> void:
	var content := get_node_or_null("Split/Content")
	if content is PanelContainer:
		var style := UiStyle.panel_style()
		style.content_margin_left = 14.0
		style.content_margin_top = 12.0
		style.content_margin_right = 14.0
		style.content_margin_bottom = 12.0
		content.add_theme_stylebox_override("panel", style)
	reload_language()

## 按当前界面语言重读文档（语言切换时由 [Main] 再调一次）。
func reload_language() -> void:
	for child in nChapters.get_children():
		PlacementPreview.dismiss(child)
	_sections = _load_sections()
	for index in _sections.size():
		var button := Button.new()
		button.text = String(_sections[index].get("title", "?"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: _show_section(index))
		nChapters.add_child(button)
	if _sections.is_empty():
		nTitle.text = tr("DOC_TITLE")
		nBody.text = tr("DOC_MISSING") % [_current_docs_dir(), EXTENSION]
		return
	_show_section(0)


## 当前语言对应的文档目录；该目录不存在时回落到 [constant FALLBACK_LOCALE]。
func _current_docs_dir() -> String:
	var name := "zh_CN" if TranslationServer.get_locale().begins_with("zh") else FALLBACK_LOCALE
	var dir := DOCS_DIR.path_join(name)
	return dir if DirAccess.dir_exists_absolute(dir) else DOCS_DIR.path_join(FALLBACK_LOCALE)


## 读当前语言目录下的文档文件：文件名排序 → 首行章节名，其余正文。
func _load_sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := _current_docs_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var names := DirAccess.get_files_at(dir)
	names.sort()
	for file_name in names:
		if file_name.get_extension().to_lower() != EXTENSION:
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(file_name))
		if text == "":
			push_warning("文档文件为空或读不出来：%s" % file_name)
			continue
		var parts := text.split("\n", true, 1)
		out.append({
			"title": parts[0].strip_edges(),
			"body": parts[1] if parts.size() > 1 else "",
		})
	return out


func _show_section(index: int) -> void:
	if index < 0 or index >= _sections.size():
		return
	_current = index
	nTitle.text = String(_sections[index].get("title", ""))
	nBody.text = String(_sections[index].get("body", ""))
	nBody.scroll_to_line(0)
	for i in nChapters.get_child_count():
		var button := nChapters.get_child(i) as Button
		if button != null:
			button.set_pressed_no_signal(i == index)
