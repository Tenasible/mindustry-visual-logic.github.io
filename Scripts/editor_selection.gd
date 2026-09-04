extends Node
## 编辑器页的“框选 + 批量拖动 + 选中管理”控制器（作为 Editor 场景的 SelectionHost 子节点）。
## - 在工程区空白处按住左键拖动 -> 框选（矩形实时命中积木）；
## - 点击空白区域 -> 清空选择；
## - shift+点击积木 -> 范围选择；ctrl+点击 -> 切换；
## - 普通点击未选中积木 -> 单选并开始单块拖动（走 LogicBlocks 原有逻辑）；
## - 点击已选中的积木且多选 -> 整组拖动（组占位预览 + 组落位/删除）。
## 选择状态存放在 BlockSelection（通用模型）里，本类只负责交互与视觉。

const BlockDrag := preload("res://Scripts/block_drag.gd")
const SelectionOverlayScn := preload("res://Scripts/selection_overlay.gd")
const SelectionModelScn := preload("res://Scripts/block_selection.gd")

const BAND_MIN_DRAG := 6.0          # 超过此位移才视为“框选”，否则视为“点击空白=取消选择”
const DELETE_OFFSET_X := 100.0      # 与单块拖动的删除区阈值保持一致
const CLICK_MAX_MOVE := 6.0         # 单击 vs 拖动阈值：按下-松手间积木位移小于此值视为“点击”（选中）

var editor: Control
var container: Control           # %UserBlocks（Control 才有 global_position 几何）
var dragging_node: Node          # 主场景 Dragging（存放拖动中的积木）

var selection = SelectionModelScn.new()   # BlockSelection 通用模型
var overlay: Control

var _range_anchor := -1            # shift 范围选择的锚点（容器内 index）

# “点击选中 vs 拖动”手势：按下时暂不选中，等 LogicBlocks 单块拖放结束
# 再按位移决定（原地点击才选中；真的拖动过则松手不残留选中）。
var _pending_block: Node = null
var _pending_start := Vector2.ZERO
var _pending_max := 0.0

# 框选状态
var _band_active := false
var _band_start := Vector2.ZERO

# 整组拖动状态
var _group_blocks: Array = []
var _group_placeholders: Array = []
var _group_delta := Vector2.ZERO
var _group_offsets: Array = []
var _group_slot := -1
var _group_active := false


func setup(editor_root: Control, drag: Node) -> void:
	editor = editor_root
	container = editor_root.get_node_or_null("%UserBlocks") as Control
	dragging_node = drag
	if container == null:
		push_warning("SelectionHost.setup: 找不到 %UserBlocks")
		return
	selection.changed.connect(_on_selection_changed)
	overlay = SelectionOverlayScn.new()
	overlay.name = "SelectionOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 120
	editor_root.add_child(overlay)


func _mouse_global() -> Vector2:
	if editor != null:
		return editor.get_global_mouse_position()
	return Vector2.ZERO


func _process(_delta: float) -> void:
	_track_pending()
	if not _group_active and not _band_active:
		# 静态选择也可能因容器重排/加载而变化：每帧刷新高亮框（代价小）
		# prune_valid 顺带清掉被释放节点的残留引用（如拖到删除区销毁的积木）
		selection.prune_valid()
		_refresh_boxes()
		return
	# 释放发生在窗口外/失焦时的兜底：按钮已松开则结束当前动作
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not held:
		if _band_active:
			_finish_band()
		elif _group_active:
			_finish_group()
	else:
		if _band_active:
			_update_band()
		elif _group_active:
			_update_group()
	_refresh_boxes()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if _group_active:
				return
			_try_begin_band()
		else:
			if _band_active:
				_finish_band()
			elif _group_active:
				_finish_group()
	elif event is InputEventMouseMotion:
		if _band_active:
			_update_band()
		elif _group_active:
			_update_group()


# ---------- 框选 ----------

