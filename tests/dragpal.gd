extends Node
## 窗口化探针（积木栏路径 + 可选 ui_scale）：从左侧积木栏（GivenBlocks，
## is_given_block=true）按下拿起一个积木副本，拖到工作区 if 积木的身体上方，
## 占位符应进入身体内部容器，松手后积木应落位到身体里。
## 全程用合成 InputEvent 驱动（与真实 OS 鼠标同一输入管线），不用 warp_mouse
## （它在 content_scale_factor != 1 时坐标偏移不可靠）。
## 运行：godot --path <仓库根> res://tests/dragpal.tscn（需窗口模式）
## 可选：DRAGPAL_SCALE=1.5 模拟 ui_scale

var machine := 0   # 模拟 main 提供给 editor 页的 machine 字段
var mouse_pos := Vector2.ZERO   # 当前（合成）鼠标的画布坐标

var fails: Array = []

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		fails.append(msg)
		print("  [FAIL] ", msg)


## 模拟真实鼠标移动到画布坐标 p：
## - 引擎对注入事件按窗口像素（含 content_scale 折算）处理，因此 motion/button 事件
##   的 position 与 warp_mouse 参数都传 p * content_scale（scale=1 时与旧探针一致）。
func _scale() -> float:
	return get_viewport().get_window().content_scale_factor


func _move_to(p: Vector2) -> void:
	mouse_pos = p
	var vp := get_viewport()
	vp.warp_mouse(p * _scale())
	var mm := InputEventMouseMotion.new()
	mm.position = p * _scale()
	Input.parse_input_event(mm)
	await get_tree().process_frame


