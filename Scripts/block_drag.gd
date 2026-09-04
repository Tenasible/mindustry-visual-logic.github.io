extends RefCounted
class_name BlockDrag
## 积木拖拽/落位/跳线目标的纯几何判定。
## 被 logic_blocks（基类）、block_shell、jump 复用，保证三处判定口径一致；
## 函数都是“只读+无副作用”，便于单测与后续扩展（跨容器拖放、滚动跟随等）。


## 子块竖直中心（全局坐标）。非 Control 或尚未布局的节点按 0 处理。
static func child_center_y(child: Node) -> float:
	if child is Control:
		var c := child as Control
		return c.global_position.y + c.size.y * 0.5
	return 0.0


## ignore 可为单个节点或节点数组，命中即视为“排除”。
static func _is_ignored(child: Node, ignore) -> bool:
	if ignore == null:
		return false
	if ignore is Array:
		return ignore.has(child)
	return ignore == child


## 容器内按视觉顺序的真实子块（跳过 ignore 指定的节点）。
static func real_blocks(container: Node, ignore = null) -> Array:
	var out := []
	for child in container.get_children():
		if _is_ignored(child, ignore):
			continue
		if child is Control:
			out.append(child)
	return out


## 计算插入槽位（0..real_count）：鼠标应插入的索引。
## 规则：统计“竖直中心位于鼠标上方的子块”个数——鼠标在该子块中心线以上时
## 插到它前面，以下则插到它后面。单调稳定、不随占位符高度产生震荡。
## ignore 可为单个占位节点或一组节点（整组拖动时的占位符）。
static func find_insert_slot(container: Node, mouse_y: float, ignore = null) -> int:
	var slot := 0
	for child in real_blocks(container, ignore):
		if child_center_y(child) < mouse_y:
			slot += 1
	return slot


## 返回竖直中心离鼠标最近的子块（供 Jump 箭头拖拽选择目标），可排除自身；
## 没有候选时返回 null（调用方按“无目标”处理）。
static func find_nearest_block(container: Node, mouse_y: float, exclude: Node = null) -> Node:
	var best: Node = null
	var best_dis := INF
	for child in real_blocks(container, exclude):
		if child == exclude:
			continue
		var dis := absf(child_center_y(child) - mouse_y)
		if dis < best_dis:
			best_dis = dis
			best = child
	return best


## 与给定全局矩形相交的子块（按全局坐标判定）。
static func blocks_in_rect(container: Node, rect: Rect2) -> Array:
	var out := []
	for child in real_blocks(container):
		var c := child as Control
		if c.size.x <= 0 and c.size.y <= 0:
			continue
		var r := Rect2(c.global_position, c.size)
		if r.intersects(rect):
			out.append(c)
	return out


## 把一组节点按原顺序连续插入容器 slot 位置：
## 先将 nodes 依序挂到容器末尾（已带父节点的用 reparent 脱离，无父节点的直接 add_child），
## 再自前向后把第 i 个移到 slot+i，实现“整组保序落位”。
static func insert_run(container: Node, nodes: Array, slot: int) -> void:
	if nodes.is_empty():
		return
	for n in nodes:
		var p = n.get_parent()
		if p == container:
			continue
		if p != null:
			n.reparent(container)
		else:
			container.add_child(n)
	for i in nodes.size():
		container.move_child(nodes[i], slot + i)


## 在包含 point 的宿主容器中选“面积最小（最深）者”。
## 调用方负责过滤（可见性/排除自身后代/积木栏），这里只做几何判定，便于单测。
static func smallest_host_at(hosts: Array, point: Vector2) -> Node:
	var best: Node = null
	var best_area := INF
	for c in hosts:
		if not (c is Control):
			continue
		var ctrl := c as Control
		var r := ctrl.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if not r.has_point(point):
			continue
		var area := r.size.x * r.size.y
		if area < best_area:
			best_area = area
			best = c
	return best