func _try_begin_band() -> void:
	if container == null or editor == null:
		return
	var mouse := _mouse_global()
	if _point_over_any_block(mouse):
		return
	var scroll := editor.get_node_or_null("%UserBlockScroll") as Control
	if scroll == null or not scroll.get_global_rect().has_point(mouse):
		return
	_band_active = true
	_band_start = mouse
	overlay.set_band(_to_local_rect(Rect2(_band_start, Vector2.ZERO)), true)


func _update_band() -> void:
	var mouse := _mouse_global()
	var g := Rect2(_band_start, Vector2.ZERO)
	g = g.expand(mouse)              # 规范化矩形
	overlay.set_band(_to_local_rect(g), true)
	var hit := BlockDrag.blocks_in_rect(container, g)
	selection.set_many(hit)


func _finish_band() -> void:
	_band_active = false
	overlay.set_band(Rect2(), false)
	var mouse := _mouse_global()
	var g := Rect2(_band_start, Vector2.ZERO)
	g = g.expand(mouse)
	if g.size.x < BAND_MIN_DRAG and g.size.y < BAND_MIN_DRAG:
		# 视为“点击空白”：取消选择
		selection.clear()
	else:
		selection.set_many(BlockDrag.blocks_in_rect(container, g))
	_refresh_boxes()


# ---------- 点击积木（选择逻辑入口，由 LogicBlocks 基类调用） ----------

## 返回 true 表示本控制器接管了这次按下（多选切换/范围选择/组拖动）；
## 返回 false 表示让 LogicBlocks 继续原有“单块拖动”流程。
func editor_on_block_press(block: Node) -> bool:
	if container == null or not container.is_ancestor_of(block):
		return false
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var ordered := _ordered_blocks()
	var idx := ordered.find(block)

	if ctrl:
		selection.toggle(block)
		_range_anchor = idx
		return true

	if shift:
		if _range_anchor < 0:
			_range_anchor = idx
			selection.select_only(block)
		else:
			selection.select_range(ordered, _range_anchor, idx)
		return true

	if selection.is_selected(block) and selection.size() > 1:
		_begin_group_drag(block)
		return true

	# 普通点击/单块拖动：先不选中。选中延迟到手势结束（_track_pending）再决定——
	# 原地点击才选中；真的拖动过则松手不残留选中（曾因按下即 select_only，
	# 导致“拖动放下后积木仍被选中”破坏手感）。
	_pending_block = block
	_pending_start = (block as Control).global_position
	_pending_max = 0.0
	_range_anchor = idx
	return false


# ---------- 点击 vs 拖动的手势判定 ----------

## 每帧跟踪“单块拖放手势”的进度：LogicBlocks 把 moving 置 false（commit_drop）即手势结束。
## 结束时机：
## - 积木在拖动中被销毁（删除区）-> 放弃待定，选中集里的失效引用由 prune_valid 清理；
## - 位移 < CLICK_MAX_MOVE（原地点击）-> 选中该积木（等同旧“按下即选中”的最终效果）；
## - 位移 >= CLICK_MAX_MOVE（真的拖动过）-> clear()，拖动放下不残留选中。
func _track_pending() -> void:
	if _pending_block == null:
		return
	var b: Node = _pending_block
	if not is_instance_valid(b):
		_pending_block = null
		return
	var moving: bool = b.get("moving")
	if moving:
		var c := b as Control
		if c != null:
			var d := c.global_position.distance_to(_pending_start)
			if d > _pending_max:
				_pending_max = d
		return
	# 手势已结束（commit_drop 已置 moving=false）
	_pending_block = null
	if _pending_max >= CLICK_MAX_MOVE:
		selection.clear()
	else:
		selection.select_only(b)
	_refresh_boxes()


# ---------- 整组拖动 ----------

