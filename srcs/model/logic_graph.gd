class_name LogicGraph
extends RefCounted

## 逻辑程序的纯数据模型：画布上的若干条链，每条链是一个有序的节点 id 数组。
## 容器 = (owner_id, slot_id)：owner_id == [constant ROOT] 时 slot_id 是链 id，否则是
## 宿主节点的 <Nest> 槽位 id；顺序 = 数组下标，空位 = 不存在，不存绝对坐标。

const ROOT: int = 0

## 块引用（Jump 目标）的文本形式 `#<节点 id>`；不是这个形式的都视为未锁定。
const LINK_PREFIX: String = "#"


static func make_link_ref(id: int) -> String:
	return "%s%d" % [LINK_PREFIX, id] if id > 0 else ""


static func parse_link_ref(value: Variant) -> int:
	var text := String(value).strip_edges()
	if not text.begins_with(LINK_PREFIX):
		return ROOT
	var digits := text.substr(LINK_PREFIX.length())
	return int(digits) if digits.is_valid_int() else ROOT


## 引用字段现在指向的节点 id；值不是 `#<id>` 或节点已不在图上时返回 0（视为未锁定）。
func link_target(node: LogicNode, field_id: StringName) -> int:
	if node == null:
		return ROOT
	var target := parse_link_ref(node.get_field(field_id, ""))
	return target if target > 0 and _nodes.has(target) else ROOT


## 遍历每个节点的全部块引用字段：[param fields_of] 是 `节点 -> Array[StringName]`
## （「哪些字段是引用」的真相在块定义上，由调用方给），逐个回调 `{node, field_id, target}`。
## 值为空 / 指向不在图上的节点的目标按 0 上报（未锁定），与 [method link_target] 同一口径。
func each_link_ref(fields_of: Callable, emit: Callable) -> void:
	for id in all_ids():
		var node := get_node_by_id(id)
		if node == null:
			continue
		for field_id in fields_of.call(node):
			emit.call({
				"node": node,
				"field_id": field_id,
				"target": link_target(node, field_id),
			})


## 清掉指向 [param doomed] 里任一 id 的全部引用字段（删除块时与删除同处一条撤销记录）。
func clear_links_to(doomed: Dictionary, fields_of: Callable) -> void:
	each_link_ref(fields_of, func(ref: Dictionary) -> void:
		var target: int = ref["target"]
		if target > 0 and doomed.has(target):
			set_field((ref["node"] as LogicNode).id, ref["field_id"], ""))

signal structure_changed()
signal field_changed(id: int, field_id: StringName, value: Variant)
## 整体被替换（读档 / 撤销 / 重做），视图层应重建。
signal reset()

var _nodes: Dictionary[int, LogicNode] = {}
var _chains: Dictionary[StringName, Array] = {}
var _chain_positions: Dictionary[StringName, Vector2] = {}
var _next_id: int = 1
var _next_chain: int = 1


#region 查询

func has(id: int) -> bool:
	return _nodes.has(id)


func get_node_by_id(id: int) -> LogicNode:
	return _nodes.get(id)


func chain_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_chains.keys())
	return out


func chain_position(chain_id: StringName) -> Vector2:
	return _chain_positions.get(chain_id, Vector2.ZERO)


## 深度优先的全部节点 id（从各条链出发，孤儿节点不包含在内）。
func all_ids() -> Array[int]:
	var out: Array[int] = []
	for chain_id in _chains:
		for id in slot_items(ROOT, chain_id):
			_collect_subtree(id, out)
	return out


func subtree_ids(id: int) -> Array[int]:
	var out: Array[int] = []
	_collect_subtree(id, out)
	return out


func slot_items(owner_id: int, slot_id: StringName = &"") -> Array[int]:
	var out: Array[int] = []
	out.assign(_container_ref(owner_id, slot_id))
	return out


## 定位节点所在的容器，返回 {owner_id, slot, index}；不在图中时返回空字典。
func locate(id: int) -> Dictionary:
	if not _nodes.has(id):
		return {}
	for chain_id in _chains:
		var index := slot_items(ROOT, chain_id).find(id)
		if index >= 0:
			return {"owner_id": ROOT, "slot": chain_id, "index": index}
	for owner_id in _nodes:
		var node: LogicNode = _nodes[owner_id]
		for slot_id in node.slots:
			var index := node.peek_slot(slot_id).find(id)
			if index >= 0:
				return {"owner_id": owner_id, "slot": slot_id, "index": index}
	return {}


