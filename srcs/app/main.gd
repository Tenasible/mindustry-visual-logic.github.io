@tool
extends Container

## 应用外壳：菜单栏、多标签编辑器、文件对话框、公告窗、自定义光标 —— 只做菜单分发。

@onready var nMenuBar: Control = $MenuBar
@onready var nEditors: TabContainer = $Editors
@onready var nBackground: Panel = $Panel
@onready var wNotice: Window = $NoticeWindow
@onready var wProject: FileDialog = $ProjectDialog
@onready var nQuitButton: Button = $Quit
@onready var nEditMenu: PopupMenu = $MenuBar/Edit
@onready var nFileMenu: PopupMenu = $MenuBar/File
@onready var wSettings: SettingsWindow = $SettingsWindow
@onready var wAbout: AboutWindow = $AboutWindow

var Editor = preload("res://srcs/pages/editor.tscn")
var Document = preload("res://srcs/pages/document_page.tscn")

var custom_cursor = preload("res://assets/sprites/cursors/cursor.png")
var ibeam_cursor = preload("res://assets/sprites/cursors/ibeam.png")
var hand_cursor = preload("res://assets/sprites/cursors/hand.png")
var hsize_cursor = preload("res://assets/sprites/cursors/hsize.png")
var vsize_cursor = preload("res://assets/sprites/cursors/vsize.png")
var bdiagsize_cursor = preload("res://assets/sprites/cursors/bdiagsize.png")
var fdiagsize_cursor = preload("res://assets/sprites/cursors/fdiagsize.png")

var _dialog_mode: StringName = &"open"

## 标签条的「就地重命名」：手势与输入框都在 [TabRename] 里，外壳只接「改完写到哪」。
var _rename: TabRename = null
## F5 快捷导出的 action 名（键位在 project.godot，换键不用改代码）。
const QUICK_EXPORT_ACTION: StringName = &"compile"
## Ctrl+C / Ctrl+V 也走 project.godot 的动作；这两个不入菜单（accelerator 被 F5 占着），所以走 [method _unhandled_key_input] 兜底。
const QUICK_COPY_ACTION: StringName = &"copy_mlog"
const QUICK_PASTE_ACTION: StringName = &"paste_mlog"

