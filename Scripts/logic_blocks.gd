extends PanelContainer

class_name LogicBlocks ## 积木使用的类。

const BlockDrag := preload("res://Scripts/block_drag.gd")

## 行号列的水平偏移（Index 节点相对积木自身左侧的 x）：
## - 顶层积木：-25，落在工作区左侧的行号槽；
## - 嵌套在 C 形积木身体内的积木：-4，右缘紧贴内容列左侧，
##   使行号进入 C 块的“腰部内部”（若沿用 -25 会飘到 C 外框左侧之外）。
const INDEX_X_OUTER := -25.0
const INDEX_X_NESTED := 7.0

@export var is_given_block = false ## 是否是积木栏中的积木。此类积木被左键按下时会生成一个悬挂在鼠标上的副本。

@export var index_node: Label ## 显示行号的Label节点。
@export var input_node: Node2D ## 部分积木的快捷输入面板被实例化后的父节点。
@export var origin_node: VBoxContainer ## 一般是UserBlocks节点。
@export var dragging_node: Node2D ## 位于main.tscn场景的Dragging节点。

@export var label_value: String ## 严格锁定特征，随机生成时，是一个0~2^32之间的int整数。这个值在所有积木中应该独一无二，用于在生成节点树副本时确保jump的跳转目标是副本中的对应积木，而不是原节点树中的积木。

var export_line_map := {}    ## BlockExport 注入的“节点->绝对行号”映射（jump 用它换算跳线目标）
var _mvl_load_anchor := ""   ## 从工程文件加载时暂存的 jump 锚点（目标 label_value），重连后使用

var moving = false ## 是否被抓起
var to_mouse_position ## 被抓起时相对鼠标的坐标
var shadow_block ## 积木阴影，用于预览松开鼠标时积木的位置


signal mouse_motion(pressed) ## 被鼠标按下时发出。pressed是鼠标对自己的动作。曾在积木的节点树结构优化前用于服务block_shell场景。现在没有被使用。


## 编译前进行准备工作。进行此行为时，所有积木的pre_compile都会被轮流调用。method参数是当前准备工作的步骤。
func pre_compile(_method: int = 0):
	return false

## 编译导出。一般返回String类型参数，并在结尾加换行符。
func compile():
	push_error("积木脚本尚未设置导出函数： " + self.name)
	return ""

func save_block():
	pass

## 被鼠标按下时进行的操作。
func _on_gui_input(event: InputEvent):
	# 当被鼠标抓起
	if event is InputEventMouseButton:
		if not event.pressed:
			return false
		
		if not ((event.button_index == MOUSE_BUTTON_LEFT) or
			(event.button_index == MOUSE_BUTTON_RIGHT)):
			return false
		
		if moving:
			return false
		else:
			# 多选/批量拖动入口：询问最近的选择控制器（EditorSelection），返回 true 表示已接管本次按下
			if (not is_given_block) and event.button_index == MOUSE_BUTTON_LEFT:
				var ctrl: Node = _find_selection_controller()
				if ctrl != null and ctrl.editor_on_block_press(self):
					return false
			
			# 复制（从积木栏拿起）
			if is_given_block:
				emit_signal("mouse_motion",event.pressed)
			
				var block = self.duplicate()
				block.is_given_block = false
				block.to_mouse_position = global_position - get_global_mouse_position()
				block.moving = true
				block.origin_node = origin_node
				block.input_node = input_node
				block.index_node = null
				block.summon_random_label_value()
				
				dragging_node.add_child(block)
				
				block.spawn_shadow()
				block._register_own_cshape_hosts()
				return false
			
			# 移动（抓取列表中已有的积木）
			if event.button_index == MOUSE_BUTTON_LEFT:
				if index_node:
					index_node.visible = false
				
				z_index = 1
				emit_signal("mouse_motion",event.pressed)
				
				to_mouse_position = global_position - get_global_mouse_position()
				reparent(dragging_node)
				moving = true
				
				spawn_shadow()
			
			# 复制
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				emit_signal("mouse_motion",event.pressed)
				
				var block = self.duplicate()
				block.is_given_block = false
				block.to_mouse_position = global_position - get_global_mouse_position()
				block.moving = true
				block.origin_node = origin_node
				block.z_index = 1
				block.input_node = input_node
				block.summon_random_label_value()
				
				dragging_node.add_child(block)
				
				block.spawn_shadow()
				block._register_own_cshape_hosts()


func _init() -> void:
	if not label_value:
		summon_random_label_value()
	
	gui_input.connect(_on_gui_input)


## 为积木加载输入框和选择框的参数。value的第一项一般是积木的名字。
func load_value(_value: Array):
	push_error("积木脚本尚未设置加载函数： " + self.name)


func _process(_delta: float) -> void:
	logic_process()


func _ready():
	spawn_index_node()
	get_nodes()
	
	
