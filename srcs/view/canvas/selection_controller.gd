class_name SelectionController
extends Node

## 画布上的「框选 + 多选 + 整组拖动」控制器。
##
## 拥有 [BlockSelection]（按节点 id 存的选择集），框选矩形与命中结果每帧推给画布画；
## 点击 / shift / ctrl 的分流由 [method BlockView.press_requested] 进来到
## [method editor_on_block_press]，整组拖动则另开一条「搬一组」的拖拽会话。
##
## 组判定基于「视觉顺序」（[LayoutSolver.top_level_order]），不是链下标：
## 同一条链上的选中块保序，跨链时按「链摆位 → 行」分组，组间顺序稳定。

## 位移超过它才算「框选」，否则当作点击空白 = 清空选择。
const BAND_MIN_DRAG := 6.0
## 单击 vs 拖动：按下到松手块挪了这么多像素以上 = 真拖动，松手不残留选中。
const CLICK_MAX_MOVE := 6.0

var canvas: EditorCanvas
var area: SubViewportContainer
## 组拖拽会话复用主拖拽控制器（搬块 / 删除区 / 落点全一套）。
var drag: DragController

var selection := BlockSelection.new()

## shift 范围选择的锚点：视觉顺序里的下标（-1 = 还没点过）。
var _range_anchor: int = -1
## 「按下暂不选中」的待定手势：等拖动会话结束再按位移判定点击 / 拖动。
var _pending_id: int = 0
var _pending_start := Vector2.ZERO
var _pending_max := 0.0
## 框选状态。
var _band_active := false
var _band_start := Vector2.ZERO
var _band_rect := Rect2()

func _ready() -> void:
	set_process(false)
	selection.changed.connect(_on_selection_changed)


## 画布重建 / 换图后由标签页调用：清掉失效 id 的选中态（选中集存的是 id，
## 图换掉后旧 id 指向不存在的节点，继续高亮会画在空气上）。
func prune() -> void:
	var kept: Array[int] = []
	for id in selection.get_selected():
		if canvas != null and canvas.graph != null and canvas.graph.has(id):
			kept.append(id)
	selection.set_many(kept)


func _process(_delta: float) -> void:
	_track_pending()
	if _band_active:
		_update_band()
		# 失焦 / 窗口外松手的兜底：键已松开就按当前矩形收尾
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_band()
	if not _band_active and _pending_id == 0:
		set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if canvas == null or canvas.layout == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if not _band_active:
				_try_begin_band()
		elif _band_active:
			_finish_band()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _band_active:
		_update_band()


#region 框选

func _try_begin_band() -> void:
	# 本节点是 SubViewport 的子节点，只有鼠标在画布范围内才会收到事件，不需要再用 area 判定
	var screen := get_viewport().get_mouse_position()
	var vp_rect := Rect2(Vector2.ZERO, get_viewport().size)
	if not vp_rect.has_point(screen):
		return
	var world := _world_mouse()
	# 按在块上不框选（那是块自己的事）；巢里的子块与顶层块都算「有块」
	if canvas.node_at_world(world) != 0:
		return
	_band_active = true
	_band_start = world
	_band_rect = Rect2(world, Vector2.ZERO)
	canvas.nCamera.stop_panning()
	set_process(true)


func _update_band() -> void:
	_band_rect = Rect2(_band_start, Vector2.ZERO).expand(_world_mouse())
	selection.set_many(LayoutSolver.nodes_in_rect(canvas.graph, canvas.layout, _band_rect))
	canvas.set_selection_band(_band_rect, true)


func _finish_band() -> void:
	_band_active = false
	canvas.set_selection_band(Rect2(), false)
	if _band_rect.size.x < BAND_MIN_DRAG and _band_rect.size.y < BAND_MIN_DRAG:
		selection.clear()
	else:
		selection.set_many(LayoutSolver.nodes_in_rect(canvas.graph, canvas.layout, _band_rect))
	_range_anchor = -1

#endregion


#region 点击 / shift / ctrl 分流（由 BlockView 按下时调用）

