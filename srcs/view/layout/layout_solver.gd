class_name LayoutSolver
extends RefCounted

## 布局求解（纯函数，不碰控件）：先自底向上量尺寸，再自顶向下摆位置，最后按位置产出吸附锚点。
## 度量函数由调用方注入：`func(node, slot_extents) -> BlockMetrics`，slot_extents 只含图上真实存在的槽位。


static func solve(graph: LogicGraph, measure: Callable) -> LayoutResult:
	var result := LayoutResult.new()
	if graph == null or not measure.is_valid():
		return result
	var measured: Dictionary[int, bool] = {}
	for chain_id in graph.chain_ids():
		for head_id in graph.slot_items(LogicGraph.ROOT, chain_id):
			_measure_node(graph, measure, head_id, result, measured)
	var placed: Dictionary[int, bool] = {}
	var chain_idx := 0
	for chain_id in graph.chain_ids():
		_place_chain(
			graph, result, graph.slot_items(LogicGraph.ROOT, chain_id),
			graph.chain_position(chain_id), LogicGraph.ROOT, chain_id, chain_idx, placed
		)
		chain_idx += 1
	return result


static func _measure_node(
	graph: LogicGraph,
	measure: Callable,
	id: int,
	result: LayoutResult,
	measured: Dictionary[int, bool]
) -> void:
	if measured.has(id) or result.metrics.has(id):
		return
	# 先打标记，防止损坏数据里的环把递归拖死
	measured[id] = true
	var node := graph.get_node_by_id(id)
	if node == null:
		return
	var slot_extents: Dictionary[StringName, Vector2] = {}
	for slot_id in node.slots:
		var children := node.peek_slot(slot_id)
		for child_id in children:
			_measure_node(graph, measure, child_id, result, measured)
		slot_extents[slot_id] = chain_extent(children, result)
	var metrics: BlockMetrics = measure.call(node, slot_extents)
	result.metrics[id] = metrics if metrics != null else BlockMetrics.new()


## 一条链的总尺寸（宽 = 最宽成员，高 = 首成员顶到末成员底）。
static func chain_extent(ids: Array[int], result: LayoutResult) -> Vector2:
	var width := 0.0
	var height := 0.0
	var previous: BlockMetrics = null
	for id in ids:
		var metrics: BlockMetrics = result.metrics.get(id)
		if metrics == null:
			continue
		width = maxf(width, metrics.size.x)
		if previous != null:
			height += previous.tail_offset.y
		previous = metrics
	if previous != null:
		height += previous.size.y
	return Vector2(width, height)


static func _place_chain(
	graph: LogicGraph,
	result: LayoutResult,
	ids: Array[int],
	origin: Vector2,
	owner_id: int,
	slot_id: StringName,
	chain_idx: int,
	placed: Dictionary[int, bool]
) -> void:
	var cursor := origin
	for index in ids.size():
		var id: int = ids[index]
		if placed.has(id):
			continue
		var metrics: BlockMetrics = result.metrics.get(id)
		if metrics == null:
			continue
		placed[id] = true
		result.rects[id] = Rect2(cursor, metrics.size)
		# 跳线路由查表用：链序号、链内行号、父级 C 形块 id
		result.chain_ids[id] = chain_idx
		result.orders[id] = result.orders.size()
		result.owners[id] = owner_id
		# 尾部锚点：插在这个块之后。
		result.anchors.append({
			"owner_id": owner_id,
			"slot": slot_id,
			"index": index + 1,
			"position": cursor + metrics.tail_offset,
			"width": metrics.tail_width,
			"kind": &"tail",
			"from_id": id,
		})
		# 槽位锚点：插进槽内容的最前面。
		for slot_key in metrics.slot_offsets:
			result.anchors.append({
				"owner_id": id,
				"slot": slot_key,
				"index": 0,
				"position": cursor + metrics.slot_offsets[slot_key],
				"width": metrics.slot_widths.get(slot_key, metrics.size.x),
				"kind": &"slot",
				"from_id": id,
			})
			_place_chain(
				graph, result, graph.slot_items(id, slot_key),
				cursor + metrics.slot_offsets[slot_key], id, slot_key, chain_idx, placed
			)
		cursor += metrics.tail_offset


#region 选择辅助（框选 / shift 范围选用的都是「视觉顺序」，不是数组下标）


## 全部顶层块按画布视觉顺序排的 id（先按链摆位，再按行；巢里的块不参与点选）。
## 布局不变时结果稳定 —— 只有它才能当 shift 范围选择的「有序列表」。
static func top_level_order(graph: LogicGraph, result: LayoutResult) -> Array[int]:
	var out: Array[int] = []
	if graph == null or result == null:
		return out
	var rows: Array[Dictionary] = []
	for chain_id in graph.chain_ids():
		var pos := graph.chain_position(chain_id)
		for id in graph.slot_items(LogicGraph.ROOT, chain_id):
			var rect := result.rect_of(id)
			rows.append({"y": rect.position.y, "x": pos.x, "id": id})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["y"]), float(b["y"])):
			return float(a["y"]) < float(b["y"])
		return float(a["x"]) < float(b["x"]))
	for row in rows:
		out.append(row["id"])
	return out


## 与矩形相交的顶层块 id（按视觉顺序）。
static func nodes_in_rect(graph: LogicGraph, result: LayoutResult, rect: Rect2) -> Array[int]:
	var out: Array[int] = []
	if graph == null or result == null:
		return out
	for id in top_level_order(graph, result):
		if result.rect_of(id).intersects(rect):
			out.append(id)
	return out

#endregion