## 生成积木阴影（可见的半透明占位条），一般在积木被拿起时生成，
## 用于预览积木放下的位置。调用后变量 shadow_block 是生成的占位符引用。
func spawn_shadow():
	shadow_block = PanelContainer.new()
	var w := self.size.x if self.size.x > 0.0 else 320.0
	var h := self.size.y if self.size.y > 0.0 else 40.0
	shadow_block.custom_minimum_size = Vector2(w, h)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.45, 0.7, 1.0, 0.16)
	style.border_color = Color(0.5, 0.75, 1.0, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	shadow_block.add_theme_stylebox_override("panel", style)
	shadow_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	origin_node.add_child(shadow_block)

	return shadow_block


## 一般的积木在_process()中进行的行为。
func logic_process():
	if index_node:
		index_node.text = str(self.get_index())
		var ix := index_node.get_parent() as Node2D
		if ix != null:
			# 拖动把积木在工作区 <-> C 形身体之间移动时，行号列要跟着层级切换
			var tx := _current_index_x()
			if not is_equal_approx(ix.position.x, tx):
				ix.position.x = tx
	
	# 被拿起
	if moving:
		global_position = get_global_mouse_position() + to_mouse_position
		_update_shadow_preview()
		
		# 拖到左侧（删除区）时半透明提示
		if self.global_position.x < origin_node.global_position.x - 100:
			modulate = Color(1 , 1 , 1 , 0.6)
		else:
			modulate = Color(1 , 1 , 1 , 1)
		
		# 松开鼠标：统一提交“落位 / 取消删除”（判定收敛到 commit_drop 单点）
		if (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) == false and 
			Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) == false):
			commit_drop()


## 拖拽中更新占位预览。仅在目标槽位变化时才移动占位符，
## 避免每帧全量扫描后仍做一次 move_child 引发的整列重排。
## 目标容器跟随鼠标：默认是 origin_node（外列），当鼠标位于某个
## C 形积木的身体（组 "mvl_block_hosts"）内时切换为该身体，从而支持嵌套。
func _update_shadow_preview():
	if origin_node == null:
		return
	if shadow_block == null or not is_instance_valid(shadow_block):
		shadow_block = null
		return
	_refresh_drop_hosts()
	var host := _pick_drop_host()
	if host == null:
		host = origin_node
	if shadow_block.get_parent() != host:
		var old = shadow_block.get_parent()
		if old != null:
			old.remove_child(shadow_block)
		host.add_child(shadow_block)
	var slot := BlockDrag.find_insert_slot(host, get_global_mouse_position().y, shadow_block)
	if slot != shadow_block.get_index():
		host.move_child(shadow_block, slot)


## 拖拽前重建宿主注册表：遍历当前编辑器下所有积木（含嵌套），
## 确保每个 C 形积木的身体容器都在 mvl_block_hosts 组里（防止注册因副本/时序丢失）。
func _refresh_drop_hosts() -> void:
	var wb := _find_user_blocks()
	if wb == null:
		return
	for child in wb.get_children():
		if child is Control:
			_ensure_cshape_hosts(child)


## 找当前工作区容器（UserBlocks）。用“沿父链找名字为 UserBlocks 的 VBox”
## 而不是 %唯一名查找——% 解析依赖 owner 场景，跨场景/运行时动态节点时不可靠。
func _find_user_blocks() -> Node:
	# 注意：遍历变量必须显式声明为 Node——若写成 `var n := self`，静态类型是
	# LogicBlocks（PanelContainer 分支），`n is VBoxContainer` 会被分析器判为
	# “静态不可能”的解析错误，进而使整个基类脚本编译失败，连锁导致所有
	# 按路径继承的积木内嵌脚本报 “Could not resolve class 'LogicBlocks'”。
	var n: Node = self
	while n != null:
		if n.name == "UserBlocks" and n is VBoxContainer:
			return n
		n = n.get_parent()
	var er := _find_selection_controller()
	if er != null:
		return er.get_node_or_null("%UserBlocks")
	return null


## 直接注册自身（及可能嵌套于自身身体的 C 块）的落位宿主；
## 用于“积木栏拖出副本”这类可能错过 _ready 注册的路径。
func _register_own_cshape_hosts() -> void:
	_ensure_cshape_hosts(self)


func _ensure_cshape_hosts(block: Node) -> void:
	if block.has_method("cshape_body_children"):
		var body: Node = block.call("body_container")
		if body is Control:
			(body as Control).add_to_group("mvl_block_hosts")
		for inner in block.cshape_body_children():
			if inner is Control:
				_ensure_cshape_hosts(inner)


## 选择当前鼠标下的落位宿主：取命中的、面积最小的（最深）可见宿主容器；
## 排除自身及其后代的容器（不能把积木拖进自己身体里）。
func _pick_drop_host() -> Node:
	if origin_node == null:
		return null
	var mouse := get_global_mouse_position()
	var best: Node = null
	var best_area := INF
	for c in get_tree().get_nodes_in_group("mvl_block_hosts"):
		if not (c is Control):
			continue
		var ctrl := c as Control
		if not ctrl.is_visible_in_tree():
			continue
		if self.is_ancestor_of(c):
			continue
		if _in_given_palette(c):
			continue
		# 用“有效判定矩形”命中：C 形积木可让整个身体面板区域都可落位
		var r := _host_effective_rect(c)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if r.has_point(mouse):
			var area := r.size.x * r.size.y
			if area < best_area:
				best_area = area
				best = c
	return best


