extends Node
## C 形积木两种来源的身体容器可寻性与宿主注册（headless）：
##   1) instantiate() 正常实例；
##   2) duplicate() 副本（对应“从积木栏拿起 C 形积木副本放进工作区”的真实路径，
##      副本没有 owner 场景链，%唯一名查找可能失效）。
## 输出 CSHAPEDUP PASS 且退出码 0 即通过。

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

	var ub := VBoxContainer.new()
	ub.name = "UserBlocks"
	add_child(ub)
	await get_tree().process_frame

	# 1) 正常实例
	var inst: Node = (load("res://Blocks/Logics/if.tscn") as PackedScene).instantiate()
	ub.add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var ib: Node = inst.call("body_container")
	check(ib != null, "instantiate：body_container 可找到（ib=" + str(ib) + "）")
	check(ib != null and ib.is_in_group("mvl_block_hosts"), "instantiate：身体已注册为宿主")

	# 2) duplicate 副本（模拟从积木栏拿起）
	var src: Node = (load("res://Blocks/Logics/if.tscn") as PackedScene).instantiate()
	ub.add_child(src)
	await get_tree().process_frame
	var dup: Node = src.duplicate()
	dup.name = "IfDup"
	ub.add_child(dup)
	await get_tree().process_frame
	await get_tree().process_frame
	var db: Node = dup.call("body_container")
	check(db != null, "duplicate：body_container 可找到（db=" + str(db) + "）")
	check(db != null and db.is_in_group("mvl_block_hosts"), "duplicate：身体已注册为宿主")

	# 3) reparent 往返（模拟 C 形积木自己被抓取拖放一次：进 Dragging 再 commit 回容器）。
	#    _exit_tree 会把身体移出宿主组，而 _ready 只触发一次——这是真实 GUI 里
	#    “工作区 If 身体不在宿主组”的核心疑点。
	var drag_layer := Node2D.new()
	drag_layer.name = "Dragging"
	add_child(drag_layer)
	await get_tree().process_frame
	var round: Node = (load("res://Blocks/Logics/if.tscn") as PackedScene).instantiate()
	ub.add_child(round)
	await get_tree().process_frame
	await get_tree().process_frame
	check(round.call("body_container") != null
		and round.call("body_container").is_in_group("mvl_block_hosts"),
		"reparent 前：身体已注册为宿主")
	round.reparent(drag_layer)
	await get_tree().process_frame
	round.reparent(ub)
	await get_tree().process_frame
	await get_tree().process_frame
	var rb: Node = round.call("body_container")
	check(rb != null, "reparent 后：body_container 仍可找到")
	check(rb != null and rb.is_in_group("mvl_block_hosts"),
		"reparent 往返后：身体仍在宿主组（真实拖放路径）")

	# 4) 副本同样经历 reparent 往返
	var dup2: Node = (load("res://Blocks/Logics/if.tscn") as PackedScene).instantiate().duplicate()
	dup2.name = "IfDup2"
	ub.add_child(dup2)
	await get_tree().process_frame
	dup2.reparent(drag_layer)
	await get_tree().process_frame
	dup2.reparent(ub)
	await get_tree().process_frame
	await get_tree().process_frame
	var db2: Node = dup2.call("body_container")
	check(db2 != null and db2.is_in_group("mvl_block_hosts"),
		"duplicate + reparent 往返后：身体仍在宿主组")

	if fails.is_empty():
		print("CSHAPEDUP PASS")
		get_tree().quit(0)
	else:
		print("CSHAPEDUP FAILED: ", fails.size(), " 项")
		get_tree().quit(1)
