extends PanelContainer

class_name LogicBlocks ## 积木使用的类。

@export var is_given_block = false ## 是否是积木栏中的积木。此类积木被左键按下时会生成一个悬挂在鼠标上的副本。

@export var index_node: Label ## 显示行号的Label节点。
@export var input_node: Node2D ## 部分积木的快捷输入面板被实例化后的父节点。
@export var origin_node: VBoxContainer ## 一般是UserBlocks节点。
@export var dragging_node: Node2D ## 位于main.tscn场景的Dragging节点。

@export var label_value: String ## 严格锁定特征，随机生成时，是一个0~2^32之间的int整数。这个值在所有积木中应该独一无二，用于在生成节点树副本时确保jump的跳转目标是副本中的对应积木，而不是原节点树中的积木。

var moving = false ## 是否被抓起
var to_mouse_position ## 被抓起时相对鼠标的坐标
var shadow_block ## 积木阴影，用于预览松开鼠标时积木的位置


signal mouse_motion(pressed) ## 被鼠标按下时发出。pressed是鼠标对自己的动作。曾在积木的节点树结构优化前用于服务block_shell场景。现在没有被使用。


## 编译前进行准备工作。进行此行为时，所有积木的pre_compile都会被轮流调用。method参数是当前准备工作的步骤。
func pre_compile(method: int = 0):
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
			# 复制
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
				return false
			
			# 移动
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


func _init() -> void:
	if not label_value:
		summon_random_label_value()
	
	gui_input.connect(_on_gui_input)


## 为积木加载输入框和选择框的参数。value的第一项一般是积木的名字。
func load_value(value: Array):
	push_error("积木脚本尚未设置加载函数： " + self.name)


func _process(delta: float) -> void:
	logic_process()


func _ready():
	spawn_index_node()
	get_nodes()
	
	
## 生成积木阴影，一般在积木被拿起时生成，用于预览积木放下的位置。调用后，变量shadow_block是生成的积木阴影的引用。
func spawn_shadow():
	shadow_block = PanelContainer.new()
	shadow_block.custom_minimum_size = self.size
	origin_node.add_child(shadow_block)

	return shadow_block


## 一般的积木在_process()中进行的行为。
func logic_process():
	if index_node:
		index_node.text = str(self.get_index())
	
	# 被拿起
	if moving:
		global_position = get_global_mouse_position() + to_mouse_position
		
		# 计算阴影位置
		if shadow_block != null:
			if origin_node != null:
				var min_dis = INF
				var min_block = origin_node.get_child(0)
				
				for i in origin_node.get_children():
					if abs(i.global_position.y + i.size.y - get_global_mouse_position().y) < min_dis:
						min_block = i
						min_dis = abs(i.global_position.y + i.size.y - get_global_mouse_position().y)

				origin_node.move_child(shadow_block, min_block.get_index() )

		# 基于 shadow_block 进行预放置位置移动判定
		if self.global_position.x < origin_node.global_position.x - 100:
			modulate = Color(1 , 1 , 1 , 0.6)
		else:
			modulate = Color(1 , 1 , 1 , 1)
		
		# 当自身被松开
		if (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) == false and 
			Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) == false):
			if index_node:
				index_node.visible = true
			
			if self.global_position.x < origin_node.global_position.x - 100:
				if shadow_block != null:
					shadow_block.queue_free()
				self.queue_free()
			
			z_index = 0
			moving = false
			reparent(origin_node)
			
			origin_node.move_child(self , shadow_block.get_index())
				
			shadow_block.queue_free()


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
	node.position = Vector2(-25, self.size.y * 0.5)
	
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
