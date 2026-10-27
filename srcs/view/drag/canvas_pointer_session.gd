class_name CanvasPointerSession
extends Node

## 画布上的指针会话骨架：搬块与锁定跳转目标共用（[DragController] / [LinkController]）。
##
## 只管开始 / 每帧 / 落地 / 取消 / 失焦收尾 + 世界坐标与删除区判断；差异由三个钩子回答
## （[method _finish_button] / [method _is_cancel_button] / [method _consumes_release]）。

## 画布，以及会话覆盖的区域（SubViewportContainer，用于屏幕↔世界坐标换算）。
var canvas: EditorCanvas
var area: SubViewportContainer
## 拖到这里松手 = 删掉搬的块 / 解除锁定（左侧块列表）。
var delete_zones: Array[Control] = []

## 按下后鼠标挪动超过这么多像素才算「真的搬动了」。
const MOVE_THRESHOLD: float = 4.0

var _active: bool = false
var _start_mouse: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_process(false)


func is_active() -> bool:
	return _active


## 取消会话（右键 / Esc / 失焦），不改数据；要复原临时位置的子类覆写它。
func cancel() -> void:
	if not _active:
		return
	_close_session()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var button: MouseButton = (event as InputEventMouseButton).button_index
	if event.pressed:
		# 另一个键按下 = 取消（左键搬移时按右键、右键复制时按左键……）
		if _is_cancel_button(button):
			cancel()
			get_viewport().set_input_as_handled()
	elif button == _finish_button():
		_finish_session()
		# 默认不消费松开事件：SubViewportContainer 靠 is_input_handled() 决定要不要把事件
		# 转发进画布 —— 吞掉 mouse-up 会让画布 GUI 的按键掩码清不掉（之后“拖不动块”）。
		if _consumes_release():
			get_viewport().set_input_as_handled()


## 窗口失焦（切窗口 / 在窗口外松手）：收尾的 mouse-up 多半收不到，主动取消。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _active:
		cancel()


func _process(_delta: float) -> void:
	if _active:
		_update_session()


## 会话开始：子类把状态摆好后调用（它不负责那次拖拽的初始化）。
func _begin_session() -> void:
	_start_mouse = _world_mouse()
	_active = true
	# 会话期间画布不该被相机平移抢走（左键既是平移也是搬块）
	if canvas != null and canvas.nCamera != null:
		canvas.nCamera.stop_panning()
	_on_session_started()
	set_process(true)
	_update_session()


func _world_mouse() -> Vector2:
	return canvas.world_from_screen(area.get_global_rect(), get_viewport().get_mouse_position())


func _over_delete_zone() -> bool:
	var mouse := get_viewport().get_mouse_position()
	for zone in delete_zones:
		if PlacementPreview.is_valid_object(zone) and zone.is_visible_in_tree() and zone.get_global_rect().has_point(mouse):
			return true
	return false


## 鼠标是否还在画布区域内（在外面松手 = 取消）。
func _inside_canvas() -> bool:
	if not PlacementPreview.is_valid_object(area):
		return false
	return area.get_global_rect().has_point(get_viewport().get_mouse_position())


func _moved(world: Vector2) -> bool:
	return (world - _start_mouse).length() > MOVE_THRESHOLD


#region 子类钩子

func _finish_button() -> MouseButton:
	return MOUSE_BUTTON_LEFT


## 哪个键按下算取消（默认：不是落地键的那个）。
func _is_cancel_button(button: MouseButton) -> bool:
	return button != _finish_button()


## 松开事件要不要消费（默认不消费，理由见 [method _input] 的注释）。
func _consumes_release() -> bool:
	return false


func _on_session_started() -> void:
	pass


func _update_session() -> void:
	pass


## 松手落地（子类实现；收尾请自行调 [method _close_session]）。
func _finish_session() -> void:
	pass


## 清掉会话状态与画布上的临时效果（取消与落地都会走到）。
func _close_session() -> void:
	pass

#endregion