#endregion


#region 链管理

func create_chain(pos: Vector2 = Vector2.ZERO) -> StringName:
	var chain_id := StringName("c%d" % _next_chain)
	_next_chain += 1
	var ids: Array[int] = []
	_chains[chain_id] = ids
	_chain_positions[chain_id] = pos
	structure_changed.emit()
	return chain_id


## 取第一条链；一条都没有时按 [param fallback_pos] 新建一条。
func primary_chain(fallback_pos: Vector2 = Vector2.ZERO) -> StringName:
	for chain_id in _chains:
		return chain_id
	return create_chain(fallback_pos)


#endregion


#region 结构修改

## 创建一个新节点（**尚未入图**，请再用 [method insert_node] 放入容器）。
func new_node(type_id: StringName) -> LogicNode:
	var node := LogicNode.new(_next_id, type_id)
	_next_id += 1
	return node


## 把节点插入到容器的 [param index] 处；[param index] 为负表示追加到末尾。
func insert_node(node: LogicNode, owner_id: int, slot_id: StringName = &"", index: int = -1) -> bool:
	if node == null or _nodes.has(node.id) or not _can_host(owner_id, slot_id):
		return false
	_nodes[node.id] = node
	_sync_next_id(node.id)
	_insert_at(_container_ref(owner_id, slot_id, true), node.id, index)
	structure_changed.emit()
	return true


## 把一棵尚未入图的子树整体放进容器（[param nodes] 第一个必须是根），中途不发信号。
func insert_subtree(nodes: Array[LogicNode], owner_id: int, slot_id: StringName = &"", index: int = -1) -> bool:
	if nodes.is_empty() or not _can_host(owner_id, slot_id):
		return false
	for node in nodes:
		if node == null or _nodes.has(node.id):
			return false
	for node in nodes:
		_nodes[node.id] = node
		_sync_next_id(node.id)
	_insert_at(_container_ref(owner_id, slot_id, true), nodes[0].id, index)
	structure_changed.emit()
	return true

## 删除节点及其整棵子树。链被清空时会一并删除该链。
func remove_node(id: int) -> bool:
	var where := locate(id)
	if where.is_empty():
		return false
	var doomed: Array[int] = []
	_collect_subtree(id, doomed)
	_detach(where)
	_drop_empty_container(where)
	for victim in doomed:
		_nodes.erase(victim)
	structure_changed.emit()
	return true


## 移动单个节点；拒绝把自己移进自己或自己的子孙（否则成环）。
func move_node(id: int, owner_id: int, slot_id: StringName = &"", index: int = -1) -> bool:
	return move_nodes([id] as Array[int], owner_id, slot_id, index)

## 同一容器里「这个块及其后面的所有块」（拖动时一起走）。
func tail_ids(id: int) -> Array[int]:
	var at := locate(id)
	if at.is_empty():
		return [id] as Array[int]
	var items := slot_items(at["owner_id"], at["slot"])
	var out: Array[int] = []
	for i in range(int(at["index"]), items.size()):
		out.append(items[i])
	return out


## 把一串有先后顺序的节点整体搬到目标容器（逐个搬会因下标变化而错位）。
## 通用入口：按参数顺序落位；链式搬移（后面的跟着走）用 [method move_tail]。
func move_nodes(ids: Array[int], owner_id: int, slot_id: StringName = &"", index: int = -1) -> bool:
	if ids.is_empty() or not _can_host(owner_id, slot_id):
		return false
	for id in ids:
		if not _nodes.has(id):
			return false
		if owner_id != ROOT and (owner_id == id or _is_descendant(owner_id, id)):
			return false
	var places: Array[Dictionary] = []
	var same_container := true
	var removed_before := 0
	for id in ids:
		var at := locate(id)
		if at.is_empty():
			return false
		places.append(at)
		if at["owner_id"] != owner_id or at["slot"] != slot_id:
			same_container = false
		elif index >= 0 and int(at["index"]) < index:
			removed_before += 1
	var target := index
	if target < 0:
		target = slot_items(owner_id, slot_id).size()
	elif same_container:
		target = index - removed_before
	# 摘出必须倒序：_detach 按记录下来的下标移除，先摘前面的会让后面的下标整体左移
	for i in range(places.size() - 1, -1, -1):
		_detach(places[i])
	var container := _container_ref(owner_id, slot_id, true)
	for i in ids.size():
		_insert_at(container, ids[i], target + i)
	for at in places:
		_drop_empty_container(at)
	structure_changed.emit()
	return true

