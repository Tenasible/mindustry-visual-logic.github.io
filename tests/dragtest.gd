extends Node
## BlockDrag 纯函数 + LogicBlocks.commit_drop 落位/删除 的 headless 测试：
##   godot --headless --path <仓库根> res://tests/dragtest.tscn
## 退出码 0 = 通过；1 = 有失败项。

const BlockDrag := preload("res://Scripts/block_drag.gd")

var fails: Array = []
var machine := 0
var _bump_count := 0

func _bump(_s) -> void:
	_bump_count += 1

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		fails.append(msg)
		print("  [FAIL] ", msg)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var host := Control.new()
	host.position = Vector2(40, 50)
	host.size = Vector2(700, 900)
	add_child(host)

	var dragging := Node2D.new()
	add_child(dragging)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	host.add_child(vbox)
	vbox.position = Vector2(60, 70)

	# 三行不同高度的占位块
	var rows := []
	for i in 3:
		var p := PanelContainer.new()
		p.name = "Row%d" % i
		p.custom_minimum_size = Vector2(260, 40 + i * 25)
		vbox.add_child(p)
		rows.append(p)

	await get_tree().process_frame
	await get_tree().process_frame

	# ---------- BlockDrag 几何 ----------
	var centers := []
	for r in rows:
		var c := r as Control
		centers.append(c.global_position.y + c.size.y * 0.5)

	check(BlockDrag.find_insert_slot(vbox, centers[0] - 0.5) == 0, "鼠标在首行中心上方 -> 槽位 0")
	check(BlockDrag.find_insert_slot(vbox, centers[0] + 0.5) == 1, "鼠标在首行中心下方 -> 槽位 1")
	check(BlockDrag.find_insert_slot(vbox, centers[1] + 0.5) == 2, "鼠标在次行中心下方 -> 槽位 2")
	check(BlockDrag.find_insert_slot(vbox, centers[2] + 0.5) == 3, "鼠标在末行中心下方 -> 槽位 3")
	check(BlockDrag.find_insert_slot(vbox, centers[0] - 500) == 0, "远高于列表 -> 0")
	check(BlockDrag.find_insert_slot(vbox, centers[2] + 500) == 3, "远低于列表 -> 3")

	# 单调性：鼠标 y 递增时槽位不下降
	var prev := -1
	var monotonic := true
	for k in 30:
		var y := float(centers[0]) - 100 + k * 10.0
		var s := BlockDrag.find_insert_slot(vbox, y)
		if s < prev:
			monotonic = false
		prev = s
	check(monotonic, "槽位随鼠标 y 单调不减")

	# 忽略占位符参数
	check(BlockDrag.find_insert_slot(vbox, centers[1] - 0.5, rows[1]) == 1,
		"ignore 占位符不影响计数（排除自身）")

	# ignore 支持数组（整组拖动时忽略整组占位符）
	var slot_ign2 := BlockDrag.find_insert_slot(vbox, centers[1] - 0.5, [rows[0], rows[1]])
	check(slot_ign2 == 0, "ignore 数组生效（忽略前两行后计数为 0）")

	# blocks_in_rect：矩形命中
	var r1 := Rect2((rows[1] as Control).global_position - Vector2(2, 2), (rows[1] as Control).size + Vector2(4, 4))
	var hit := BlockDrag.blocks_in_rect(vbox, r1)
	check(hit.size() == 1 and hit[0] == rows[1], "矩形只命中中间行")
	var r01 := Rect2((rows[0] as Control).global_position - Vector2(2, 2), Vector2(500, 200))
	check(BlockDrag.blocks_in_rect(vbox, r01).size() >= 2, "大矩形命中多行")

	# insert_run：整组保序插入
	var ta := PanelContainer.new()
	ta.name = "TempA"
	ta.custom_minimum_size = Vector2(100, 30)
	var tb := PanelContainer.new()
	tb.name = "TempB"
	tb.custom_minimum_size = Vector2(100, 30)
	BlockDrag.insert_run(vbox, [ta, tb], 1)
	await get_tree().process_frame
	var names_after_run := []
	for c in vbox.get_children():
		names_after_run.append(c.name)
	var expect_run := ["Row0", "TempA", "TempB", "Row1", "Row2"]
	var run_ok: bool = names_after_run.size() == expect_run.size()
	for i in names_after_run.size():
		if run_ok and str(names_after_run[i]) != str(expect_run[i]):
			run_ok = false
	check(run_ok, "insert_run 保序插入（实际 " + str(names_after_run) + "）")
	for tmp in [ta, tb]:
		if is_instance_valid(tmp):
			vbox.remove_child(tmp)
			tmp.free()
	await get_tree().process_frame
	check(vbox.get_child_count() == 3, "临时占位已移除")

	# insert_run 对“已有父节点”的节点（拖在 Dragging 下的真实积木）也能正确移入
	var bin := VBoxContainer.new()
	host.add_child(bin)
	var pa := PanelContainer.new()
	pa.name = "PreA"
	pa.custom_minimum_size = Vector2(100, 30)
	var pb := PanelContainer.new()
	pb.name = "PreB"
	pb.custom_minimum_size = Vector2(100, 30)
	bin.add_child(pa)
	bin.add_child(pb)
	BlockDrag.insert_run(vbox, [pa, pb], 2)   # 插入 Row2 之前
	await get_tree().process_frame
	var names_after_pre := []
	for c in vbox.get_children():
		names_after_pre.append(c.name)
	var expect_pre := ["Row0", "Row1", "PreA", "PreB", "Row2"]
	var pre_ok: bool = names_after_pre.size() == expect_pre.size()
	for i in names_after_pre.size():
		if pre_ok and str(names_after_pre[i]) != str(expect_pre[i]):
			pre_ok = false
	check(pre_ok, "insert_run 带父节点移入保序（实际 " + str(names_after_pre) + "）")
	check(pa.get_parent() == vbox and pb.get_parent() == vbox, "节点父级已切换为容器")
	for tmp in [pa, pb]:
		if is_instance_valid(tmp):
			vbox.remove_child(tmp)
			tmp.free()
	bin.queue_free()

	var empty_box := VBoxContainer.new()
	host.add_child(empty_box)
	check(BlockDrag.find_insert_slot(empty_box, 123.0) == 0, "空容器 -> 槽位 0")
	check(BlockDrag.find_nearest_block(empty_box, 123.0) == null, "空容器 -> 最近块 null")

	# ---------- BlockSelection 通用模型 ----------
	var sel = (load("res://Scripts/block_selection.gd") as GDScript).new()
	_bump_count = 0
	sel.changed.connect(_bump)
	sel.select_only(rows[0])
	sel.add(rows[2])
	check(sel.is_selected(rows[0]) and sel.is_selected(rows[2]) and sel.size() == 2, "选择模型 add/select_only")
	sel.toggle(rows[1])
	check(sel.size() == 3 and sel.is_selected(rows[1]), "选择模型 toggle")
	sel.remove(rows[1])
	sel.select_range(rows, 0, 2)
	check(sel.size() == 3 and sel.get_selected() == [rows[0], rows[1], rows[2]], "选择模型 range")
	sel.clear()
	check(sel.is_empty(), "选择模型 clear")
	check(_bump_count >= 5, "changed 信号有触发（count=" + str(_bump_count) + "）")

	var near := BlockDrag.find_nearest_block(vbox, centers[1])
	check(near == rows[1], "鼠标在次行中心 -> 最近块为次行")
	var near2 := BlockDrag.find_nearest_block(vbox, centers[1], rows[1])
	var d0 := absf(centers[0] - centers[1])
	var d2 := absf(centers[2] - centers[1])
	var expect: Node = rows[0] if d0 <= d2 else rows[2]
	check(near2 == expect, "排除次行后最近块符合距离比较")

	# ---------- commit_drop 落位 ----------
	var block_a: Node = (load("res://Blocks/Operations/set.tscn") as PackedScene).instantiate()
	dragging.add_child(block_a)
	block_a.set("origin_node", vbox)
	block_a.position = Vector2(400, 100)   # x 在删除区之外
	await get_tree().process_frame

	var sh_a := PanelContainer.new()
	sh_a.custom_minimum_size = Vector2(260, 40)
	vbox.add_child(sh_a)
	vbox.move_child(sh_a, 1)               # 预览槽位 = 1（插到 Row1 之前）
	block_a.shadow_block = sh_a
	await get_tree().process_frame

	block_a.commit_drop()
	await get_tree().process_frame
	await get_tree().process_frame

	var order_a := []
	for c in vbox.get_children():
		order_a.append(c.name)
	var expect_order := ["Row0", "Set", "Row1", "Row2"]
	var seq_ok: bool = order_a.size() == expect_order.size()
	for i in order_a.size():
		if seq_ok and str(order_a[i]) != str(expect_order[i]):
			seq_ok = false
	check(seq_ok, "按预览槽位落位且占位符已移除（实际 " + str(order_a) + "）")

	# ---------- commit_drop 删除 ----------
	var origin_x := vbox.global_position.x
	var block_b: Node = (load("res://Blocks/Operations/set.tscn") as PackedScene).instantiate()
	dragging.add_child(block_b)
	block_b.set("origin_node", vbox)
	block_b.position = Vector2(origin_x - 200, 100)   # 处于删除区（x < origin.x - 100）
	var sh_b := PanelContainer.new()
	sh_b.custom_minimum_size = Vector2(260, 40)
	vbox.add_child(sh_b)
	block_b.shadow_block = sh_b
	await get_tree().process_frame

	block_b.commit_drop()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(block_b), "拖入删除区的积木已被销毁")
	check(vbox.get_child_count() == 4, "删除后容器子节点回到 4")
	check(not is_instance_valid(sh_b), "删除时占位符一并回收")

	# ---------- 其余两处拖拽实现的脚本可加载冒烟（编译通过=有对应方法） ----------
	var shell: Node = (load("res://Blocks/block_shell.tscn") as PackedScene).instantiate()
	add_child(shell)
	var jump_ins: Node = (load("res://Blocks/Logics/jump.tscn") as PackedScene).instantiate()
	add_child(jump_ins)
	await get_tree().process_frame
	check(shell.has_method("add_block"), "block_shell 脚本编译并挂载（含 BlockDrag 复用）")
	check(jump_ins.has_method("set_jump_dictionary"), "jump 脚本编译并挂载（继承基类 BlockDrag）")

	if fails.is_empty():
		print("DRAGTEST PASS")
		get_tree().quit(0)
	else:
		print("DRAGTEST FAILED: ", fails.size(), " 项")
		get_tree().quit(1)
