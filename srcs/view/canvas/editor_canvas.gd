class_name EditorCanvas
extends SubViewport

## 画布：持有图、撤销栈与全部块视图，负责布局求解与结构变更。
## 块视图之间没有父子关系，位置一律来自 [LayoutSolver]。

signal picker_requested(view: BlockView, element: ElementDef, control: Control)
signal link_requested(view: BlockView, element: ElementDef, control: Control)
signal copy_requested(view: BlockView, offset: Vector2)
signal drag_requested(view: BlockView, offset: Vector2)
## 按下时先报选择层（见 [BlockView.press_requested]）。
signal press_requested(view: BlockView, offset: Vector2, ctrl: bool, shift: bool)

@onready var nBlocks: Node2D = $Blocks
## 跳线层（在 Blocks 之后，线画在块上面，见 [LinkLayer]）。
@onready var nLinks: LinkLayer = $Links
## 落点占位块（幽灵视图）：状态在 [PlacementPreview] 里，画布只转发。
var _placement: PlacementPreview = null
@onready var nCamera: EditorCamera = $Camera
## 「框选 / 多选 / 组拖」控制器（[method setup] 里创建，选区真相在它手里）。
var _selection: SelectionController = null
var _overlay: CanvasOverlay = null

var library: BlockLibrary
var graph: LogicGraph
var history: GraphHistory
var layout: LayoutResult = null

var _views: Dictionary[int, BlockView] = {}
## 幽灵视图池：父节点 → { 块类型 id → 空闲幽灵 }。幽灵只显示、不吃鼠标、用完就扔，
## 而「新建一棵控件树」正是拖动起手里最贵的一步（带中文文本的 Label 首次入树约 3 ms）——留着重用。
const GHOST_POOL_LIMIT: int = 64
var _ghost_pool: Dictionary = {}
var _applying_field: bool = false
## 跳线数据（线段 + 颜色），每次布局后由 [method _refresh_links] 重算。
var _segments: Array[Dictionary] = []
## 锁定拖拽的预览线：{from, to, valid}；空字典 = 没在拖。
var _preview: Dictionary = {}
## 当前被高亮描边圈住的块（0 = 没有）。
var _highlight_id: int = 0
## 多选高亮集合与框选矩形（都是纯视觉，真相在 [SelectionController]）。
var _selected: Dictionary[int, bool] = {}
var _selection_band := Rect2()
var _selection_band_on := false



func setup(p_library: BlockLibrary, p_graph: LogicGraph = null) -> void:
	library = p_library
	_flush_ghost_pool()
	_placement = PlacementPreview.new(self)
	nLinks.canvas = self
	_selection = SelectionController.new()
	_selection.name = "Selection"
	_selection.canvas = self
	add_child(_selection)
	_overlay = CanvasOverlay.new()
	_overlay.name = "Overlay"
	_overlay.canvas = self
	add_child(_overlay)
	_attach_graph(p_graph)


## 换成另一张图：断开旧信号、接上新图并重建视图与撤销栈。
func adopt_graph(p_graph: LogicGraph) -> void:
	if graph == p_graph:
		return
	_attach_graph(p_graph)


## 建图接线只在这一处：setup 与 adopt_graph 共用同一条路径。
func _attach_graph(p_graph: LogicGraph) -> void:
	if graph != null:
		graph.structure_changed.disconnect(_on_structure_changed)
		graph.reset.disconnect(_on_graph_reset)
		graph.field_changed.disconnect(_on_field_changed)
	graph = p_graph if p_graph != null else LogicGraph.new()
	graph.structure_changed.connect(_on_structure_changed)
	graph.reset.connect(_on_graph_reset)
	graph.field_changed.connect(_on_field_changed)
	history = GraphHistory.new(graph)
	if _selection != null:
		_selection.prune()
	rebuild()


#region 视图与布局

## 按当前图整体重建块视图（撤销/读档/首次打开走这里）。
func rebuild() -> void:
	_flush_ghost_pool()
	for id in _views.keys():
		var view: BlockView = _views[id]
		if PlacementPreview.is_valid_object(view):
			PlacementPreview.dismiss(view)
	_views.clear()
	for id in graph.all_ids():
		_create_view(id)
	# 重建后把选择高亮重新刷一遍（视图是新的，高亮不会自己回来）
	for id in _selected:
		_set_view_selected(id, true)
	relayout()