## 把「一个块 + 它后面的所有块」一起搬（拖拽搬移的直觉：后面的跟着走，顺序不乱）。
## 展开的序列一定在原容器内连续，照旧按参数顺序落位，只是追加一个空位让位。
func move_tail(ids: Array[int], owner_id: int, slot_id: StringName = &"", index: int = -1) -> bool:
	if ids.is_empty():
		return false
	# 同容器搬移时，尾巴这一串会先在原位置整体消失、再插到 index 处：
	# 落在串内部的 index 等于没动，按搬完后的视觉位置多让一格。
	var at := locate(ids[0])
	if not at.is_empty() and at["owner_id"] == owner_id and at["slot"] == slot_id \
			and index > int(at["index"]):
		index += 1
	return move_nodes(ids, owner_id, slot_id, index)

## 新建一条链并把尚未入图的节点作为首成员（只发一次结构变更；撤销闭包里也能安全调用）。
func insert_in_new_chain(node: LogicNode, pos: Vector2) -> StringName:
	var chain_id := StringName("c%d" % _next_chain)
	if node == null or _nodes.has(node.id):
		return &""
	_next_chain += 1
	var ids: Array[int] = [node.id]
	_chains[chain_id] = ids
	_chain_positions[chain_id] = pos
	_nodes[node.id] = node
	_sync_next_id(node.id)
	structure_changed.emit()
	return chain_id


## 把一组节点搬到画布上新开的一条链（只发一次结构变更；搬不动时不留空链）。
func move_nodes_to_new_chain(ids: Array[int], pos: Vector2) -> StringName:
	if ids.is_empty():
		return &""
	var chain_id := StringName("c%d" % _next_chain)
	_next_chain += 1
	var ids_empty: Array[int] = []
	_chains[chain_id] = ids_empty
	_chain_positions[chain_id] = pos
	if move_nodes(ids, ROOT, chain_id, -1):
		return chain_id
	# 搬不动（不在图上 / 成环）：把刚建的空链收掉，不留空壳
	_chains.erase(chain_id)
	_chain_positions.erase(chain_id)
	return &""
func set_field(id: int, field_id: StringName, value: Variant) -> bool:
	var node := get_node_by_id(id)
	if node == null:
		return false
	if deep_equal(node.get_field(field_id, null), value):
		return true
	node.put_field(field_id, value)
	field_changed.emit(id, field_id, value)
	return true


func clear() -> void:
	_nodes.clear()
	_chains.clear()
	_chain_positions.clear()
	_next_id = 1
	_next_chain = 1
	reset.emit()


#endregion


#region 序列化

func to_dict() -> Dictionary:
	var nodes_out: Array = []
	var ids: Array[int] = []
	ids.assign(_nodes.keys())
	ids.sort()
	for id in ids:
		nodes_out.append((_nodes[id] as LogicNode).to_dict())
	var chains_out: Dictionary = {}
	for chain_id in _chains:
		var ids_out: Array = []
		ids_out.assign(slot_items(ROOT, chain_id))
		chains_out[String(chain_id)] = ids_out
	var positions_out: Dictionary = {}
	for chain_id in _chain_positions:
		var pos: Vector2 = _chain_positions[chain_id]
		positions_out[String(chain_id)] = [pos.x, pos.y]
	return {
		"next_id": _next_id,
		"next_chain": _next_chain,
		"chains": chains_out,
		"chain_positions": positions_out,
		"nodes": nodes_out,
	}


static func from_dict(data: Dictionary) -> LogicGraph:
	var graph := LogicGraph.new()
	graph.load_dict(data)
	return graph