func _ready() -> void:
	# 支持模拟真实 GUI 的 ui_scale：DRAGPAL_SCALE 环境变量（默认 1.0）
	var scale := float(OS.get_environment("DRAGPAL_SCALE"))
	if scale > 0.0:
		get_tree().root.content_scale_factor = scale
		print("content_scale_factor=", scale)
	await get_tree().process_frame
	await get_tree().process_frame

	var ed: Control = (load("res://Scenes/editor.tscn") as PackedScene).instantiate()
	add_child(ed)
	# 等 editor._ready() 的 place_blocks() 把 ~45 个积木填进积木栏
	for i in 8:
		await get_tree().process_frame
	ed.reset_nodes(get_node("Dragging"))
	for i in 4:
		await get_tree().process_frame

	var ub: Node = ed.get_node("%UserBlocks")
	var given: Node = ed.get_node("%GivenBlocks")

	# 工作区放一个 if 作为宿主体
	var ifblk: Node = (load("res://Blocks/Logics/if.tscn") as PackedScene).instantiate()
	ub.add_child(ifblk)
	ifblk.set("origin_node", ub)
	for i in 4:
		await get_tree().process_frame

	var body: Node = ifblk.call("body_container")
	var body_ctrl := body as Control
	print("palette_given_count=", given.get_child_count())
	print("window_size=", get_viewport().get_visible_rect().size)
	print("if_rect=", (ifblk as Control).get_global_rect())
	print("body_rect=", body_ctrl.get_global_rect(), " in_group=", body.is_in_group("mvl_block_hosts"))

	# 选积木栏里“可见”的一个积木作为拖拽源（取第一个可见的普通积木）
	var src: Control = null
	for c in given.get_children():
		if not (c is Control):
			continue
		if c.get("is_given_block") != true:
			continue
		var r := (c as Control).get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if get_viewport().get_visible_rect().has_point(r.get_center()):
			src = c as Control
			break
	check(src != null, "积木栏中找到可见积木" + (("：" + src.name) if src != null else ""))
	if src == null:
		_finish()
		return

	# 积木内部常有 STOP 的子控件（按钮/输入框/选项），按下点若落在它们上会被消费，
	# 不会触发“从积木栏拿起”。先扫描积木表面，找一个由积木根节点接收鼠标的点。
	var grab_at: Vector2 = await _find_press_point(src)
	check(grab_at != Vector2.INF, "找到由积木根节点接收鼠标的按下点" +
		(("：" + str(grab_at)) if grab_at != Vector2.INF else ""))
	if grab_at == Vector2.INF:
		print("  src_rect=", src.get_global_rect(), " hovered=",
			str(get_viewport().gui_get_hovered_control()))
		_finish()
		return
	print("src=", src.name, " grab_at=", grab_at, " hovered=",
		str(get_viewport().gui_get_hovered_control()))

	# 按下：应触发“从积木栏拿起”路径（is_given_block=true -> duplicate 副本）
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = mouse_pos * _scale()
	Input.parse_input_event(press)
	for i in 6:
		await get_tree().process_frame

	var clone: Node = null
	for c in get_node("Dragging").get_children():
		if c.get("moving") == true:
			clone = c
			break
	check(clone != null, "积木栏按下后 Dragging 下出现移动副本")
	if clone == null:
		_finish()
		return
	print("clone=", clone.name, " moving=", clone.moving, " origin=", str(clone.origin_node))

	# 悬停到 if 身体中央：占位符应进入身体内部容器
	var target := body_ctrl.get_global_rect().get_center()
	print("hover_body=", target)
	for i in 8:
		await _move_to(target)
	var sh: Node = clone.shadow_block
	print("shadow_parent=", str(sh.get_parent()) if sh != null else "null")
	check(sh != null and sh.get_parent() == body,
		"悬停身体中央：占位符进入身体内部容器")

	# 悬停 if 头部区域：整块判定矩形也应命中同一身体
	var if_ctrl := ifblk as Control
	var head_pt := Vector2(if_ctrl.get_global_rect().get_center().x,
		if_ctrl.get_global_rect().position.y + 8.0)
	print("hover_head=", head_pt)
	for i in 8:
		await _move_to(head_pt)
	var sh2: Node = clone.shadow_block
	print("shadow_parent_head=", str(sh2.get_parent()) if sh2 != null else "null")
	check(sh2 != null and sh2.get_parent() == body,
		"悬停 if 头部区域：仍命中同一身体")

	# 松手：副本应落位进身体（body 内唯一的子积木）
	for i in 4:
		await _move_to(target)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = mouse_pos * _scale()
	Input.parse_input_event(release)
	for i in 6:
		await get_tree().process_frame
	if not is_instance_valid(clone):
		print("after_drop clone 已销毁（误入删除区？mouse=", mouse_pos, "）")
		check(false, "松手后副本仍存活并落位到 if 身体")
		_finish()
		return
	print("after_drop parent=", str(clone.get_parent()), " index=", clone.get_index())
	check(clone.get_parent() == body and clone.get_index() == 0,
		"松手后积木落位到 if 身体（parent 与槽位正确）")
	check(body.get_child_count() == 1, "if 身体内有 1 个子积木")

	_finish()


## 在积木表面扫描一个“悬停时由积木根节点接收鼠标”的点：
## 逐点发 motion 事件并查询 gui_get_hovered_control()。
func _find_press_point(ctrl: Control) -> Vector2:
	var vp := get_viewport()
	var r := ctrl.get_global_rect()
	var fy_pts: Array = [2.0, ctrl.size.y * 0.5 - 1.0, ctrl.size.y - 2.0]
	var fx_pts: Array = [2.0, 6.0, ctrl.size.x * 0.5, ctrl.size.x - 6.0]
	for fy in fy_pts:
		for fx in fx_pts:
			var p := Vector2(r.position.x + fx, r.position.y + fy)
			await _move_to(p)
			var h: Control = vp.gui_get_hovered_control()
			if h == ctrl:
				return p
	return Vector2.INF


func _finish() -> void:
	if fails.is_empty():
		print("DRAGPAL PASS")
		get_tree().quit(0)
	else:
		print("DRAGPAL FAILED: ", fails.size(), " 项")
		get_tree().quit(1)