func relayout() -> void:
	if library == null:
		return
	layout = LayoutSolver.solve(graph, _measure)
	for id in _views:
		var view: BlockView = _views[id]
		if not PlacementPreview.is_valid_object(view):
			continue
		var rect := layout.rect_of(id)
		view.position = rect.position
		view.size = rect.size
	_refresh_links()


## 拖拽期间统一开关所有块视图的可交互控件（拖拽只搬位置，不顺手改数据）。
func set_elements_enabled(enabled: bool) -> void:
	for id in _views:
		var view: BlockView = _views[id]
		if PlacementPreview.is_valid_object(view):
			view.set_elements_enabled(enabled)

func _measure(node: LogicNode, slot_extents: Dictionary[StringName, Vector2]) -> BlockMetrics:
	var view: BlockView = _views.get(node.id)
	if not PlacementPreview.is_valid_object(view):
		# 视图还没建（首次求解）时先建出来再量
		view = _create_view(node.id)
	if view == null:
		return BlockMetrics.new()
	return view.measure(slot_extents)


func view_of(id: int) -> BlockView:
	return _views.get(id)



## 现有内容占的矩形（Ctrl+V 用它把新链摆到下方）。
func content_rect() -> Rect2:
	var out := Rect2()
	var first := true
	for id in _views:
		var view: BlockView = _views[id]
		if not PlacementPreview.is_valid_object(view):
			continue
		var rect := Rect2(view.position, view.size)
		out = rect if first else out.merge(rect)
		first = false
	return out


## 「框选 / 多选 / 组拖」控制器（标签页接它的 area / drag）。
func selection() -> SelectionController:
	return _selection


## 多选高亮集合变了（由 [SelectionController] 推过来）：同步到各块视图的描边。
func set_selected_ids(ids: Array[int]) -> void:
	var next: Dictionary[int, bool] = {}
	for id in ids:
		next[id] = true
	for id in _selected:
		if not next.has(id):
			_set_view_selected(id, false)
	for id in next:
		if not _selected.has(id):
			_set_view_selected(id, true)
	_selected = next


func _set_view_selected(id: int, on: bool) -> void:
	var view: BlockView = _views.get(id)
	if PlacementPreview.is_valid_object(view):
		view.set_selected_highlight(on)


## 框选矩形（世界坐标）与开关；不命中任何块时也要画矩形本身。
func set_selection_band(rect: Rect2, on: bool) -> void:
	_selection_band = rect
	_selection_band_on = on
	_redraw_overlay()

func selection_band() -> Rect2:
	return _selection_band


func selection_band_on() -> bool:
	return _selection_band_on
## 这个节点是不是入口块：不放复制、不准删、导出从它开始。
func is_entry(node: LogicNode) -> bool:
	return node != null and library != null and library.is_entry(node.type_id)

## 某节点各槽位在当前布局里的尺寸（幽灵与占位块拿它再量一次自己）。
func slot_extents_of(id: int) -> Dictionary[StringName, Vector2]:
	var out: Dictionary[StringName, Vector2] = {}
	var node := graph.get_node_by_id(id)
	if node == null or layout == null:
		return out
	for slot_id in node.slots:
		out[slot_id] = LayoutSolver.chain_extent(node.peek_slot(slot_id), layout)
	return out


func _create_view(id: int) -> BlockView:
	var node := graph.get_node_by_id(id)
	if node == null:
		return null
	var def := library.by_id(node.type_id) if library != null else null
	if def == null:
		push_warning("未知块类型：%s（节点 %d）" % [node.type_id, id])
		return null
	var view := BlockView.new()
	view.name = "Block%d" % id
	view.drag_requested.connect(drag_requested.emit)
	view.copy_requested.connect(copy_requested.emit)
	view.link_requested.connect(link_requested.emit)
	view.picker_requested.connect(picker_requested.emit)
	view.press_requested.connect(press_requested.emit)
	view.history_group_closed.connect(history.flush_merge)
	view.field_committed.connect(_on_view_field_committed)
	view.layout_dirty.connect(_on_view_layout_dirty)
	# 跳转目标按钮上的文字由画布注入（只有它知道图）
	view.link_labeler = _link_label
	nBlocks.add_child(view)
	view.setup(def, node, false)
	_views[id] = view
	return view



func _on_view_layout_dirty() -> void:
	relayout()


