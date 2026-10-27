class_name GraphCloner
extends RefCounted

## 子树深拷贝（复制块用）；副本是尚未入图的新节点，由调用方决定插到哪儿。
## 块引用指向子树内部的重映射到新节点，指向外部的不动；引用字段表由调用方传入。


## 深拷贝一棵子树（含槽位结构），返回 `{root, nodes}`；源节点不在图上时返回空字典。
static func clone(graph: LogicGraph, source_id: int, reference_fields: Callable) -> Dictionary:
	if graph == null or not graph.has(source_id):
		return {}
	# 源 id → 副本节点（先整棵建完，映射表才是全的）
	var copies: Dictionary = {}
	var order: Array[LogicNode] = []
	_clone_into(graph, source_id, copies, order)
	if order.is_empty():
		return {}
	for source_key in copies:
		var copy: LogicNode = copies[source_key]
		var fields: Array[StringName] = []
		if reference_fields.is_valid():
			fields.assign(reference_fields.call(copy))
		for field_id in fields:
			var target := LogicGraph.parse_link_ref(copy.get_field(field_id, ""))
			if target > 0 and copies.has(target):
				copy.put_field(field_id, LogicGraph.make_link_ref((copies[target] as LogicNode).id))
	return {"root": copies.get(source_id), "nodes": order}


static func _clone_into(
	graph: LogicGraph,
	source_id: int,
	copies: Dictionary,
	order: Array[LogicNode]
) -> LogicNode:
	var source := graph.get_node_by_id(source_id)
	if source == null or copies.has(source_id):
		return null
	var copy := graph.new_node(source.type_id)
	for key in source.fields:
		copy.fields[key] = source.fields[key]
	copies[source_id] = copy
	order.append(copy)
	for slot_id in source.slots:
		var children: Array[int] = []
		for child_id in source.peek_slot(slot_id):
			var child_copy := _clone_into(graph, child_id, copies, order)
			if child_copy != null:
				children.append(child_copy.id)
		if not children.is_empty():
			copy.slots[slot_id] = children
	return copy
