class_name DragController
extends CanvasPointerSession

## 拖拽会话：调色板出块、画布内搬移、吸附提示与落地。
##
## 骨架在 [CanvasPointerSession]（与 [LinkController] 共用），本类只管「搬什么、落到哪」；
## 它挂在标签页根下（不在 SubViewport 里），拖到画布外也收得到事件：画布外 = 取消，
## 左侧块列表 = 删除（一次撤销，拿起的整串一起删）。

signal drag_started()
signal drag_finished()

## 吸附判定半径（像素，世界坐标）。
@export var capture_radius: float = 22.0


## 非空表示「从图上搬移」，为空表示「从调色板新建」。
var _source_node: LogicNode = null
var _type_id: StringName = &""
var _type_def: BlockDef = null
var _ghost: BlockView = null
## 鼠标相对块左上角的偏移（屏幕上按下时的位置）。
var _offset: Vector2 = Vector2.ZERO
## 搬移时：子树各节点 → 拖拽开始时的位置。
var _subtree_positions: Dictionary[int, Vector2] = {}
var _exclude: Dictionary[int, bool] = {}
var _target: Dictionary = {}
## 本次搬移的块：拿起的那块 + 它后面的所有块（同容器的后续兄弟）。
var _carried: Array[int] = []
## 非空表示这次是「多选整组拖动」：要搬的顶层块 id（按选中时的视觉顺序）。
## 它与 _carried 互斥：组拖是任意集合，不走「后面那串」的链式语义。
var _group_ids: Array[int] = []
## 非零表示这次是「右键拖拽复制」：源子树根的节点 id。
var _copy_source_id: int = 0
## 复制拖拽时源子树的全部节点：落点占位与让位都按它们的布局算。
var _copy_ids: Array[int] = []
## 这次拖拽是用哪个键起的：松手落地只认它（右键拖拽就得右键松手）。
var _button: MouseButton = MOUSE_BUTTON_LEFT
var _pushed: Array[int] = []
## 是否停在删除区（给拖动副本压暗红用）。
var _delete_hover: bool = false
## 拖动中的副本挂在顶层覆盖层：画布里的块盖不过兄弟控件（左侧块列表）。
var _overlay: Control = null
var _floats: Array[BlockView] = []
var _float_offsets: Array[Vector2] = []
var _hidden: Dictionary[int, bool] = {}


func _ready() -> void:
	_overlay = get_parent().get_node_or_null(^"DragLayer") as Control
	super._ready()


#region 开始拖拽

func start_from_view(view: BlockView, offset: Vector2) -> void:
	if _active or canvas == null or view == null or view.node == null:
		return
	if not canvas.graph.has(view.node.id):
		return
	_active = true
	_button = MOUSE_BUTTON_LEFT
	_source_node = view.node
	_type_id = view.node.type_id
	_type_def = canvas.library.by_id(_type_id)
	_offset = offset
	# 拿起一个块时，它"后面的所有块"一起走（Mindustry 的操作直觉：后面的跟着走，顺序不乱）
	_carried = canvas.graph.tail_ids(_source_node.id)
	_subtree_positions.clear()
	_exclude.clear()
	for carried_id in _carried:
		for id in canvas.graph.subtree_ids(carried_id):
			_exclude[id] = true
			_subtree_positions[id] = canvas.layout.rect_of(id).position if canvas.layout != null else Vector2.ZERO
	# 原块先隐藏，改用覆盖层里的副本跟手 —— 否则拖到左侧块列表上方时会被裁掉
	_spawn_floats(_subtree_positions.keys(), _subtree_positions.get(_source_node.id, Vector2.ZERO), true)
	_begin_session()


