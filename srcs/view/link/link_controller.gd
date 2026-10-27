class_name LinkController
extends CanvasPointerSession

## 「拖拽锁定跳转目标」会话：在目标按钮上按下，拖到某一块上松手即锁定。
## 三个出口：某一块上松手 → 锁定；拖到自己或左侧块列表 → 解除；空白处 / 右键 / Esc → 取消。
## 按下事件不消费（让按钮走到按下态），松开时才手动复位它。

## 源块（引用字段的宿主）与它要写的字段。
var _source_id: int = 0
var _field: StringName = &""
## 按下时那个按钮：结束时复位它的按下态与焦点。
var _control: Control = null
var _origin: Vector2 = Vector2.ZERO
var _hover_id: int = 0


func start(view: BlockView, element: ElementDef, control: Control) -> void:
	if _active or canvas == null or view == null or view.node == null or element == null:
		return
	if not canvas.graph.has(view.node.id):
		return
	_source_id = view.node.id
	_field = element.id
	_control = control
	_origin = canvas.link_anchor(_source_id)
	_begin_session()


## 落地只认左键。
func _finish_button() -> MouseButton:
	return MOUSE_BUTTON_LEFT


## 右键按下 = 取消，保留原来的目标。
func _is_cancel_button(button: MouseButton) -> bool:
	return button == MOUSE_BUTTON_RIGHT


## 松开事件要消费掉：本控制器收不到按钮的 mouse-up，靠自己复位（见 [method _close_session]）。
func _consumes_release() -> bool:
	return true
func _update_session() -> void:
	var world := _world_mouse()
	# 自己不算候选：拖到自己身上是「解除锁定」，不是「跳到自己」
	_hover_id = canvas.node_at_world(world, {_source_id: true})
	canvas.set_link_preview(_origin, world, _hover_id)


func _finish_session() -> void:
	var world := _world_mouse()
	# 判命中时把自己算进去：拖到自己身上 = 解除锁定
	var hit := canvas.node_at_world(world, {})
	var over_delete := _over_delete_zone()
	# 与拖动块同一套直觉：鼠标没真正动过 = 只点了一下按钮，什么都不改
	var moved := _moved(world)
	var source_id := _source_id
	var field := _field
	_close_session()
	if not moved:
		return
	if over_delete or hit == source_id:
		canvas.set_link(source_id, field, 0)
	elif hit > 0:
		canvas.set_link(source_id, field, hit)


func _close_session() -> void:
	_active = false
	_source_id = 0
	_field = &""
	_hover_id = 0
	set_process(false)
	if PlacementPreview.is_valid_object(_control):
		# 松开事件被本控制器消费了，按钮收不到 mouse-up：手动把它从按下态放回来
		if _control is BaseButton:
			(_control as BaseButton).set_pressed_no_signal(false)
		_control.release_focus()
	_control = null
	if canvas != null:
		canvas.clear_link_preview()