## 宿主容器的有效判定矩形：若其所属 C 形积木声明了 cshape_drop_rect() 则采用之，
## 否则退回容器自身的全局矩形。
func _host_effective_rect(c: Node) -> Rect2:
	var n := c
	while n != null:
		if n.has_method("cshape_drop_rect"):
			var r: Rect2 = n.cshape_drop_rect()
			if r.size.x > 0.0 and r.size.y > 0.0:
				return r
			break
		n = n.get_parent()
	return (c as Control).get_global_rect()


## 宿主是否位于“积木栏（给定积木区）”内：其所属积木带 is_given_block=true。
func _in_given_palette(c: Node) -> bool:
	var n := c
	while n != null:
		var g = n.get("is_given_block")
		if g == true:
			return true
		if n.has_method("editor_on_block_press"):
			return false
		n = n.get_parent()
	return false


## 松开鼠标时的统一提交：
## - 拖到左侧删除区 -> 取消（回收占位符并销毁自己）；
## - 否则按“占位符当前索引 == 松开时预览槽位”落位；
## 落位后显式通知容器刷新行号与跳线，不再依赖 sort_children 隐式触发。
func commit_drop():
	if index_node:
		index_node.visible = true
	z_index = 0
	moving = false
	modulate = Color(1 , 1 , 1 , 1)
	
	# 删除区判定（相对自己所属的最外层列表）
	if origin_node == null or self.global_position.x < origin_node.global_position.x - 100:
		_discard_shadow()
		queue_free()
		return

	# 落位宿主：占位符此刻所在容器即最终宿主（预览与落位一致）
	var host: Node = origin_node
	if shadow_block != null and is_instance_valid(shadow_block):
		host = shadow_block.get_parent()

	# 落位：占位符的当前索引即预览槽位
	var slot := 0
	if shadow_block != null and is_instance_valid(shadow_block):
		slot = shadow_block.get_index()
		var p = shadow_block.get_parent()
		if p != null:
			p.remove_child(shadow_block)
		shadow_block.queue_free()
	shadow_block = null

	reparent(host)
	host.move_child(self , slot)
	origin_node = host   # 以后从这个宿主出发拖拽/删除判定都一致

	# 行号与跳线刷新；身体宿主的变化顺带通知所属 C 形积木
	if host.has_method("_on_block_moved"):
		host._on_block_moved()
	_notify_host_cshape(host)


## 移除占位符（松手取消时用）。
func _discard_shadow():
	if shadow_block != null and is_instance_valid(shadow_block):
		shadow_block.queue_free()
	shadow_block = null


## 向上寻找宿主所属的 C 形积木并通知其身体已变化。
func _notify_host_cshape(host: Node) -> void:
	var n := host
	while n != null:
		if n.has_method("on_body_changed"):
			n.on_body_changed()
			return
		n = n.get_parent()


## 查找最近的选择控制器（沿父链向上找带 editor_on_block_press 的节点）。
func _find_selection_controller() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("editor_on_block_press"):
			return n
		n = n.get_parent()
	return null


## 整组拖动时隐藏行号标签。
func _hide_drag_index() -> void:
	if index_node:
		index_node.visible = false


## 整组落位后恢复行号标签。
func _restore_drag_index() -> void:
	if index_node:
		index_node.visible = not is_given_block


## 当前应使用的行号水平偏移：父链上存在 C 形积木（cshape_body_children）即视为嵌套。
func _is_nested_in_cshape() -> bool:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("cshape_body_children"):
			return true
		n = n.get_parent()
	return false


func _current_index_x() -> float:
	return INDEX_X_NESTED if _is_nested_in_cshape() else INDEX_X_OUTER


## 获取部分必需节点的引用。
func get_nodes():
	dragging_node = get_tree().get_current_scene().get_node("Dragging")


## 生成行号节点。
func spawn_index_node():
	for i in self.get_children():
		if i.get_child_count() <= 0:
			continue
		
		if i.get_children()[0].name == "IndexLabel":
			i.queue_free()
	
	var node = Node2D.new()
	self.add_child(node)
	node.name = "Index"
	node.position = Vector2(_current_index_x(), self.size.y * 0.5)
	
	var index_node_i = load("res://Scenes/index_label.tscn")
	index_node = index_node_i.instantiate()
	node.add_child(index_node)
	
	if (not is_given_block) and (get_parent() is VBoxContainer):
		index_node.visible = true


## UserBlocks重新排列自己的子节点时调用。一般用于Jump刷新自己的跳转值。
func _on_any_block_moved():
	pass


## 调用时，会生成随机的label_value值。
func summon_random_label_value():
	label_value = str(randi())