## 视图内控件改了字段：写进图并记进撤销栈（不回灌控件，避免打断输入；解释见 [method _record_field]）。
func _on_view_field_committed(node: LogicNode, field_id: StringName, value: Variant, merge_key: StringName) -> void:
	_record_field(node, field_id, value, "修改 %s" % String(field_id), Callable(), merge_key)

#endregion


## 放一个入口块到新链上（不进撤销栈）：新页 / 清空 / 重置后的起点。
func spawn_entry_block() -> void:
	var def := library.entry_def() if library != null else null
	if def == null:
		return
	var node := _make_node(def.id)
	# 可能在撤销闭包里被调用（clear_graph）：用一次信号完成「建链 + 插节点」，避免发两次结构变更
	graph.insert_in_new_chain(node, Vector2(40, 40))


func insert_new_node(type_id: StringName, owner_id: int, slot_id: StringName, index: int, label: String = "添加块") -> LogicNode:
	# 节点先建好（未入图）再放进栈里执行：lambda 按值捕获，不能在闭包里给外部变量赋值
	var node := _make_node(type_id)
	history.record(label, func() -> void:
		graph.insert_node(node, owner_id, slot_id, index))
	return node


func insert_new_chain(type_id: StringName, world_pos: Vector2, label: String = "添加块") -> LogicNode:
	var node := _make_node(type_id)
	history.record(label, func() -> void:
		graph.insert_in_new_chain(node, world_pos))
	return node


## 把一串有先后顺序的块整体搬到目标容器，一次撤销记录；空集或首块不在图上时不动数据。
func relocate(ids: Array[int], owner_id: int, slot_id: StringName, index: int) -> bool:
	if ids.is_empty() or not graph.has(ids[0]):
		return false
	history.record("移动块", func() -> void:
		graph.move_nodes(ids, owner_id, slot_id, index))
	return true


## 搬到画布上新的一条链（落点由 [param world_pos] 定），一次撤销记录。
func relocate_to_new_chain(ids: Array[int], world_pos: Vector2) -> bool:
	if ids.is_empty() or not graph.has(ids[0]):
		return false
	history.record("移动块", func() -> void:
		graph.move_nodes_to_new_chain(ids, world_pos))
	return true


func move_node(id: int, owner_id: int, slot_id: StringName, index: int) -> bool:
	return relocate([id] as Array[int], owner_id, slot_id, index)


func move_tail(ids: Array[int], owner_id: int, slot_id: StringName, index: int) -> bool:
	if ids.is_empty() or not graph.has(ids[0]):
		return false
	history.record("移动块", func() -> void:
		graph.move_tail(ids, owner_id, slot_id, index))
	return true


func move_tail_to_new_chain(ids: Array[int], world_pos: Vector2) -> bool:
	return relocate_to_new_chain(ids, world_pos)


## 任意集合一起搬（多选组拖用），一次撤销记录；顺序 = 选中时的视觉顺序。
func move_nodes(ids: Array[int], owner_id: int, slot_id: StringName, index: int) -> bool:
	return relocate(ids, owner_id, slot_id, index)


func move_nodes_to_new_chain(ids: Array[int], world_pos: Vector2) -> bool:
	return relocate_to_new_chain(ids, world_pos)

## 删除任意集合（多选组拖的整组删除），一次撤销记录；语义同 [method remove_tail]。
func remove_nodes(ids: Array[int]) -> bool:
	if ids.is_empty() or not graph.has(ids[0]):
		return false
	var doomed := ids.duplicate()
	var links: Dictionary = {}
	for id in doomed:
		for victim in graph.subtree_ids(id):
			links[victim] = true
	history.record("删除块", func() -> void:
		for id in doomed:
			graph.remove_node(id)
		graph.clear_links_to(links, _reference_fields_of))
	return true


## 删除一串块，一次撤销记录；被删的块可能是别的 Jump 的目标，指向它们的引用一并清掉。
func remove_tail(ids: Array[int]) -> bool:
	return remove_nodes(ids)
## 复制以 [param source_id] 为根的子树插进容器，返回新根 id（失败 0）。
func duplicate_subtree(source_id: int, owner_id: int, slot_id: StringName, index: int) -> int:
	return _duplicate(source_id, func(nodes: Array[LogicNode]) -> void:
		graph.insert_subtree(nodes, owner_id, slot_id, index))


## 复制到画布上新的一条链，返回新根 id（失败 0）。
func duplicate_subtree_to_new_chain(source_id: int, world_pos: Vector2) -> int:
	return _duplicate(source_id, func(nodes: Array[LogicNode]) -> void:
		var chain := graph.create_chain(world_pos)
		graph.insert_subtree(nodes, LogicGraph.ROOT, chain, -1))