## 多选整组拖动（由 [SelectionController] 发起）：搬一组任意顶层块，保序、一次撤销。
## [param ids] 按视觉顺序；[param grabbed_id] 是按下拖拽的那一块（鼠标偏移以它为基准）。
func start_group_from_view(ids: Array[int], grabbed_id: int, offset: Vector2) -> void:
	if _active or canvas == null or ids.size() < 2:
		return
	if not canvas.graph.has(grabbed_id):
		return
	_active = true
	_button = MOUSE_BUTTON_LEFT
	_group_ids = ids.duplicate()
	_source_node = canvas.graph.get_node_by_id(grabbed_id)
	_type_id = _source_node.type_id
	_type_def = canvas.library.by_id(_type_id)
	_offset = offset
	_carried.clear()
	_subtree_positions.clear()
	_exclude.clear()
	for id in _group_ids:
		for sub_id in canvas.graph.subtree_ids(id):
			_exclude[sub_id] = true
			_subtree_positions[sub_id] = canvas.layout.rect_of(sub_id).position if canvas.layout != null else Vector2.ZERO
	_spawn_floats(_subtree_positions.keys(), _subtree_positions.get(grabbed_id, Vector2.ZERO), true)
	_begin_session()


## 右键在块上按下：拖出一份副本（源块不隐藏也不移动，落地时才克隆）。
func start_copy_from_view(view: BlockView, offset: Vector2) -> void:
	if _active or canvas == null or view == null or view.node == null:
		return
	if not canvas.graph.has(view.node.id):
		return
	# 入口块不许复制（一个文档只该有一个）：连会话都不开，右键不会冒出跟手的副本
	if canvas.is_entry(view.node):
		return
	_active = true
	_button = MOUSE_BUTTON_RIGHT
	_source_node = null
	_copy_source_id = view.node.id
	_copy_ids = canvas.graph.subtree_ids(_copy_source_id)
	_type_id = view.node.type_id
	_type_def = canvas.library.by_id(_type_id)
	_offset = offset
	# 复制的不是“后面那串”，这里必须清掉上一次拖拽的遗留
	_carried.clear()
	_exclude.clear()
	_subtree_positions.clear()
	for id in _copy_ids:
		_subtree_positions[id] = canvas.layout.rect_of(id).position if canvas.layout != null else Vector2.ZERO
	_spawn_floats(_copy_ids, _subtree_positions.get(_copy_source_id, Vector2.ZERO), false)
	_begin_session()


func start_from_palette(block: BlockDef, offset: Vector2) -> void:
	if _active or canvas == null or block == null:
		return
	_active = true
	_button = MOUSE_BUTTON_LEFT
	_source_node = null
	_type_id = block.id
	_type_def = block
	_offset = offset
	_subtree_positions.clear()
	_exclude.clear()
	# 新建块没有“要一起搬的块”：清掉上一次拖拽留下的 _carried，免得摆出旧占位视图
	_carried.clear()
	_ghost = canvas.make_ghost(_type_id, _overlay)
	if _ghost != null:
		_ghost.position = _layer_mouse() - _offset * _zoom()
	_begin_session()


## 会话开始：拖拽期间块里的控件一律不可操作（拖拽只搬位置，不改数据）。
func _on_session_started() -> void:
	canvas.set_elements_enabled(false)
	_target = {}
	drag_started.emit()


## 生成跟手的副本（位置 = 相对头块的布局偏移）；搬移时顺带藏起原块。
func _spawn_floats(ids: Array, head: Vector2, hide_sources: bool) -> void:
	_floats.clear()
	_float_offsets.clear()
	_hidden.clear()
	if _overlay == null:
		return
	for id in ids:
		var node := canvas.graph.get_node_by_id(id)
		if node == null:
			continue
		if hide_sources:
			var source_view := canvas.view_of(id)
			if PlacementPreview.is_valid_object(source_view):
				_hidden[id] = source_view.visible
				source_view.visible = false
		var float_view := canvas.make_ghost(node.type_id, _overlay, node)
		if float_view != null:
			_floats.append(float_view)
			_float_offsets.append((_subtree_positions[id] as Vector2) - head)

#endregion


#region 跟踪与落地


