class_name GraphHistory
extends RefCounted

## 撤销/重做栈（快照式）：每次记录前后各拍一张 [method LogicGraph.to_dict]；图很小，快照换实现不出错。

signal changed()

const DEFAULT_LIMIT: int = 200

var _graph: LogicGraph
var _limit: int = DEFAULT_LIMIT
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _merge_key: StringName = &""


func _init(p_graph: LogicGraph, p_limit: int = DEFAULT_LIMIT) -> void:
	_graph = p_graph
	_limit = maxi(p_limit, 1)


## 记录一次修改：拍快照 → 执行 [param mutate] → 再拍快照。
## 内容没变不入栈；[param merge_key] 与上一条相同时合并为一条（输入框连续打字用）。
func record(label: String, mutate: Callable, merge_key: StringName = &"") -> void:
	if not mutate.is_valid():
		push_error("GraphHistory.record 收到无效的 Callable")
		return
	var before := _graph.to_dict()
	mutate.call()
	var after := _graph.to_dict()
	if LogicGraph.deep_equal(before, after):
		return
	if merge_key != &"" and merge_key == _merge_key and not _undo_stack.is_empty():
		var last: Dictionary = _undo_stack.back()
		last["after"] = after
		last["label"] = label
	else:
		_undo_stack.push_back({"label": label, "before": before, "after": after})
		if _undo_stack.size() > _limit:
			_undo_stack.pop_front()
	_merge_key = merge_key
	_redo_stack.clear()
	changed.emit()


## 结束当前合并段（例如输入框失焦），使后续修改不再并入上一条。
func flush_merge() -> void:
	_merge_key = &""


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()



func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var entry: Dictionary = _undo_stack.pop_back()
	_graph.load_dict(entry["before"])
	_redo_stack.push_back(entry)
	_merge_key = &""
	changed.emit()
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	var entry: Dictionary = _redo_stack.pop_back()
	_graph.load_dict(entry["after"])
	_undo_stack.push_back(entry)
	_merge_key = &""
	changed.emit()
	return true


func clear() -> void:
	if _undo_stack.is_empty() and _redo_stack.is_empty():
		return
	_undo_stack.clear()
	_redo_stack.clear()
	_merge_key = &""
	changed.emit()


func depth() -> Vector2i:
	return Vector2i(_undo_stack.size(), _redo_stack.size())