## 就地载入（保留对象引用，便于视图层继续持有同一张图）。载入后发出 [signal reset]。
func load_dict(data: Dictionary) -> void:
	_chains.clear()
	_chain_positions.clear()
	# 同 id 的节点对象要复用：撤销/读档后外部持有的引用仍指向图上的那一个
	var incoming: Dictionary[int, LogicNode] = {}
	for raw in data.get("nodes", []):
		var parsed := LogicNode.from_dict(raw)
		incoming[parsed.id] = parsed
	for id in _nodes.keys():
		if not incoming.has(id):
			_nodes.erase(id)
	for id in incoming:
		var fresh: LogicNode = incoming[id]
		var existing: LogicNode = _nodes.get(id)
		if existing == null:
			_nodes[id] = fresh
		else:
			existing.type_id = fresh.type_id
			existing.fields = fresh.fields
			existing.slots = fresh.slots
	var chains_raw: Dictionary = data.get("chains", {})
	for key in chains_raw:
		var ids: Array[int] = []
		ids.assign(chains_raw[key])
		_chains[StringName(key)] = ids
	var positions_raw: Dictionary = data.get("chain_positions", {})
	for key in positions_raw:
		var pair: Array = positions_raw[key]
		if pair.size() >= 2:
			_chain_positions[StringName(key)] = Vector2(pair[0], pair[1])
	_next_id = int(data.get("next_id", 1))
	_next_chain = int(data.get("next_chain", 1))
	for id in _nodes:
		_sync_next_id(id)
	reset.emit()


#endregion


#region 内部

func _insert_at(arr: Array, value: int, index: int) -> void:
	if index < 0 or index > arr.size():
		arr.push_back(value)
	else:
		arr.insert(index, value)


## 取容器数组本体（[param create] 为真时按需建槽位；为假时返回临时空数组，改它不影响图）。
func _container_ref(owner_id: int, slot_id: StringName, create: bool = false) -> Array:
	if owner_id == ROOT:
		return _chains.get(slot_id, [])
	var node := get_node_by_id(owner_id)
	if node == null:
		return []
	if create:
		return node.slot(slot_id)
	return node.slots.get(slot_id, [])


## 该容器现在能否接收成员：根要链存在，节点要自身在图上（槽位按需建立）。
func _can_host(owner_id: int, slot_id: StringName) -> bool:
	return _chains.has(slot_id) if owner_id == ROOT else _nodes.has(owner_id)


func _detach(where: Dictionary) -> void:
	if where.is_empty():
		return
	var items := _container_ref(where["owner_id"], where["slot"])
	var index: int = where["index"]
	if index >= 0 and index < items.size():
		items.remove_at(index)


## 容器空了就删掉它：链不留空壳，节点槽位也不留空数组当占位。
func _drop_empty_container(where: Dictionary) -> void:
	if where.is_empty() or not _container_ref(where["owner_id"], where["slot"]).is_empty():
		return
	var owner_id: int = where["owner_id"]
	var slot_id: StringName = where["slot"]
	if owner_id == ROOT:
		_chains.erase(slot_id)
		_chain_positions.erase(slot_id)
		return
	var owner := get_node_by_id(owner_id)
	if owner != null:
		owner.slots.erase(slot_id)


func _collect_subtree(id: int, out: Array[int]) -> void:
	if not _nodes.has(id) or out.has(id):
		return
	out.append(id)
	var node: LogicNode = _nodes[id]
	for slot_id in node.slots:
		for child_id in node.peek_slot(slot_id):
			_collect_subtree(child_id, out)


func _is_descendant(candidate: int, ancestor: int) -> bool:
	var cursor := candidate
	var guard := _nodes.size() + 1
	while cursor != ROOT and guard > 0:
		guard -= 1
		var where := locate(cursor)
		if where.is_empty():
			return false
		var owner_id: int = where["owner_id"]
		if owner_id == ancestor:
			return true
		cursor = owner_id
	return false


func _sync_next_id(id: int) -> void:
	if id >= _next_id:
		_next_id = id + 1


## 结构与数值的深比较（Dictionary / Array 在 GDScript 里不保证按值比较）。
static func deep_equal(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if ta != tb:
		var a_number := ta == TYPE_INT or ta == TYPE_FLOAT
		var b_number := tb == TYPE_INT or tb == TYPE_FLOAT
		if a_number and b_number:
			return is_equal_approx(float(a), float(b))
		return false
	match ta:
		TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			if da.size() != db.size():
				return false
			for key in da:
				if not db.has(key):
					return false
				if not deep_equal(da[key], db[key]):
					return false
			return true
		TYPE_ARRAY:
			var aa: Array = a
			var ab: Array = b
			if aa.size() != ab.size():
				return false
			for i in aa.size():
				if not deep_equal(aa[i], ab[i]):
					return false
			return true
		TYPE_VECTOR2:
			return (a as Vector2).is_equal_approx(b)
		_:
			return a == b

#endregion
