extends "res://Scripts/logic_blocks.gd"
class_name CShapeBlocks
## “C 形积木”基类：可以在身体（Body）里容纳其它积木的积木。
##
## 设计约定（尽量简洁、可复用）：
##  - 身体容器：优先找唯一节点 %Body，其次 %UserBLocks（兼容已搭好骨架的 if.tscn）。
##    身体容器在 _ready 时加入组 "mvl_block_hosts"，使 LogicBlocks 拖拽可以把积木拖入/拖出身体。
##  - 导出（配合 Scripts/block_export.gd 的扁平化行号）：
##     子类可覆写以下“钩子”，默认都是“0 行、空行”，因此纯分组容器也不产生任何代码：
##      cshape_header_count() / cshape_footer_count()      —— 各自占几行（0 或 1）
##      cshape_header_line(skip_line) / cshape_footer_line() —— 行文本（须以 \n 结尾）
##      cshape_header_line 的 skip_line = 本积木结束后第一条指令的绝对行号，
##      便于“条件为假跳过身体”这类结构化指令无需标签。
##  - 身体里的子积木仍是普通 LogicBlocks；扁平导出会为整棵树计算绝对行号并统一换算 jump 目标。

const BlockExportScn := preload("res://Scripts/block_export.gd")


func body_container() -> VBoxContainer:
	for candidate in ["%Body", "%UserBLocks"]:
		var n := get_node_or_null(candidate)
		if n is VBoxContainer:
			return n
	return null


func cshape_body_children() -> Array:
	var b := body_container()
	if b == null:
		return []
	return b.get_children()


## 身体所有子积木将产生的指令行总数（递归计入嵌套 C 形积木）。
func cshape_body_count() -> int:
	var total := 0
	for c in cshape_body_children():
		total += BlockExportScn.count_lines_node(c)
	return total


# ---- 导出钩子（子类按需覆写，默认 0 行） ----

func cshape_header_count() -> int:
	return 0


func cshape_footer_count() -> int:
	return 0


func cshape_header_line(_skip_line: int) -> String:
	return ""


func cshape_footer_line() -> String:
	return ""


# ---- 身体容器注册 ----

## 每次进入场景树都注册宿主（reparent/拖放提交会让 C 形积木反复进出树；
## _ready 一生只触发一次，若只在 _ready 注册，拖放过一次的积木身体会永远
## 退出宿主组——真实 GUI 里“工作区 If 不接收拖入”的根因，见 tests/cshape_dup.gd）。
func _enter_tree() -> void:
	_register_body_host()


func _ready() -> void:
	super._ready()


func _exit_tree() -> void:
	var b := body_container()
	if b != null:
		b.remove_from_group("mvl_block_hosts")


func _register_body_host() -> void:
	var b := body_container()
	if b != null:
		b.add_to_group("mvl_block_hosts")


## 身体内容变化后的回调（拖入/拖出/删除子积木后由框架调用，默认无操作）。
func on_body_changed() -> void:
	pass


## C 形积木“可落位区域”的有效判定矩形（全局坐标）。
## 默认取整块积木的矩形（含头部/身体/底盖）：拖到 C 块任意位置都算“放入身体”，
## 使可落位区域与视觉一致、足够大；子类若想收窄可覆写。
func cshape_drop_rect() -> Rect2:
	var r := get_global_rect()
	if r.size.x > 0.0 and r.size.y > 0.0:
		return r
	var body_wrap: Node = get_node_or_null("VBoxContainer/Body")
	if body_wrap is Control:
		return (body_wrap as Control).get_global_rect()
	var b := body_container()
	if b != null:
		return (b as Control).get_global_rect()
	return Rect2()
