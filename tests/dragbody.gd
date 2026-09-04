extends Node
## 窗口化探针：拖动中的积木悬停在 if 身体中央时，占位符应进入身体内部容器。
## 运行：godot --path <仓库根> res://tests/dragbody.tscn（需窗口模式，headless 下 warp_mouse 无效）

const BlockDragScn := preload("res://Scripts/block_drag.gd")

var machine := 0
var fails: Array = []

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		fails.append(msg)
		print("  [FAIL] ", msg)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var ed: Control = (load("res://Scenes/editor.tscn") as PackedScene).instantiate()
	add_child(ed)
	await get_tree().process_frame
	await get_tree().process_frame
	ed.reset_nodes(get_node("Dragging"))
	await get_tree().process_frame

	var selhost: Node = ed.get_node_or_null("SelectionHost")
	var sel = selhost.get("selection") if selhost != null else null   # BlockSelection(RefCounted)
	check(selhost != null and sel != null, "SelectionHost 可用（取 selection 模型）")

	var ub: Node = ed.get_node("%UserBlocks")
	var ub_ctrl := ub as Control

	# 放一个 if 作为宿主体
	var ifblk: Node = (load("res://Blocks/Logics/if.tscn") as PackedScene).instantiate()
	ub.add_child(ifblk)
	ifblk.set("origin_node", ub)
	await get_tree().process_frame
	await get_tree().process_frame

	var body: Node = ifblk.call("body_container")
	var br: Rect2 = (body as Control).get_global_rect()
	print("body_rect=", br, " in_group=", body.is_in_group("mvl_block_hosts"))
	print("ub_rect=", (ub as Control).get_global_rect())
	var hosts: Array = get_tree().get_nodes_in_group("mvl_block_hosts")
	print("host_count=", hosts.size())

	# 走与真实拖动一致的完整路径：把左键“按下”在要拖的积木上，
	# 让 LogicBlocks 自己抓起它，再把指针移到身体中央观察占位符去向
	var drag: Node = (load("res://Blocks/Operations/set.tscn") as PackedScene).instantiate()
	ub.add_child(drag)
	drag.set("origin_node", ub)
	await get_tree().process_frame
	await get_tree().process_frame

	var viewport := get_viewport()
	print("window_size=", viewport.get_visible_rect().size)
	var dr := (drag as Control).get_global_rect()
	var grab_at := dr.position + Vector2(3.0, dr.size.y * 0.5)
	print("grab_at=", grab_at)

	viewport.warp_mouse(grab_at)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = grab_at
	Input.parse_input_event(press)
	for i in 4:
		await get_tree().process_frame

	print("after_grab moving=", drag.moving, " parent=", str(drag.get_parent()))
	check(drag.moving and drag.get_parent() == get_node("Dragging"), "积木被正常抓起")
	check(sel.is_empty(), "抓取/拖动过程中不产生选中（选中延迟到手势结束）")

	var target := br.get_center()
	print("warp_to=", target)
	viewport.warp_mouse(target)
	for i in 8:
		await get_tree().process_frame
		viewport.warp_mouse(target)
		await get_tree().process_frame

	var sh: Node = drag.shadow_block
	print("shadow_parent=", str(sh.get_parent()) if sh != null else "null")
	print("moving=", drag.moving)
	check(sh != null and sh.get_parent() == body,
		"真实逻辑驱动下占位符进入身体内部容器（parent=" + str(sh.get_parent() if sh != null else null) + "）")

	# 悬停在“身体面板的左边缘/缩进条”这类窄条上也应命中身体内部（有效判定矩形）
	var body_wrap: Control = ifblk.get_node_or_null("VBoxContainer/Body")
	if body_wrap != null and drag.moving and drag.shadow_block != null:
		var wr: Rect2 = body_wrap.get_global_rect()
		var left_point := Vector2(wr.position.x + 6.0, wr.get_center().y)
		print("left_point=", left_point, " inBodyPanel=", wr.has_point(left_point))
		viewport.warp_mouse(left_point)
		for i in 8:
			await get_tree().process_frame
			viewport.warp_mouse(left_point)
			await get_tree().process_frame
		var sh2: Node = drag.shadow_block
		print("shadow_parent_left=", str(sh2.get_parent()) if sh2 != null else "null")
		check(sh2 != null and sh2.get_parent() == body,
			"身体面板左边缘处也命中身体内部容器")

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = viewport.get_mouse_position()
	Input.parse_input_event(release)
	for i in 6:
		await get_tree().process_frame
	check(drag.get_parent() == body, "松手后积木落位到 if 身体（拖动放下）")
	check(sel.is_empty(), "拖动放下后不残留选中（位移超阈值 -> clear）")

	# ---- 点击 vs 拖动手势：原地点击应选中该积木 ----
	var sr := (drag as Control).get_global_rect()
	var click_at := sr.position + Vector2(3.0, sr.size.y * 0.5)
	print("click_at=", click_at)
	viewport.warp_mouse(click_at)
	var press2 := InputEventMouseButton.new()
	press2.button_index = MOUSE_BUTTON_LEFT
	press2.pressed = true
	press2.position = click_at
	Input.parse_input_event(press2)
	for i in 4:
		await get_tree().process_frame
	check(sel.is_empty(), "原地点击按下瞬间仍不选中（待定手势）")
	var release2 := InputEventMouseButton.new()
	release2.button_index = MOUSE_BUTTON_LEFT
	release2.pressed = false
	release2.position = viewport.get_mouse_position()
	Input.parse_input_event(release2)
	for i in 8:
		await get_tree().process_frame
	print("after_click sel_size=", sel.size(), " is_selected=", sel.is_selected(drag))
	check(sel.size() == 1 and sel.is_selected(drag), "原地点击松开后选中该积木")

	# ---- 已选中的积木再被拖动放下：应清空选中（原投诉场景） ----
	var press3 := InputEventMouseButton.new()
	press3.button_index = MOUSE_BUTTON_LEFT
	press3.pressed = true
	press3.position = viewport.get_mouse_position()
	Input.parse_input_event(press3)
	for i in 4:
		await get_tree().process_frame
	var away := Vector2(ub_ctrl.get_global_rect().position.x + 30.0,
		ub_ctrl.get_global_rect().end.y - 30.0)
	print("drag_away_to=", away)
	viewport.warp_mouse(away)
	for i in 8:
		await get_tree().process_frame
		viewport.warp_mouse(away)
		await get_tree().process_frame
	var release3 := InputEventMouseButton.new()
	release3.button_index = MOUSE_BUTTON_LEFT
	release3.pressed = false
	release3.position = viewport.get_mouse_position()
	Input.parse_input_event(release3)
	for i in 6:
		await get_tree().process_frame
	print("after_drag_away parent=", str(drag.get_parent()), " sel_size=", sel.size())
	check(sel.is_empty(), "已选中积木拖动放下后清除选中")
	check(drag.get_parent() == ub, "拖动落位回到 UserBlocks")

	drag.queue_free()
	ifblk.queue_free()
	await get_tree().process_frame

	if fails.is_empty():
		print("DRAGBODY PASS")
		get_tree().quit(0)
	else:
		print("DRAGBODY FAILED: ", fails.size())
		get_tree().quit(1)
