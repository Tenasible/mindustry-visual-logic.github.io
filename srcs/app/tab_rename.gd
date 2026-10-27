class_name TabRename
extends Node

## 标签条的「就地重命名」：单击已选中的标签或右键任意标签，在标签上浮一个输入框。
## 它只认识 [TabContainer] 与标签下标，「改完写到哪」由 [signal name_submitted] 交给外壳。
## 手势：单击延迟一个双击间隔才开框（否则双击关标签会闪一下）；按住拖走 = 取消改名。

## 名字提交了：[param index] 是标签下标，[param value] 是用户输入的内容（空 = 回落默认）。
signal name_submitted(index: int, value: String)
## 双击某个标签 = 关掉它（关掉最后一个要补一个空白页，那是外壳的事）。
signal close_requested(index: int)

## 单击后等多久才开重命名框：取引擎判定双击的同一个间隔，双击时就不会先闪一下。
const RENAME_DELAY_MS: int = 400
## 按下后鼠标挪动超过这么多像素，就当「在拖动重排标签」，不再弹重命名框。
const DRAG_CANCEL_PX: float = 4.0

var _tabs: TabContainer = null
## 标签条上的就地重命名输入框（TabBar 的子节点，不占标签页）。
var _edit: LineEdit = null
var _index: int = -1
var _pending_index: int = -1
var _pending_token: int = 0
var _press_pos: Vector2 = Vector2.ZERO


## 接管一个标签容器的标签条（在它和它的标签条都进树之后调用）。
func setup(tabs: TabContainer) -> void:
	_tabs = tabs
	var bar := _tabs.get_tab_bar()
	if bar == null:
		return
	bar.gui_input.connect(_on_tab_gui_input)
	bar.tab_rmb_clicked.connect(open)
	_edit = LineEdit.new()
	_edit.hide()
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.text_submitted.connect(func(_text: String) -> void: commit())
	_edit.focus_exited.connect(commit)
	_edit.gui_input.connect(_on_rename_input)
	bar.add_child(_edit)


## 在某个标签上就地编辑它的名字（鼠标右键或单击已选中标签时调用）。
func open(index: int) -> void:
	if _edit == null or index < 0 or index >= _tabs.get_tab_count():
		return
	var bar := _tabs.get_tab_bar()
	if bar == null:
		return
	if _index == index and _edit.visible:
		# 已经在改这个名字了：不要把正在输入的内容重置回标签标题
		_edit.grab_focus()
		return
	_index = index
	var rect := bar.get_tab_rect(index)
	_edit.text = _tabs.get_tab_title(index)
	_edit.position = rect.position
	_edit.size = Vector2(maxf(rect.size.x, 96.0), rect.size.y)
	_edit.show()
	_edit.grab_focus()
	_edit.select_all()


func commit() -> void:
	if _index < 0 or _edit == null:
		return
	var index := _index
	var value := _edit.text
	close()
	name_submitted.emit(index, value)


## 收起输入框。先清下标再放焦点：release_focus 发的 focus_exited 会递归回到 [method commit]。
func close() -> void:
	_index = -1
	if _edit != null:
		_edit.hide()
		_edit.release_focus()


## 标签条上的鼠标按下：单击已选中的标签 = 重命名，双击任意标签 = 关闭它。
## 事件早于内建处理，所以能看到「点击前的当前页」，也能用引擎给的 double_click。
func _on_tab_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 按住左键拖走 = 拖动重排标签，取消排队中的改名（没按键的移动不算）。
		if _pending_index >= 0 \
				and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
				and (event.position - _press_pos).length() > DRAG_CANCEL_PX:
			_cancel_pending()
		return
	if not (event is InputEventMouseButton) or not event.pressed \
			or event.button_index != MOUSE_BUTTON_LEFT:
		return
	_press_pos = event.position
	var index := _tab_at(event.position)
	if index < 0:
		return
	if event.double_click:
		_cancel_pending()
		close_requested.emit(index)
		return
	if index != _tabs.current_tab:
		return
	queue(index)


func queue(index: int) -> void:
	_pending_index = index
	_pending_token += 1
	var token := _pending_token
	await get_tree().create_timer(RENAME_DELAY_MS / 1000.0).timeout
	if token != _pending_token or _pending_index != index:
		return
	_pending_index = -1
	open(index)


func _cancel_pending() -> void:
	_pending_index = -1
	_pending_token += 1


func _tab_at(point: Vector2) -> int:
	var bar := _tabs.get_tab_bar()
	if bar == null:
		return -1
	for i in _tabs.get_tab_count():
		if bar.get_tab_rect(i).has_point(point):
			return i
	return -1


func _on_rename_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		_edit.accept_event()