func _update_session() -> void:
	var world := _world_mouse()
	var layer := _layer_mouse()
	var zoom := _zoom()
	# 悬停到左侧块列表上：不找吸附点，只提示「松手就删」
	var deleting := _source_node != null and _over_delete_zone()
	if deleting != _delete_hover:
		_delete_hover = deleting
		_apply_delete_hint(deleting)
	if PlacementPreview.is_valid_object(_ghost):
		_ghost.position = layer - _offset * zoom
		_ghost.scale = Vector2(zoom, zoom)
	elif not _floats.is_empty():
		# 覆盖层是屏幕空间：位置 = 鼠标 + 各块相对头块的布局偏移 × 缩放
		var origin := layer - _offset * zoom
		for i in _floats.size():
			var float_view := _floats[i]
			if PlacementPreview.is_valid_object(float_view):
				float_view.position = origin + _float_offsets[i] * zoom
				float_view.scale = Vector2(zoom, zoom)
	elif _source_node != null and not _subtree_positions.is_empty():
		# 没有覆盖层时的兜底：仍在画布坐标系里直接移动原块
		var base: Vector2 = _subtree_positions.get(_source_node.id, world - _offset)
		var delta := world - _offset - base
		for id in _subtree_positions:
			var view: BlockView = canvas.view_of(id)
			if PlacementPreview.is_valid_object(view):
				view.position = (_subtree_positions[id] as Vector2) + delta
	if _delete_hover or not _inside_canvas():
		# 拖到删除区 / 画布外：不找吸附点也不摆占位块（松手时再决定删还是取消）
		_target = {}
		_release_shift()
		canvas.clear_placement_preview()
		return
	_target = canvas.find_anchor(world, capture_radius, _exclude)
	_update_placement_preview()


func _update_placement_preview() -> void:
	_release_shift()
	if _target.is_empty() or canvas.layout == null:
		canvas.clear_placement_preview()
		return
	var at := Vector2(_target.get("position", Vector2.ZERO))
	if _copy_source_id > 0:
		if _copy_ids.is_empty():
			canvas.clear_placement_preview()
			return
		# 副本是源的深拷贝，形状与源子树一模一样：按“根落在吸附点”把它们摆出来
		canvas.show_placement_preview(_copy_ids, at - canvas.layout.rect_of(_copy_ids[0]).position)
		_apply_insert_shift(at)
		return
	if _source_node == null:
		# 从调色板拖出：占位块就是将要新建的那个块（默认值），左上角落在吸附点上
		canvas.show_new_placement_preview(_type_def, at)
		_apply_insert_shift(at)
		return
	if _carried.is_empty() and _group_ids.is_empty():
		canvas.clear_placement_preview()
		return
	# 多选组拖：占位的是整个选中集（顺序与源布局无关，只按它们的原始摆位平移）。
	var preview_ids: Array[int] = _group_ids if not _group_ids.is_empty() else _carried
	canvas.show_placement_preview(preview_ids, at - canvas.layout.rect_of(preview_ids[0]).position)
	_apply_insert_shift(at)


## 插在中间时给占位块腾位置：把插入点之后的块整体下移（每帧先还原再重算）。
func _apply_insert_shift(_at: Vector2) -> void:
	var index: int = int(_target.get("index", -1))
	var height := canvas.placement_preview_height()
	if index < 0 or height <= 0.0:
		return
	var owner_id: int = int(_target.get("owner_id", LogicGraph.ROOT))
	var slot: StringName = _target.get("slot", &"")
	for item in canvas.graph.slot_items(owner_id, slot).slice(index):
		for id in canvas.graph.subtree_ids(item):
			var view := canvas.view_of(id)
			if PlacementPreview.is_valid_object(view):
				view.position += Vector2(0, height)
				_pushed.append(id)


## 把让位造成的临时偏移还原（布局结果才是真相）。
func _release_shift() -> void:
	for id in _pushed:
		var view := canvas.view_of(id)
		if PlacementPreview.is_valid_object(view) and canvas.layout != null:
			view.position = canvas.layout.rect_of(id).position
	_pushed.clear()


