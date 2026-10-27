class_name BlockSelection
extends RefCounted

## 多选集合：按节点 id 存「哪些块被选中」，与容器 / 视图 / 图本身解耦。
## 只认 id（图里的唯一标识），视图销毁重建后选中集仍然有效；不持有引用，
## 所以不存在「释放后残留」——读侧先判 [method LogicGraph.has] 再取。

signal changed


func is_selected(id: int) -> bool:
	return _selected.has(id)


func size() -> int:
	return _selected.size()


func is_empty() -> bool:
	return _selected.is_empty()


## 选中集副本（插入顺序）。
func get_selected() -> Array[int]:
	return _selected.duplicate()


func clear() -> void:
	if _selected.is_empty():
		return
	_selected.clear()
	changed.emit()


func select_only(id: int) -> void:
	if _selected.size() == 1 and _selected[0] == id:
		return
	_selected = [id] as Array[int]
	changed.emit()


## 整体替换为给定集合（保持参数顺序）。
func set_many(ids: Array[int]) -> void:
	if ids == _selected:
		return
	_selected = ids.duplicate()
	changed.emit()


func add(id: int) -> void:
	if _selected.has(id):
		return
	_selected.append(id)
	changed.emit()


func remove(id: int) -> void:
	var before := _selected.size()
	_selected.erase(id)
	if _selected.size() != before:
		changed.emit()


func toggle(id: int) -> void:
	if _selected.has(id):
		_selected.erase(id)
	else:
		_selected.append(id)
	changed.emit()


## 按「锚点下标 + 目标下标」选中一段（shift 点击）；有序列表由调用方给（视觉顺序）。
func select_range(ordered: Array[int], anchor_index: int, to_index: int) -> void:
	if ordered.is_empty():
		return
	var lo := maxi(0, mini(anchor_index, to_index))
	var hi := mini(ordered.size() - 1, maxi(anchor_index, to_index))
	var picked: Array[int] = []
	for i in range(lo, hi + 1):
		picked.append(ordered[i])
	set_many(picked)


var _selected: Array[int] = []
