class_name PlacementPreview
extends RefCounted

## 落点占位块：拖拽时摆一组半透明幽灵视图，指示「现在放下会怎么样」。
## 视图只在目标集合变化时重建，之后每帧只更新位置；状态全在这里，画布只转发。

## 画布只认这三个方法（幽灵工厂 / 幽灵回收 / 布局查询）——不直接引用 EditorCanvas 类型，
## 免得与画布构成类名环：编辑器冷加载时全局类缓存还没建好，环上的 `PlacementPreview.new(...)`
## 会报 "Could not resolve external class member \"_init\""（AGENTS.md 记载的坑）。
var _canvas: Object
## 当前幽灵视图与各自的原始位置（按下标一一对应）。
var _views: Array[BlockView] = []
var _origins: Array[Vector2] = []
## 当前预览的节点集合（图上搬移）与块类型（调色板新建）。
var _ids: Array[int] = []
var _def_id: StringName = &""


## 引擎对象仍然活着（非 null 且未被 free）；视图层到处都是这个判断，收成一个词。
static func is_valid_object(value: Variant) -> bool:
	return value != null and is_instance_valid(value)


## 从父节点摘掉并 queue_free（先摘掉：queue_free 到帧末才生效，这一帧里它仍可能被遍历到）。
static func dismiss(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


func _init(canvas: Object) -> void:
	_canvas = canvas


## 摆出「这些已存在的块会落到哪」：相对布局不变，整体平移 [param offset]。
func show_existing(ids: Array[int], offset: Vector2) -> void:
	if ids != _ids or _def_id != &"":
		clear()
		_ids = ids.duplicate()
		_origins.clear()
		for id in ids:
			var node: LogicNode = _canvas.graph.get_node_by_id(id)
			if node == null:
				continue
			# make_ghost(source) 已带真实字段值、不吃鼠标，并按本体布局量过巢的尺寸
			var ghost: BlockView = _canvas.make_ghost(node.type_id, null, node)
			if ghost == null:
				continue
			ghost.modulate = Color(1, 1, 1, 0.5)
			_views.append(ghost)
			_origins.append(_canvas.layout.rect_of(id).position if _canvas.layout != null else Vector2.ZERO)
	for i in _views.size():
		if i < _origins.size() and is_valid_object(_views[i]):
			_views[i].position = _origins[i] + offset

## 摆出「从调色板拖出的新块会落到哪」：占位块就是要新建的那个块（默认值）。
func show_new(def: BlockDef, top_left: Vector2) -> void:
	if def == null:
		clear()
		return
	if _def_id != def.id:
		clear()
		_def_id = def.id
		var ghost: BlockView = _canvas.make_ghost(def.id)
		if ghost != null:
			ghost.modulate = Color(1, 1, 1, 0.5)
			_views.append(ghost)
	for view in _views:
		if is_valid_object(view):
			view.position = top_left

## 占位块的总高度（插在中间时用它给后面的块让位）。
func height() -> float:
	var total := 0.0
	for view in _views:
		if is_valid_object(view):
			total += maxf(view.metrics.size.y if view.metrics != null else view.size.y, 1.0)
	return total


func clear() -> void:
	for view in _views:
		if is_valid_object(view):
			_canvas.release_ghost(view)
	_views.clear()
	_origins.clear()
	_ids.clear()
	_def_id = &""


## 当前摆着的幽灵视图（仅供验证/调试；位置以本类为真相）。
func views() -> Array[BlockView]:
	return _views