func _finish_session() -> void:
	if not _active:
		return
	var world := _world_mouse()
	var origin := world - _offset
	var target := _target
	var inside := _inside_canvas()
	var source := _source_node
	var type_id := _type_id
	var moved := _moved(world)
	# 拖到左侧块列表松手 = 删除（要在 _close_session() 清掉这些集合之前判断）
	var carried := _carried.duplicate()
	var group := _group_ids.duplicate()
	var deleting := source != null and moved and _over_delete_zone()
	# 复制的源块要赶在 _close_session() 之前记下来
	var copy_source := _copy_source_id
	_close_session()
	var doomed: Array[int] = group if not group.is_empty() else carried
	if deleting and not doomed.is_empty():
		# 入口块不能删：删了文档就没起点（导出「从 Start 开始」也无从谈起）。
		if self._carries_entry(doomed):
			print("[MVL] 入口块（Start）不能删除")
			canvas.relayout()
			return
		canvas.remove_nodes(doomed)
		return
	if not inside or not moved:
		# 画布外松手 = 取消；原地松手 = 没搬动，都不动数据
		canvas.relayout()
		return
	if copy_source > 0:
		# 右键拖拽复制：源块留在原地，这里只把副本插进去
		if target.is_empty():
			canvas.duplicate_subtree_to_new_chain(copy_source, origin)
		else:
			canvas.duplicate_subtree(copy_source, target["owner_id"], target["slot"], target["index"])
		return
	if not group.is_empty():
		# 多选组拖：任意集合按选中时的视觉顺序保序落位
		if target.is_empty():
			canvas.move_nodes_to_new_chain(group, origin)
		else:
			canvas.move_nodes(group, target["owner_id"], target["slot"], target["index"])
		return
	if not target.is_empty():
		var owner_id: int = target["owner_id"]
		var slot: StringName = target["slot"]
		var index: int = target["index"]
		if source == null:
			canvas.insert_new_node(type_id, owner_id, slot, index)
		else:
			canvas.move_tail(_carried, owner_id, slot, index)
	elif source == null:
		canvas.insert_new_chain(type_id, origin)
	else:
		canvas.move_tail_to_new_chain(_carried, origin)


func _carries_entry(ids: Array[int]) -> bool:
	for id in ids:
		if canvas.is_entry(canvas.graph.get_node_by_id(id)):
			return true
	return false


func _finish_button() -> MouseButton:
	return _button


## 右键 / Esc：取消拖拽，清掉临时效果并把布局复原。
func cancel() -> void:
	if not _active:
		return
	super.cancel()
	canvas.relayout()


func _close_session() -> void:
	for float_view in _floats:
		if PlacementPreview.is_valid_object(float_view):
			canvas.release_ghost(float_view)
	_floats.clear()
	_float_offsets.clear()
	for id in _hidden:
		var hidden_view := canvas.view_of(id)
		if PlacementPreview.is_valid_object(hidden_view):
			hidden_view.visible = _hidden[id]
	_hidden.clear()
	_release_shift()
	if PlacementPreview.is_valid_object(_ghost):
		canvas.release_ghost(_ghost)
	_ghost = null
	_active = false
	_delete_hover = false
	_source_node = null
	_copy_source_id = 0
	_group_ids.clear()
	_copy_ids.clear()
	_type_id = &""
	_type_def = null
	_subtree_positions.clear()
	_exclude.clear()
	_target = {}
	set_process(false)
	if canvas != null:
		canvas.set_elements_enabled(true)
		canvas.clear_placement_preview()
	drag_finished.emit()


## 覆盖层坐标下的鼠标位置；没有覆盖层时退回画布世界坐标。
func _layer_mouse() -> Vector2:
	if _overlay != null:
		return _overlay.get_global_mouse_position()
	return _world_mouse()


## 相机缩放：覆盖层是屏幕空间，副本的位置与大小都要按它换算。
func _zoom() -> float:
	if _overlay != null and canvas != null and canvas.nCamera != null:
		return canvas.nCamera.zoom.x
	return 1.0



## 给拖动副本压一层暗红，提示「松手就删」；离开时恢复本色。
func _apply_delete_hint(on: bool) -> void:
	var tint := Color(1.0, 0.45, 0.45, 0.85) if on else Color.WHITE
	if PlacementPreview.is_valid_object(_ghost):
		_ghost.modulate = tint
	for float_view in _floats:
		if PlacementPreview.is_valid_object(float_view):
			float_view.modulate = tint



#endregion
