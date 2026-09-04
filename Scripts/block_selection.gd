extends RefCounted
class_name BlockSelection
## 通用“多选模型”：与具体容器/UI 解耦，只维护“哪些节点被选中”的集合。
## 供框选、shift 范围、ctrl 切换、批量拖动等复用；后续任何需要选择态的
## 列表式 UI（文件列表、图层列表……）都可直接使用。

signal changed(sel: BlockSelection)

var _selected: Array = []


func is_selected(node: Node) -> bool:
	return _selected.has(node)


func size() -> int:
	return _selected.size()


func is_empty() -> bool:
	return _selected.is_empty()


## 返回选中集合（副本，插入顺序）
func get_selected() -> Array:
	return _selected.duplicate()


## 清空选择；无变化时静默。
func clear() -> void:
	if _selected.is_empty():
		return
	_selected.clear()
	changed.emit(self)


## 只选中这一个节点
func select_only(node: Node) -> void:
	if _selected.size() == 1 and _selected[0] == node:
		return
	_selected = [node]
	changed.emit(self)


## 把集合替换为给定节点（保持参数顺序）
func set_many(nodes: Array) -> void:
	var cleaned := nodes.duplicate()
	if cleaned == _selected:
		return
	_selected = cleaned
	changed.emit(self)


## 追加选中一个节点（不影响其它已选项）
func add(node: Node) -> void:
	if _selected.has(node):
		return
	_selected.append(node)
	changed.emit(self)


## 从选中集中移除一个节点
func remove(node: Node) -> void:
	var before := _selected.size()
	_selected.erase(node)
	if _selected.size() == before:
		return
	changed.emit(self)


func toggle(node: Node) -> void:
	if _selected.has(node):
		_selected.erase(node)
	else:
		_selected.append(node)
	changed.emit(self)


## 按“锚点 index + 目标 index”选中一段（shift 点击）。由调用方提供有序列表。
func select_range(ordered: Array, anchor_index: int, to_index: int) -> void:
	if ordered.is_empty():
		return
	var lo := mini(anchor_index, to_index)
	var hi := maxi(anchor_index, to_index)
	lo = maxi(0, lo)
	hi = mini(ordered.size() - 1, hi)
	var picked := []
	for i in range(lo, hi + 1):
		picked.append(ordered[i])
	set_many(picked)


## 清理已失效节点（被释放/移出等）；返回是否有清理
func prune_valid() -> bool:
	var changed_any := false
	var kept := []
	for n in _selected:
		if is_instance_valid(n):
			kept.append(n)
		else:
			changed_any = true
	if changed_any:
		_selected = kept
		changed.emit(self)
	return changed_any
