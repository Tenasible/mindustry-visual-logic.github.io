extends Node
## MVL 工程文件（ProjectIO）回环测试 —— 无头运行：
##   godot --headless --path <仓库根> res://tests/roundtrip.tscn
## 退出码 0 = 通过；1 = 有失败项。

var fails: Array = []
var machine := 0   # 模拟 main 提供给 editor 页的 machine 字段
const ProjectIOScn := preload("res://Scripts/project_io.gd")

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		fails.append(msg)
		print("  [FAIL] ", msg)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# 装载真实编辑器页（提供 current_scene.machine 与 Dragging，模拟 main 环境）
	var ed: Control = (load("res://Scenes/editor.tscn") as PackedScene).instantiate()
	add_child(ed)
	await get_tree().process_frame
	await get_tree().process_frame

	# 模拟 main：把拖拽层交给编辑器（顺带装配 SelectionHost 选择控制器）
	ed.reset_nodes(get_node("Dragging"))
	await get_tree().process_frame
	var host: Node = ed.get_node_or_null("SelectionHost")
	check(host != null, "editor 场景含 SelectionHost")
	if host != null:
		check(host.get("editor") == ed, "SelectionHost 已装配 editor")
		check(host.get("overlay") != null, "SelectionHost 已创建高亮覆盖层")

	var ub: Node = ed.get_node("%UserBlocks")
	var easy: Node = ed.get_node("%EasyInput")
	check(ub.get_child_count() == 0, "新编辑器 UserBlocks 为空")

	# ---- 手工构造一份工程（模拟用户在界面上拼好的积木） ----
	var set_block := _make(ub, "res://Blocks/Operations/set.tscn", "LBL_SET")
	set_block.get_node("%a").text = "result"
	set_block.get_node("%b").text = "@counter"

	var expr := _make(ub, "res://Blocks/Logics/expression.tscn", "LBL_EXPR")
	expr.get_node("%a").text = "注释 带空格 Hello world 世界"

	var label_block := _make(ub, "res://Blocks/Logics/jump_label.tscn", "LBL_LOOP")
	label_block.get_node("%a").text = "loop"

	var draw := _make(ub, "res://Blocks/PutInOut/draw.tscn", "LBL_DRAW")
	draw.get_node("%op1").selected = 2      # col
	draw.get_node("%a").text = "255"
	draw.get_node("%b").text = "128"
	draw.get_node("%c").text = "64"
	draw.get_node("%d").text = "0.5"
	draw.get_node("%e").text = "drawing"
	draw.get_node("%f").text = "第7参数-必须保留"   # 剪贴板往返会丢（旧 load_value bug）

	var print_block := _make(ub, "res://Blocks/PutInOut/print.tscn", "LBL_PRINT")
	print_block.get_node("%a").text = "你好 MVL"
	print_block.get_node("%Button").button_pressed = true   # 引号开关（剪贴板往返丢失）

	var set2 := _make(ub, "res://Blocks/Operations/set.tscn", "LBL_TARGET")   # jump 跳转目标
	set2.get_node("%a").text = "t"
	set2.get_node("%b").text = "1"

	var jump := _make(ub, "res://Blocks/Logics/jump.tscn", "LBL_JUMP")
	jump.get_node("%op1").selected = 3
	jump.get_node("%a").text = "@time"
	jump.get_node("%b").text = ">= 60"
	jump.set("jump_to", set2)
	# jump 的 %c 显示行号：加载后会被重连阶段修正为最终行号，因此初始给“目标当前行号”
	#（保存的是目标锚点，行号随插入/合并变化也能正确重连）

	var configure := _make(ub, "res://Blocks/configure.tscn", "LBL_CONF")
	var conf_rows: Node = configure.get_node("%Configures")
	# 增加一行，形成 2 行；改名避免自动重命名歧义
	var extra_row: Node = (load("res://Scenes/config_setting.tscn") as PackedScene).instantiate()
	extra_row.name = "MyRow"
	conf_rows.add_child(extra_row)
	var row0: Node = conf_rows.get_child(0)
	row0.name = "RowA"
	row0.get_node("HBoxContainer/ConfigSelect").selected = 0
	row0.get_node("HBoxContainer/Configs/MaxFPS/HBoxContainer/LineEdit").text = "90"
	var row1: Node = conf_rows.get_child(1)
	row1.name = "RowB"
	row1.get_node("HBoxContainer/ConfigSelect").selected = 2
	row1.get_node("HBoxContainer/Configs/UIScale/HBoxContainer/LineEdit").text = "1.5"

	# 让 jump 的 %c 显示其目标（set2）当前行号，与重连后的规范化结果一致
	jump.get_node("%c").text = str(set2.get_index())

	await get_tree().process_frame

	var order: Array = [set_block, expr, label_block, draw, print_block, set2, jump, configure]

	# ---- 保存（capture） ----
	var data: Dictionary = ProjectIOScn.capture_project(ub)
	check(data.get("format", "") == "mvl-project", "capture 格式标记正确")
	var blks: Array = data["blocks"]
	check(blks.size() == order.size(), "capture 块数量 = " + str(order.size()))
	for i in range(blks.size()):
		check(str(blks[i]["scene"]).ends_with(order[i].scene_file_path.get_file()),
			"顺序保留: index " + str(i) + " -> " + str(blks[i]["scene"]))
	# jump 锚点
	var jump_entry: Dictionary = {}
	for b in blks:
		if str(b["scene"]).ends_with("jump.tscn"):
			jump_entry = b
	check(str(jump_entry["jump"]["anchor"]) == "LBL_TARGET", "jump 锚点 = 目标 label")
	check(str(jump_entry["label"]) == "LBL_JUMP", "jump label 保留")
	# configure 行
	var conf_entry: Dictionary = {}
	for b in blks:
		if str(b["scene"]).ends_with("configure.tscn"):
			conf_entry = b
	var row_keys: Array = []
	for p in conf_entry["ui"]:
		if str(p).begins_with("HBoxContainer/Configures/"):
			row_keys.append(str(p).split("/")[2])
	check(row_keys.has("RowA") and row_keys.has("RowB"), "configure 两行都被记录")

	# ---- 清空并重新加载 ----
	for c in ub.get_children():
		ub.remove_child(c)
		c.free()
	await get_tree().process_frame

	var errors: Array = ProjectIOScn.apply_project(ub, data, easy)
	check(errors.is_empty(), "apply 无错误（errors=" + str(errors) + ")")
	await get_tree().process_frame

	var data2: Dictionary = ProjectIOScn.capture_project(ub)
	var blks2: Array = data2["blocks"]
	check(blks2.size() == blks.size(), "重新 capture 块数量一致")
	for i in range(blks.size()):
		var a: Dictionary = blks[i]
		var b: Dictionary = blks2[i]
		check(str(a["scene"]) == str(b["scene"]), "scene 一致 #" + str(i))
		check(str(a["label"]) == str(b["label"]), "label 一致 #" + str(i))
		check(a["ui"] == b["ui"], "ui 状态一致 #" + str(i))
	# jump 重连正确性：指向的节点是新实例且 label 正确、行号文本已修正
	var jump_node: Node = null
	var target_node: Node = null
	for c in ub.get_children():
		if str(c.scene_file_path).ends_with("jump.tscn"):
			jump_node = c
		if str(c.scene_file_path).ends_with("set.tscn") and c.get("label_value") == "LBL_TARGET":
			target_node = c
	check(jump_node != null and target_node != null, "jump/目标都在新容器中")
	if jump_node != null and target_node != null:
		var jt: Node = jump_node.get("jump_to")
		check(is_instance_valid(jt) and jt == target_node, "jump_to 指向新实例的目标积木")
		check(str(jump_node.get_node("%c").text) == str(target_node.get_index()), "jump %c 行号已修正为最终行号")
	# configure 行重建
	var conf_node: Node = null
	for c in ub.get_children():
		if str(c.scene_file_path).ends_with("configure.tscn"):
			conf_node = c
	if conf_node != null:
		var rows: Node = conf_node.get_node("%Configures")
		check(rows.get_child_count() == 2, "configure 行数重建 = 2")
		var names: Array = []
		for r in rows.get_children():
			names.append(r.name)
		check(names.has("RowA") and names.has("RowB"), "configure 行名重建: " + str(names))

	# ---- 模拟框选路径（不依赖真实鼠标输入；曾因 to_local 缺失而崩溃） ----
	host._band_start = Vector2(0, 0)
	host._band_active = true
	host._update_band()
	host._finish_band()
	check(true, "框选 update/finish 不崩溃")
	var lr: Rect2 = host._to_local_rect(Rect2(Vector2(10, 20), Vector2(50, 60)))
	check(lr.size == Vector2(50, 60), "本地坐标换算保持尺寸（lr=" + str(lr) + "）")

	# ---- 文件往返 ----
	# 用系统临时目录而非 user://：受限/重定向环境下 user:// 可能不可写，会误报失败
	var tmp_path := _os_tmp_path("_mvl_roundtrip_test.mvlp")
	var err: Error = ProjectIOScn.save_to_file(tmp_path, data)
	check(err == OK, "save_to_file OK")
	var file_data: Dictionary = ProjectIOScn.load_from_file(tmp_path)
	check(file_data.size() > 0 and file_data.get("format", "") == "mvl-project", "load_from_file OK")
	if file_data.size() > 0:
		var data3: Dictionary = ProjectIOScn.capture_project(ub)
		check(data3 == data, "capture == 源数据（文件往返无损）")
	DirAccess.remove_absolute(tmp_path)

	# ---- 整组拖动模拟（reparent 进 Dragging -> 松手保序落位；曾因 add_child 报错） ----
	var ghost := Control.new()
	ghost.position = Vector2(-1200, 0)          # 使鼠标(0,0)位于列表内部而非删除区
	add_child(ghost)
	var gv := VBoxContainer.new()
	gv.position = Vector2(-1200, 0)
	ghost.add_child(gv)
	var ga := PanelContainer.new()
	ga.name = "GA"
	ga.custom_minimum_size = Vector2(200, 40)
	var gb := PanelContainer.new()
	gb.name = "GB"
	gb.custom_minimum_size = Vector2(200, 40)
	var gc := PanelContainer.new()
	gc.name = "GC"
	gc.custom_minimum_size = Vector2(200, 40)
	gv.add_child(ga)
	gv.add_child(gb)
	gv.add_child(gc)
	await get_tree().process_frame
	await get_tree().process_frame

	host.container = gv                       # 临时把控制器指向合成容器
	host.dragging_node = get_node("Dragging")
	host.selection.clear()
	host.selection.select_only(ga)
	host.selection.add(gb)
	var consumed: bool = host.editor_on_block_press(ga)
	check(consumed, "多选按下已选积木 -> 控制器接管（组拖动开始）")
	check(ga.get_parent() == host.dragging_node and gb.get_parent() == host.dragging_node,
		"整组已 reparent 到 Dragging（无 add_child 报错）")
	check(gv.get_child_count() == 3, "容器内剩下占位 x2 + 未选块 x1")
	host._finish_group()                       # 鼠标(0,0) -> 槽位 0（列表顶部）
	await get_tree().process_frame
	await get_tree().process_frame
	var gnames := []
	for c in gv.get_children():
		gnames.append(str(c.name))
	check(gnames == ["GA", "GB", "GC"], "整组保序落位到列表顶部（实际 " + str(gnames) + "）")
	check(ga.get_parent() == gv and gb.get_parent() == gv, "整组落位后父节点恢复为容器")
	host.container = ub                        # 还原
	host.selection.clear()
	ghost.free()

	# ---- C 形身体作为落位宿主：空身体中央应命中身体内部容器 ----
	var ifblk: Node = (load("res://Blocks/Logics/if.tscn") as PackedScene).instantiate()
	ub.add_child(ifblk)
	ifblk.set("origin_node", ub)
	await get_tree().process_frame
	await get_tree().process_frame
	var ifbody: Node = ifblk.call("body_container")
	check(ifbody != null and ifbody.is_in_group("mvl_block_hosts"), "if 身体容器已注册为宿主")
	var br := (ifbody as Control).get_global_rect()
	# 空身体最小高度是产品外观参数（if.tscn %UserBLocks custom_minimum_size，
	# 用户可按需调整以改善空闲外观）——断言跟随节点自身的最小尺寸，而非写死 80
	var min_h: float = (ifbody as Control).custom_minimum_size.y
	check(br.size.y >= min_h - 1.0,
		"空身体高度满足其最小尺寸（min=" + str(min_h) + " y=" + str(br.size.y) + "）")
	var bd: GDScript = load("res://Scripts/block_drag.gd")
	var cands: Array = []
	for h in get_tree().get_nodes_in_group("mvl_block_hosts"):
		if (h is Control) and (h as Control).is_visible_in_tree():
			cands.append(h)
	var picked: Node = bd.smallest_host_at(cands, br.get_center())
	check(picked == ifbody, "空身体中央命中身体内部容器（picked=" + str(picked) + "）")
	ifblk.queue_free()

	if fails.is_empty():
		print("ROUNDTRIP PASS")
		get_tree().quit(0)
	else:
		print("ROUNDTRIP FAILED: ", fails.size(), " 项")
		get_tree().quit(1)


func _os_tmp_path(fname: String) -> String:
	var t := OS.get_environment("TEMP")
	if t == "":
		t = "/tmp"
	return t + "/" + fname


func _make(container: Node, scene_path: String, label: String) -> Node:
	var scene: PackedScene = load(scene_path)
	var block: Node = scene.instantiate()
	container.add_child(block)
	block.set("origin_node", container)
	block.set("label_value", label)
	return block