func _begin_group_drag(grabbed: Node) -> void:
	var ordered := _ordered_blocks()
	var blocks: Array = []
	for b in ordered:
		if selection.is_selected(b):
			blocks.append(b)
	if not blocks.has(grabbed):
		blocks.insert(0, grabbed)
	if blocks.size() < 2:
		return

	var base_pos := (grabbed as Control).global_position
	var mouse := _mouse_global()
	_group_delta = base_pos - mouse
	_group_offsets.clear()
	_group_blocks.clear()
	for b in blocks:
		_group_blocks.append(b)
		_group_offsets.append((b as Control).global_position - base_pos)
		if dragging_node != null and b.get_parent() != dragging_node:
			b.reparent(dragging_node)        # 先脱离原容器再挂到 Dragging（add_child 不允许已有父节点）
		b.z_index = 1
		if b.has_method("_hide_drag_index"):
			b._hide_drag_index()

	_group_placeholders.clear()
	for b in blocks:
		var ph := PanelContainer.new()
		var c := b as Control
		ph.custom_minimum_size = c.size if c.size.y > 0 else Vector2(300, 40)
		container.add_child(ph)
		_group_placeholders.append(ph)

	_group_active = true
	_group_slot = -1
	_update_group()


func _update_group() -> void:
	if not _group_active:
		return
	var mouse := _mouse_global()
	for i in _group_blocks.size():
		var b := _group_blocks[i] as Control
		b.global_position = mouse + _group_delta + _group_offsets[i]

	var del: bool = mouse.x < container.global_position.x - DELETE_OFFSET_X
	for b in _group_blocks:
		b.modulate = Color(1, 1, 1, 0.6) if del else Color(1, 1, 1, 1)

	var slot := BlockDrag.find_insert_slot(container, mouse.y, _group_placeholders)
	if slot != _group_slot:
		_group_slot = slot
		for ph in _group_placeholders:
			if ph.get_parent() != null:
				container.remove_child(ph)
		BlockDrag.insert_run(container, _group_placeholders, slot)
	_refresh_boxes()


func _finish_group() -> void:
	if not _group_active:
		return
	_group_active = false
	var mouse := _mouse_global()
	var del: bool = mouse.x < container.global_position.x - DELETE_OFFSET_X

	# 移除组占位符
	for ph in _group_placeholders:
		if is_instance_valid(ph) and ph.get_parent() != null:
			container.remove_child(ph)
			ph.queue_free()
	_group_placeholders.clear()

	if del:
		# 整组删除
		for b in _group_blocks:
			if is_instance_valid(b):
				b.modulate = Color(1, 1, 1, 1)
				if b.has_method("_restore_drag_index"):
					b._restore_drag_index()
				b.queue_free()
	else:
		var slot := _group_slot
		if slot < 0:
			slot = 0
		BlockDrag.insert_run(container, _group_blocks, slot)
		for b in _group_blocks:
			b.z_index = 0
			b.modulate = Color(1, 1, 1, 1)
			if b.has_method("_restore_drag_index"):
				b._restore_drag_index()
		if container.has_method("_on_block_moved"):
			container._on_block_moved()
	_group_blocks.clear()
	_group_offsets.clear()
	_group_delta = Vector2.ZERO
	_group_slot = -1
	_refresh_boxes()


# ---------- 视觉 ----------

func _on_selection_changed(_sel) -> void:
	_refresh_boxes()


func _refresh_boxes() -> void:
	if overlay == null:
		return
	var rects: Array = []
	if selection != null:
		for n in selection.get_selected():
			if is_instance_valid(n) and n is Control and n.get_parent() == container:
				var c := n as Control
				rects.append(_to_local_rect(Rect2(c.global_position, c.size)))
	overlay.set_boxes(rects)


func _to_local_rect(g: Rect2) -> Rect2:
	# GUI 平面无旋转/缩放，本地坐标 = 全局坐标 - 覆盖层左上角（其锚点铺满编辑器页）
	var origin := overlay.global_position
	var tl := g.position - origin
	var br := g.end - origin
	return Rect2(tl, br - tl)


func _ordered_blocks() -> Array:
	var out := []
	if container == null:
		return out
	for c in container.get_children():
		if c is Control:
			out.append(c)
	return out


func _point_over_any_block(p: Vector2) -> bool:
	for c in _ordered_blocks():
		if (c as Control).get_global_rect().has_point(p):
			return true
	return false