## 复制一棵子树并整体入图，返回新根 id；[param mutate] 拿到尚未入图的副本。
func _duplicate(source_id: int, mutate: Callable) -> int:
	# 入口块拒绝复制（DragController 已拦一道）：复制入口 = 一个文档两个起点
	if self.is_entry(graph.get_node_by_id(source_id)):
		return 0
	var clone := _clone_subtree(source_id)
	if clone.is_empty():
		return 0
	var nodes: Array[LogicNode] = clone["nodes"]
	var new_root: LogicNode = clone["root"]
	history.record("复制块", mutate.bind(nodes))
	return new_root.id


## 深拷贝一棵子树（含槽位结构）：实现全在 [GraphCloner]（纯数据、不碰控件）。
func _clone_subtree(source_id: int) -> Dictionary:
	return GraphCloner.clone(graph, source_id, _reference_fields_of)


## 某节点的块引用字段（「哪些字段是引用」的真相在块定义上）。
func _reference_fields_of(node: LogicNode) -> Array[StringName]:
	var def := library.by_id(node.type_id) if library != null else null
	return def.reference_fields() if def != null else [] as Array[StringName]


## 撤销/重做：history 内部会 load_dict，图发出 reset 信号后画布自行重建。
func undo() -> bool:
	return history.undo()


func redo() -> bool:
	return history.redo()


## 建节点并预置字段默认值（默认值在数据层，不在输入框里）。
func _make_node(type_id: StringName) -> LogicNode:
	var node := graph.new_node(type_id)
	var def := library.by_id(type_id) if library != null else null
	if def != null:
		def.apply_defaults(node)
	return node

#endregion


#region 坐标与拖拽辅助

## 屏幕坐标 → 画布世界坐标（[param area_rect] 是 SubViewportContainer 的全局矩形）。
func world_from_screen(area_rect: Rect2, screen_pos: Vector2) -> Vector2:
	var local := screen_pos - area_rect.position
	return get_canvas_transform().affine_inverse() * local


func anchors() -> Array[Dictionary]:
	return layout.anchors if layout != null else []


