extends Node
## C 形积木 + 扁平化导出的 headless 测试：
##   godot --headless --path <仓库根> res://tests/exporttest.tscn
## 退出码 0 = 通过。

const BlockExportScn := preload("res://Scripts/block_export.gd")

var fails: Array = []
var machine := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		fails.append(msg)
		print("  [FAIL] ", msg)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var root := VBoxContainer.new()
	add_child(root)
	root.position = Vector2(0, 0)

	# ---- 构造：If { setA ; jump->setB ; setB } , setC ----
	var if_node: Node = (load("res://Blocks/Logics/if.tscn") as PackedScene).instantiate()
	if_node.get_node("%op1").selected = 0    # equal
	if_node.get_node("%a").text = "x"
	if_node.get_node("%b").text = "false"
	root.add_child(if_node)

	var body: Node = if_node.call("body_container")
	check(body != null, "if 积木有身体容器")
	check(body.is_in_group("mvl_block_hosts"), "身体容器已注册为落位宿主")
	# 内部装饰面板必须是 PASS，否则点击会被吞掉导致 if 无法拖动
	var head: Node = if_node.get_node_or_null("VBoxContainer/Head")
	var tail: Node = if_node.get_node_or_null("VBoxContainer/Tail")
	check(head != null and head.mouse_filter == Control.MOUSE_FILTER_PASS, "Head 鼠标过滤为 PASS（可拖）")
	check(tail != null and tail.mouse_filter == Control.MOUSE_FILTER_PASS, "Tail 鼠标过滤为 PASS（可拖）")
	if body != null:
		check(body.mouse_filter == Control.MOUSE_FILTER_PASS, "Body 鼠标过滤为 PASS（可拖）")

	var set_a: Node = (load("res://Blocks/Operations/set.tscn") as PackedScene).instantiate()
	set_a.get_node("%a").text = "a1"
	set_a.get_node("%b").text = "v1"
	set_a.set("label_value", "SA")
	var jump_inner: Node = (load("res://Blocks/Logics/jump.tscn") as PackedScene).instantiate()
	jump_inner.get_node("%op1").selected = 2   # lessThan
	jump_inner.get_node("%a").text = "x"
	jump_inner.get_node("%b").text = "false"
	jump_inner.set("label_value", "SJ")
	var set_b: Node = (load("res://Blocks/Operations/set.tscn") as PackedScene).instantiate()
	set_b.get_node("%a").text = "b2"
	set_b.get_node("%b").text = "v2"
	set_b.set("label_value", "SB")
	body.add_child(set_a)
	body.add_child(jump_inner)
	body.add_child(set_b)
	jump_inner.set("jump_to", set_b)          # 指向身体内另一块积木

	var set_c: Node = (load("res://Blocks/Operations/set.tscn") as PackedScene).instantiate()
	set_c.get_node("%a").text = "c3"
	set_c.get_node("%b").text = "v3"
	set_c.set("label_value", "SC")
	root.add_child(set_c)

	await get_tree().process_frame
	await get_tree().process_frame

	var text: String = BlockExportScn.export_text(root)
	var lines := text.split("\n", false)
	check(lines.size() == 5, "扁平化共 5 行（实际 " + str(lines.size()) + "）")
	check(lines[0] == "jump 4 notEqual x false", "if 头：取反条件跳到身体结束后的行 4（实际 '" + lines[0] + "'）")
	check(lines[1] == "set a1 v1", "身体内第 1 条：set a1 v1")
	check(lines[2] == "jump 3 lessThan x false", "身体内 jump 目标换算为绝对行号 3（实际 '" + lines[2] + "'）")
	check(lines[3] == "set b2 v2", "身体内第 2 条：set b2 v2")
	check(lines[4] == "set c3 v3", "If 之后的积木从行 4 继续")

	# ---- always 条件（无条件执行，无头行）与空身体（0 行） ----
	var if2: Node = (load("res://Blocks/Logics/if.tscn") as PackedScene).instantiate()
	var aux := VBoxContainer.new()
	add_child(aux)
	aux.add_child(if2)
	if2.get_node("%op1").selected = 7        # always
	check(BlockExportScn.count_lines_node(if2) == 0, "空身体 -> if 贡献 0 行")
	var body2: Node = if2.call("body_container")
	var set_d: Node = (load("res://Blocks/Operations/set.tscn") as PackedScene).instantiate()
	set_d.get_node("%a").text = "d"
	set_d.get_node("%b").text = "1"
	body2.add_child(set_d)
	await get_tree().process_frame
	check(BlockExportScn.count_lines_node(if2) == 1, "always + 1 子积木 -> 只内联 1 行（无头）")
	var t2: String = BlockExportScn.export_text(aux)
	check(t2 == "set d 1\n", "always 身体被直接内联（实际 '" + t2 + "'）")

	# ---- C 形积木的 UI 控件仍可被通用采集/施加 ----
	var ui := {}
	# 复用 ProjectIO 采集逻辑（通过预加载脚本调用静态方法）
	var pio: GDScript = load("res://Scripts/project_io.gd")
	# 直接验证：if 头部的 LineEdit 通过 capture 后可被施加
	var data: Dictionary = pio.capture_project(root)
	var entry0: Dictionary = data["blocks"][0]
	check(str(entry0["scene"]).ends_with("if.tscn"), "if 作为顶层块被采集")
	check(entry0.has("children") and (entry0["children"] as Array).size() == 3,
		"if 身体 3 个子积木进入 children")

	# 嵌套工程 apply 到空容器后再导出，应与原导出一致（文件往返对嵌套也成立）
	var fresh := VBoxContainer.new()
	add_child(fresh)
	var errs: Array = pio.apply_project(fresh, data, null)
	check(errs.is_empty(), "嵌套工程 apply 无错误（errors=" + str(errs) + "）")
	await get_tree().process_frame
	var text3: String = BlockExportScn.export_text(fresh)
	check(text3 == text, "嵌套 apply 后导出与原导出一致")

	if fails.is_empty():
		print("EXPORTTEST PASS")
		get_tree().quit(0)
	else:
		print("EXPORTTEST FAILED: ", fails.size(), " 项")
		get_tree().quit(1)