## 块按下时由 [BlockView.press_requested] 调进来；接管（ctrl/shift 切换、组拖）时
## 调 [method BlockView.consume_press] 拦住随后的 drag_requested，没接管则放行单块拖动。
func editor_on_block_press(view: BlockView, offset: Vector2, ctrl: bool, shift: bool) -> void:
	if canvas == null or canvas.graph == null or view == null or view.node == null:
		return
	var id: int = view.node.id
	if not canvas.graph.has(id):
		return
	var top := _top_level_id(id)
	# 巢里的子块不参与多选（它跟着父块走）：交还原有拖动
	if top == 0:
		_range_anchor = -1
		return
	var ordered := LayoutSolver.top_level_order(canvas.graph, canvas.layout)
	var idx := ordered.find(top)

	if ctrl:
		selection.toggle(top)
		_range_anchor = idx
		view.consume_press()
		return
	if shift:
		if _range_anchor < 0:
			_range_anchor = idx
			selection.select_only(top)
		else:
			selection.select_range(ordered, _range_anchor, idx)
		view.consume_press()
		return
	if selection.is_selected(top) and selection.size() > 1:
		if drag != null:
			drag.start_group_from_view(_group_roots(), top, offset)
		view.consume_press()
		return

	# 普通点击 / 单块拖动：按下先不选中，等手势结束按位移判定（原地点击才选中，
	# 真的拖动过则 clear —— 曾因按下即 select_only，拖完放下块仍被选中，手感很差）。
	_pending_id = top
	_pending_start = canvas.layout.rect_of(top).position if canvas.layout != null else Vector2.ZERO
	_pending_max = 0.0
	_range_anchor = idx
	set_process(true)


## 巢里的块归属到它的顶层块；本身就在顶层则返回自身。0 = 不在图上。
func _top_level_id(id: int) -> int:
	if canvas == null or canvas.graph == null:
		return 0
	var current := id
	while canvas.graph.has(current):
		var at := canvas.graph.locate(current)
		if at.is_empty():
			return 0
		var owner_id: int = int(at["owner_id"])
		if owner_id == LogicGraph.ROOT:
			return current
		current = owner_id
	return 0


## 选中集展开成「要搬的顶层块」：按视觉顺序保序、去掉巢里块与不在图上的。
func _group_roots() -> Array[int]:
	var out: Array[int] = []
	if canvas == null or canvas.graph == null or canvas.layout == null:
		return out
	var ordered := LayoutSolver.top_level_order(canvas.graph, canvas.layout)
	var picked: Dictionary[int, bool] = {}
	for id in selection.get_selected():
		var top := _top_level_id(id)
		if top != 0:
			picked[top] = true
	for id in ordered:
		if picked.has(id):
			out.append(id)
	return out

#endregion


#region 点击 vs 拖动的手势判定

## 按下时不选中，盯住这次单块手势：拖动会话一结束就按总位移判定。
## - 块在手势中被删（拖到删除区）→ 放弃待定；
## - 位移 < CLICK_MAX_MOVE（原地点击）→ 选中它；
## - 位移 ≥ CLICK_MAX_MOVE（真拖动）→ clear()，松手不残留选中。
func _track_pending() -> void:
	if _pending_id == 0:
		return
	if drag != null and drag.is_active():
		if canvas.layout != null:
			var pos := canvas.layout.rect_of(_pending_id).position
			var d := pos.distance_to(_pending_start)
			if d > _pending_max:
				_pending_max = d
		return
	var id := _pending_id
	_pending_id = 0
	# 拖动会话结束（_close_session 已跑）：此刻 layout 反映的是搬完后的位置
	if canvas == null or canvas.graph == null or not canvas.graph.has(id):
		return
	if _pending_max >= CLICK_MAX_MOVE:
		selection.clear()
	else:
		selection.select_only(id)

#endregion


func _on_selection_changed() -> void:
	if canvas != null:
		canvas.set_selected_ids(selection.get_selected())


## 本节点是 SubViewport 的子节点，get_viewport().get_mouse_position() 已经是 SubViewport 内坐标；
## 直接走画布变换的逆即可，不能再减 SubViewportContainer 的全局位置（两者坐标空间不同）。
func _world_mouse() -> Vector2:
	return canvas.get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