## 找可落点的锚点：优先命中鼠标附近的插入线（[param exclude] 里的块不参与），找不到返回空字典。
func find_anchor(world_pos: Vector2, radius: float, exclude: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_cost := INF
	for anchor in anchors():
		var from_id: int = anchor.get("from_id", 0)
		if exclude.has(from_id):
			continue
		var owner_id: int = anchor.get("owner_id", 0)
		if owner_id != LogicGraph.ROOT and exclude.has(owner_id):
			continue
		var origin: Vector2 = anchor["position"]
		var width: float = maxf(float(anchor["width"]), 12.0)
		var dy := absf(world_pos.y - origin.y)
		if dy > radius:
			continue
		if world_pos.x < origin.x - radius or world_pos.x > origin.x + width + radius:
			continue
		var cost := dy + absf(world_pos.x - clampf(world_pos.x, origin.x, origin.x + width)) * 0.25
		if cost < best_cost:
			best_cost = cost
			best = anchor
	return best


## 造一个幽灵块视图（半透明、不吃鼠标、绑临时节点不写历史）。
## [param parent] 传顶层覆盖层就画在整个界面之上；[param source] 传真实节点则显示它的字段值。
func make_ghost(type_id: StringName, parent: Node = null, source: LogicNode = null) -> BlockView:
	var def := library.by_id(type_id) if library != null else null
	if def == null:
		return null
	var host: Node = parent if parent != null else nBlocks
	var temp := source if source != null else LogicNode.new(0, type_id)
	if source == null:
		def.apply_defaults(temp)
	var extents: Dictionary[StringName, Vector2] = {}
	if source != null:
		extents = slot_extents_of(source.id)
	var ghost := _take_pooled_ghost(host, type_id)
	# 池里那个已经建好控件树（preview、不吃鼠标、link_labeler 都就位了）：换节点刷新即可；
	# 换不了（池里的是旧库的定义，正常不会发生）就丢掉重来。
	if ghost != null:
		if ghost.retarget(def, temp, extents):
			ghost.visible = true
			ghost.modulate = Color.WHITE
			ghost.scale = Vector2.ONE
			ghost.z_index = 50
			return ghost
		PlacementPreview.dismiss(ghost)
	ghost = BlockView.new()
	ghost.interactive = false
	# 幽灵也要显示「锁到了哪一块」：不注入这个标签器，跳转目标会一律显示未锁定
	ghost.link_labeler = _link_label
	host.add_child(ghost)
	ghost.setup(def, temp, true)
	if source != null:
		ghost.measure(extents)
	ghost.z_index = 50
	return ghost


## 归还幽灵：留在池里等下次拖动复用。真实视图不走这里（那些该被 dismiss）。
func release_ghost(ghost: BlockView) -> void:
	if not PlacementPreview.is_valid_object(ghost) or ghost.def == null:
		return
	var host := ghost.get_parent()
	if host == null:
		return
	var bucket: Dictionary = _ghost_pool.get(host, {})
	var free: Array = bucket.get(ghost.def.id, [])
	if free.size() >= GHOST_POOL_LIMIT:
		PlacementPreview.dismiss(ghost)
		return
	ghost.visible = false
	ghost.modulate = Color.WHITE
	ghost.scale = Vector2.ONE
	free.append(ghost)
	bucket[ghost.def.id] = free
	_ghost_pool[host] = bucket


func _take_pooled_ghost(host: Node, type_id: StringName) -> BlockView:
	var bucket: Variant = _ghost_pool.get(host)
	if not (bucket is Dictionary):
		return null
	var free: Array = (bucket as Dictionary).get(type_id, [])
	while not free.is_empty():
		var ghost: BlockView = free.pop_back()
		if PlacementPreview.is_valid_object(ghost) and ghost.def != null:
			return ghost
	return null


## 池里的幽灵绑的是旧库的块定义（换语言会整库重建），一律作废。
func _flush_ghost_pool() -> void:
	for host in _ghost_pool:
		if not is_instance_valid(host):
			continue
		var bucket: Dictionary = _ghost_pool[host]
		for type_id in bucket:
			for ghost in bucket[type_id]:
				if PlacementPreview.is_valid_object(ghost):
					PlacementPreview.dismiss(ghost)
	_ghost_pool.clear()


func show_placement_preview(ids: Array[int], offset: Vector2) -> void:
	_placement.show_existing(ids, offset)


## 调色板拖出时的落点占位块：将要新建的那个块（默认值就是它入图时的取值）。
func show_new_placement_preview(def: BlockDef, top_left: Vector2) -> void:
	_placement.show_new(def, top_left)


func placement_preview_height() -> float:
	return _placement.height()


func clear_placement_preview() -> void:
	_placement.clear()

#endregion


#region 跳线（Jump 的跳转目标）

func link_segments() -> Array[Dictionary]:
	return _segments


func link_preview() -> Dictionary:
	return _preview


func link_anchor(id: int) -> Vector2:
	return LinkRouter.anchor_left(layout, id)


## 世界坐标命中哪一块（嵌套时取面积最小的，返回 0 = 空白）。
func node_at_world(point: Vector2, exclude: Dictionary = {}) -> int:
	var best := 0
	var best_area := INF
	for id in _views:
		if exclude.has(id):
			continue
		var view: BlockView = _views[id]
		if not PlacementPreview.is_valid_object(view) or not view.contains_world_point(point):
			continue
		var area := view.size.x * view.size.y
		if area < best_area:
			best_area = area
			best = id
	return best


## 锁定 / 解除某个引用字段（[param target_id] 为 0 表示解除）；重复锁同一目标不动数据。
func set_link(source_id: int, field_id: StringName, target_id: int) -> bool:
	var node := graph.get_node_by_id(source_id)
	if node == null:
		return false
	if graph.link_target(node, field_id) == target_id:
		return true
	return _record_field(node, field_id, LogicGraph.make_link_ref(target_id),
			"锁定跳转目标" if target_id > 0 else "解除跳转目标",
			func(view: BlockView) -> void: view.sync_from_data())

## 写一个字段并记一条撤销（值没变时由撤销栈的快照比对兜底，不在这里早退 ——
## 视图提交后总要刷新可见性与布局）。视图自己发起的改动不回灌控件（避免打断输入），
## [param sync] 提供时才把控件刷成新值（锁定目标是程序化改的，控件不会自己发信号）。
## [param merge_key] 非空时与上一条同 key 的记录合并（输入框连续打字算一条撤销）。
func _record_field(node: LogicNode, field_id: StringName, value: Variant, label: String,
		sync: Callable, merge_key: StringName = &"") -> bool:
	_applying_field = true
	history.record(label, func() -> void:
		graph.set_field(node.id, field_id, value), merge_key)
	_applying_field = false
	var view: BlockView = _views.get(node.id)
	if PlacementPreview.is_valid_object(view):
		if sync.is_valid():
			sync.call(view)
		else:
			view.refresh_visibility()
	relayout()
	return true

## 锁定拖拽中：更新预览线与悬停高亮（每帧由 [LinkController] 调）。
func set_link_preview(from: Vector2, to: Vector2, hover_id: int) -> void:
	_preview = {"from": from, "to": to, "valid": hover_id > 0}
	set_link_highlight(hover_id)
	_redraw_overlay()


func clear_link_preview() -> void:
	_preview = {}
	set_link_highlight(0)
	_redraw_overlay()


func set_link_highlight(id: int) -> void:
	if _highlight_id == id:
		return
	var previous: BlockView = _views.get(_highlight_id)
	if PlacementPreview.is_valid_object(previous):
		previous.set_link_highlight(false)
	_highlight_id = id
	var current: BlockView = _views.get(id)
	if PlacementPreview.is_valid_object(current):
		current.set_link_highlight(true)


## 引用字段现在指着哪一块（块视图把它显示在按钮上）。
func _link_label(node_id: int, field_id: StringName) -> String:
	var node := graph.get_node_by_id(node_id)
	if node == null:
		return tr("LINK_UNLOCKED")
	var target := graph.link_target(node, field_id)
	if target <= 0:
		return tr("LINK_UNLOCKED")
	return String(graph.get_node_by_id(target).type_id)


## 重算全部跳线（布局一变就跑）。
func _refresh_links() -> void:
	_segments = LinkRouter.segments(graph, library, layout)
	_redraw_links()

func _redraw_links() -> void:
	if PlacementPreview.is_valid_object(nLinks):
		nLinks.queue_redraw()


func _redraw_overlay() -> void:
	if PlacementPreview.is_valid_object(_overlay):
		_overlay.queue_redraw()


class CanvasOverlay extends Node2D:
	const LINE_WIDTH: float = 4.0
	const PREVIEW_DASH: float = 7.0
	const BAND_WIDTH: float = 1.5
	const PREVIEW_COLOR: Color = Color(1.0, 0.9, 0.4, 0.95)
	const PREVIEW_CANCEL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.4)
	const BAND_FILL: Color = Color(0.30, 0.55, 1.0, 0.10)
	const BAND_EDGE: Color = Color(0.45, 0.72, 1.0, 0.95)

	var canvas: Object

	func _draw() -> void:
		if canvas == null:
			return
		# 1. 动态连线预览（仅在拖线时绘制）
		var preview: Dictionary = canvas.link_preview()
		if not preview.is_empty():
			var from: Vector2 = preview["from"]
			var to: Vector2 = preview["to"]
			var valid: bool = bool(preview["valid"])
			var color: Color = PREVIEW_COLOR if valid else PREVIEW_CANCEL_COLOR
			draw_dashed_line(from, to, color, LINE_WIDTH, PREVIEW_DASH, true)
			if valid:
				LinkLayer.draw_arrow(self, to, color)

		# 2. 动态框选矩形（仅在框选时绘制）
		if canvas.selection_band_on():
			var band: Rect2 = canvas.selection_band()
			draw_rect(band, BAND_FILL, true)
			draw_rect(band, BAND_EDGE, false, BAND_WIDTH)




#endregion


#region 图信号

func _on_structure_changed() -> void:
	_sync_views()
	relayout()


func _on_graph_reset() -> void:
	rebuild()


func _on_field_changed(id: int, _field_id: StringName, _value: Variant) -> void:
	if _applying_field:
		return
	var view: BlockView = _views.get(id)
	if PlacementPreview.is_valid_object(view):
		view.sync_from_data()
	relayout()


## 结构变化后对齐视图集合：新增的建、消失的删，其余保持（避免重建打断输入）。
func _sync_views() -> void:
	var alive: Dictionary[int, bool] = {}
	for id in graph.all_ids():
		alive[id] = true
		if not _views.has(id) or not PlacementPreview.is_valid_object(_views[id]):
			_create_view(id)
	for id in _views.keys():
		if not alive.has(id):
			var view: BlockView = _views[id]
			if PlacementPreview.is_valid_object(view):
				PlacementPreview.dismiss(view)
			_views.erase(id)

#endregion