var _settings: AppSettings = null
func _ready() -> void:
	Input.set_custom_mouse_cursor(custom_cursor, Input.CURSOR_ARROW, Vector2(32, 32))
	Input.set_custom_mouse_cursor(ibeam_cursor, Input.CURSOR_IBEAM, Vector2(32, 32))
	Input.set_custom_mouse_cursor(hand_cursor, Input.CURSOR_POINTING_HAND, Vector2(32, 32))
	Input.set_custom_mouse_cursor(vsize_cursor, Input.CURSOR_VSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(hsize_cursor, Input.CURSOR_HSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(bdiagsize_cursor, Input.CURSOR_BDIAGSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(fdiagsize_cursor, Input.CURSOR_FDIAGSIZE, Vector2(32, 32))
	# 读设置并应用（帧率 / UI 缩放）；设置窗口只管改数据，应用在这里
	self._settings = AppSettings.load_from_disk()
	self._apply_settings()
	# 编辑器里 SettingsWindow 的脚本不是 @tool（实例是占位的），碰它的方法与信号都会报错
	if not Engine.is_editor_hint():
		self.wSettings.setup(self._settings)
		self.wSettings.changed.connect(_on_settings_changed)
		self.wSettings.closed.connect(_on_settings_closed)

	self.nFileMenu.set_item_accelerator(4, KEY_F5)

	self.new_editor()
	self._setup_tab_rename()


func _on_sort_children() -> void:
	fit_child_in_rect(self.nBackground, Rect2(Vector2.ZERO, Vector2(self.size)))
	# 工具栏一行：左菜单右退出（先量行高，再按退出按钮宽度把菜单栏缩回去）
	fit_child_in_rect(self.nMenuBar, Rect2(Vector2.ZERO, Vector2(self.size.x, 0)))
	var row_height := self.nMenuBar.size.y
	var quit_width: float = maxf(self.nQuitButton.get_combined_minimum_size().x, 72.0)
	fit_child_in_rect(self.nQuitButton, Rect2(self.size.x - quit_width, 0, quit_width, row_height))
	fit_child_in_rect(self.nMenuBar, Rect2(Vector2.ZERO, Vector2(self.size.x - quit_width, row_height)))
	fit_child_in_rect(self.nEditors, Rect2(0, row_height, self.size.x, self.size.y - row_height))


#region 标签页

func new_page(title: StringName, scn: Resource) -> Node:
	var node = scn.instantiate()
	var count = 1
	self.nEditors.add_child(node)
	self.nEditors.current_tab = node.get_index()
	while self.nEditors.has_node(title + str(count)):
		count += 1
	node.name = title + str(count)
	return node


func new_editor() -> LogicEditorTab:
	var node := self.new_page("Editor", self.Editor) as LogicEditorTab
	# 编辑器里 LogicEditorTab 的脚本不是 @tool（实例是占位的）：接信号、取标题都会报错
	if node != null and not Engine.is_editor_hint():
		node.name_changed.connect(_on_editor_name_changed.bind(node))
		_refresh_tab_title(node)
	return node


func _current_editor() -> LogicEditorTab:
	return self.nEditors.get_current_tab_control() as LogicEditorTab


func _refresh_tab_title(editor: LogicEditorTab) -> void:
	if not PlacementPreview.is_valid_object(editor):
		return
	var index := editor.get_index()
	if index >= 0 and index < self.nEditors.get_tab_count():
		self.nEditors.set_tab_title(index, editor.display_name())
		self.nEditors.set_tab_tooltip(index, tr("TAB_TOOLTIP"))


func _on_editor_name_changed(_display: String, editor: LogicEditorTab) -> void:
	_refresh_tab_title(editor)


func _setup_tab_rename() -> void:
	self.nEditors.tab_changed.connect(_on_tab_changed)
	self._rename = TabRename.new()
	self.add_child(self._rename)
	self._rename.setup(self.nEditors)
	self._rename.name_submitted.connect(_on_tab_renamed)
	self._rename.close_requested.connect(_close_tab)


## 关闭某个标签页；关掉最后一个就补一个空白页。
func _close_tab(index: int) -> void:
	self._rename.close()
	if index < 0 or index >= self.nEditors.get_tab_count():
		return
	var page := self.nEditors.get_tab_control(index)
	if page != null:
		self.nEditors.remove_child(page)
		page.queue_free()
	if self.nEditors.get_tab_count() == 0:
		self.new_editor()


func _on_tab_changed(_tab: int) -> void:
	# 切页/新增页先提交没落下的名字，免得输入框留在旧标签位置
	self._rename.commit()


func _on_tab_renamed(index: int, value: String) -> void:
	var editor := self._editor_at(index)
	if editor != null:
		editor.set_custom_name(value)
		self._refresh_tab_title(editor)


func _editor_at(index: int) -> LogicEditorTab:
	if index < 0 or index >= self.nEditors.get_tab_count():
		return null
	return self.nEditors.get_tab_control(index) as LogicEditorTab
#endregion

#region 编辑菜单

## 编辑菜单：0 撤销 / 1 重做 / 2 清空 / 3 设置
func _on_edit_id_pressed(id: int) -> void:
	match id:
		0:
			self._undo()
		1:
			self._redo()
		2:
			self._clear_current()
		3:
			self.wSettings.open()


## 菜单弹出前按当前页状态置灰（没得撤销/重做、画布为空）。
func _on_edit_about_to_popup() -> void:
	var editor := self._current_editor()
	self.nEditMenu.set_item_disabled(0, editor == null or not editor.can_undo())
	self.nEditMenu.set_item_disabled(1, editor == null or not editor.can_redo())
	self.nEditMenu.set_item_disabled(2, editor == null or editor.is_empty())


func _clear_current() -> void:
	var editor := self._current_editor()
	if editor != null:
		editor.clear_graph()


#endregion


#region 设置
## 把设置搬到引擎上（帧率上限 / UI 缩放 / 语言）；@tool 下跳过，免得改掉 Godot 编辑器自己的帧率、缩放与语言。
func _apply_settings() -> void:
	if _settings == null or Engine.is_editor_hint():
		return
	Engine.max_fps = _settings.max_fps
	get_tree().root.content_scale_factor = _settings.ui_scale
	_apply_language()


## 换语言：设置翻译服务，再让各页按新语言重取自己的文字（块定义 / 文档 / 代码写死的标题）。
## 场景与控件里的文本由 Godot 自动重译，不用管。
func _apply_language() -> void:
	if TranslationServer.get_locale() != _settings.active_locale():
		TranslationServer.set_locale(_settings.active_locale())
		self._reload_localized_content()
	# 窗口标题走系统 API，不跟控件一起自动重译：每次都显式写一遍
	self.wSettings.title = tr("SETTINGS_TITLE")
	self.wAbout.title = tr("ABOUT_TITLE")


## 按新语言重取「不会自动重译」的内容：设置窗下拉框、关于窗正文、标签标题、块定义与文档。
func _reload_localized_content() -> void:
	self.wSettings.refresh_language()
	self.wAbout.refresh_language()
	for index in self.nEditors.get_tab_count():
		var page := self.nEditors.get_tab_control(index)
		if page is LogicEditorTab:
			page.reload_language()
			self._refresh_tab_title(page)
		elif page is DocumentPage:
			page.reload_language()
			self.nEditors.set_tab_title(index, tr("TAB_MANUAL"))


func _on_settings_changed() -> void:
	self._apply_settings()


func _on_settings_closed() -> void:
	self._apply_settings()
	var error := _settings.save_to_disk()
	if error != OK:
		push_warning("设置没能写进 %s（错误码 %d）" % [AppSettings.path, error])


## 切走窗口：按设置把当前页 mlog 丢进剪贴板（空程序 / 非编辑器页不动）；只认 APPLICATION_FOCUS_OUT，连 WM_WINDOW_FOCUS_OUT 会重复导出。
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT or _settings == null:
		return
	# 编辑器里子场景是占位实例，调它的方法会报 placeholder instance 错（AGENTS.md 记载的坑）
	if Engine.is_editor_hint():
		return
	if not _settings.export_on_focus_lost:
		return
	var editor := self._current_editor()
	if editor == null:
		return
	var text := editor.copy_mlog_to_clipboard(true)
	if text.strip_edges() == "":
		print("[MVL] 失焦自动导出：当前页没有 mlog，剪贴板保持不变")
		return
	print("[MVL] 失焦自动导出 %d 行 mlog 到剪贴板" % text.count("\n"))


#endregion

#region 文件菜单

## 文件菜单：0 新建 / 1 保存 / 2 另存为 / 3 打开 / 4 导出到剪贴板（F5）/ 5 从剪贴板导入 / 6 追加导入。
func _on_file_id_pressed(id: int) -> void:
	match id:
		0:
			self.new_editor()
		1:
			self._save_current(false)
		2:
			self._save_current(true)
		3:
			self._open_project()
		4:
			self._export_to_clipboard()
		5:
			self._import_clipboard(false)
		6:
			self._import_clipboard(true)


func _save_current(force_dialog: bool) -> void:
	var editor := self._current_editor()
	if editor == null:
		return
	if not force_dialog and editor.file_path != "":
		var error := editor.save_to(editor.file_path)
		if error != OK:
			push_warning(GraphSerializer.last_error())
		return
	_dialog_mode = &"save"
	self.wProject.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	self.wProject.title = tr("DIALOG_SAVE_PROJECT")
	self.wProject.current_file = editor.display_name() + GraphSerializer.FILE_EXTENSION
	self.wProject.popup_centered()


func _open_project() -> void:
	_dialog_mode = &"open"
	self.wProject.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	self.wProject.title = tr("DIALOG_OPEN_PROJECT")
	self.wProject.popup_centered()


func _on_project_dialog_file_selected(path: String) -> void:
	var editor := self._current_editor()
	if editor == null:
		return
	if _dialog_mode == &"save":
		var error := editor.save_to(path)
		if error != OK:
			push_warning(GraphSerializer.last_error())
		return
	if path.get_extension() == "":
		path += GraphSerializer.FILE_EXTENSION
	if not editor.load_from(path):
		push_warning(GraphSerializer.last_error())


## 导出当前页到剪贴板（菜单项、F5、按键兜底三条路都走这里）。
func _export_to_clipboard() -> void:
	var editor := self._current_editor()
	if editor == null:
		print("[MVL] 当前页没有逻辑可导出（导出只对编辑器页有意义）")
		return
	var text := editor.copy_mlog_to_clipboard()
	print("[MVL] 已导出 %d 行 mlog 到剪贴板" % text.count("\n"))


## F5 的兜底路径（键位在 project.godot）：平时事件在菜单栏就被 accelerator 接走了。
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(QUICK_EXPORT_ACTION):
		self._export_to_clipboard()
		self.get_viewport().set_input_as_handled()
		return
	# Ctrl+C/V 只在没人接时才当整页操作（输入框有焦点时到不了这里）
	if event.is_action_pressed(QUICK_COPY_ACTION):
		self._export_to_clipboard()
		self.get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(QUICK_PASTE_ACTION):
		self._paste_clipboard_as_chain()
		self.get_viewport().set_input_as_handled()


func _undo() -> void:
	var editor := self._current_editor()
	if editor != null:
		editor.undo()


func _import_clipboard(append: bool) -> void:
	var editor := self._current_editor()
	if editor == null:
		return
	var text := DisplayServer.clipboard_get()
	var count := editor.import_mlog(text, append)
	if count == 0:
		push_warning("剪贴板里没有可识别的 mlog")
	return


## Ctrl+V：读剪贴板 → 转成块 → 放成一条新链（不接到现有块上，摆在它们下方）。
func _paste_clipboard_as_chain() -> void:
	var editor := self._current_editor()
	if editor == null:
		print("[MVL] 当前页没有逻辑可粘贴（粘贴只对编辑器页有意义）")
		return
	var text := DisplayServer.clipboard_get()
	var count := editor.paste_mlog_new_chain(text)
	if count == 0:
		push_warning("剪贴板里没有可识别的 mlog")
		return
	print("[MVL] 已把剪贴板里的 %d 个块粘到下方（未连接）" % count)
	return


func _redo() -> void:
	var editor := self._current_editor()
	if editor != null:
		editor.redo()

#endregion


#region 帮助菜单

## 帮助菜单：0 文档 / 1 公告 / 2 关于
func _on_help_id_pressed(id: int) -> void:
	match id:
		0:
			self._open_document()
		1:
			self.wNotice.show()
		2:
			self.wAbout.open()


## 文档页：已经开着就切过去，不重复开标签页。
func _open_document() -> void:
	var existing := self._document_page()
	if existing != null:
		self.nEditors.current_tab = existing.get_index()
		return
	var page := self.new_page("Manual", self.Document)
	self.nEditors.set_tab_title(page.get_index(), tr("TAB_MANUAL"))


func _document_page() -> DocumentPage:
	for child in self.nEditors.get_children():
		if child is DocumentPage:
			return child
	return null
#endregion


#region 工具栏

func _on_quit_pressed() -> void:
	self.get_tree().quit()

#endregion
