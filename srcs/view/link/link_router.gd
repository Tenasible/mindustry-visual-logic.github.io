class_name LinkRouter
extends RefCounted

## 跳线路由（纯函数）：把「谁引用了谁」算成一组可直接绘制的折线。
## 同链按「宿主 C 形块通道 + 目标 + 方向」合并成母线束统一排轨道；跨链走独立的走廊过桥折线。

# ── 基础几何常量（像素） ──
const LANE_GAP: float = 14.0        # 第 0 号母线到积木左边缘的间距
const LANE_STEP: float = 10.0       # 每外扩一道母线再加的间距
const CUT_RATIO: float = 0.5        # 同链梯形拐角最大斜率（2:1 斜切）
const MIN_BUS: float = 20.0         # 同链母线竖直段保底长度
const ROW_HEIGHT: float = 40.0      # 积木标题行高度（与 BlockView.row_height 默认值耦合，改那边要同步）
const HEADER_HALF: float = 20.0     # 标题行正中偏移（= ROW_HEIGHT / 2）
const NEST_INDENT: float = 24.0     # 巢内缩进兜底值（真值从 metrics.slot_offsets 读，见 _nest_indent）
const END_DROP: float = 4.0         # 到达端上移量（错开同块进出双箭头）
const CROSS_CHAMFER: float = 12.0   # 跨链过桥折线的最大 45 度倒角



## 计算画布上全部跳线的折线顶点与颜色。
static func segments(graph: LogicGraph, library: BlockLibrary, layout: LayoutResult) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if graph == null or library == null or layout == null:
		return out

	var local_bundles_by_ch: Dictionary = {} # 通道 → 该通道的母线束列表
	var local_bundle_map: Dictionary = {}    # 母线束键 → 母线束（合并同束的多个源）

	# 第一阶段：同链收集母线束，跨链当场出折线
	graph.each_link_ref(
			func(node: LogicNode) -> Array[StringName]:
				var def := library.by_id(node.type_id)
				return def.reference_fields() if def != null else [] as Array[StringName],
			func(ref: Dictionary) -> void:
				var target: int = ref["target"]
				if target <= 0:
					return
				var source_id: int = (ref["node"] as LogicNode).id

				# c_s / c_t：源与目标所属顶层链的整数序号
				var c_s: int = layout.chain_ids.get(source_id, -1)
				var c_t: int = layout.chain_ids.get(target, -1)
				if c_s < 0 or c_t < 0:
					return

				if c_s == c_t:
					var s_ord: int = layout.orders[source_id]
					var t_ord: int = layout.orders[target]
					var flipped: bool = s_ord > t_ord # 起点行号 > 终点行号 = 从下往上回跳

					var top_y: float = layout.rect_of(target if flipped else source_id).position.y + HEADER_HALF
					var bottom_y: float = layout.rect_of(source_id if flipped else target).position.y + HEADER_HALF

					# 找能完整包住这段区间的最小 C 形块（防跳线穿过它的标题行）
					var scope := _find_scope_by_owner(source_id, top_y, bottom_y, layout)
					var host_id: int = int(scope["host_id"])        # 包住该跳线的 C 形块 ID（顶层为 0）
					var anchor_x: float = float(scope["anchor_x"])  # 该通道母线贴靠的左边缘 X

					# 通道键 = (链序号, 宿主 C 形块)；母线束键 = 通道 + 目标 + 方向。
					# 用 Vector 值类型做键：手工拼位段在 id 变大后会互相重叠。
					var ch_key := Vector2i(c_s, host_id)
					var bundle_key := Vector4i(c_s, host_id, target, 1 if flipped else 0)

					var bundle: Dictionary = local_bundle_map.get(bundle_key, {})
					if bundle.is_empty():
						bundle = {
							"target": target,
							"flipped": flipped,
							"top": mini(s_ord, t_ord),    # 行号区间覆盖源与目标两端
							"bottom": maxi(s_ord, t_ord),
							"anchor_x": anchor_x,
							"lane": 0,
							"starts": [] as Array[int],
						}
						local_bundle_map[bundle_key] = bundle
						if not local_bundles_by_ch.has(ch_key):
							local_bundles_by_ch[ch_key] = [] as Array[Dictionary]
						(local_bundles_by_ch[ch_key] as Array[Dictionary]).append(bundle)
					# 每次都收紧上下界：all_ids 的遍历顺序与布局顺序不保证一致
					(bundle["starts"] as Array[int]).append(source_id)
					bundle["top"] = mini(int(bundle["top"]), s_ord)
					bundle["bottom"] = maxi(int(bundle["bottom"]), s_ord)
				else:
					out.append({
						"points": _route_cross(layout, source_id, target),
						"color": color_for(target),
						"is_cross": true,
					})
	)

	# 第二阶段：按通道排轨道，再逐源生成同链折线
	for ch_key in local_bundles_by_ch:
		var ch_bundles: Array[Dictionary] = local_bundles_by_ch[ch_key]
		_assign_lanes(ch_bundles)
		for bundle in ch_bundles:
			var target_id: int = int(bundle["target"])
			var end := anchor_left(layout, target_id, true) - Vector2(0.0, END_DROP)
			var color := color_for(target_id)
			# 巢内通道（宿主 C 形块）竖条只容得下 2 道：lane 0 在缩进内、lane 1 贴左缘，
			# lane ≥ 2 的母线会溢出竖条与外层母线重叠 —— 等布局能预知道数后把竖条加宽。
			var lane_x: float = float(bundle["anchor_x"]) - LANE_GAP - float(bundle["lane"]) * LANE_STEP
			for src_id: int in bundle["starts"]:
				out.append({
					"points": _route_curve(anchor_left(layout, src_id), end, lane_x),
					"color": color,
					"is_cross": false,
				})

	return out


## 顺着 owners 向上找能完整包住 [top_y, bottom_y] 的最小 C 形块（顶层返回 host_id = 0）。
## owners 理论无环也不缺键（_place_chain 用 placed 去重），这里防的是损坏数据：环用 visited 断开、
## 缺矩形当链断处理，别把编辑器卡死。
static func _find_scope_by_owner(source_id: int, top_y: float, bottom_y: float, layout: LayoutResult) -> Dictionary:
	var cur := source_id
	var seen: Dictionary = {cur: true}
	var owner: int = layout.owners.get(cur, 0)
	while owner != 0 and not seen.has(owner):
		seen[owner] = true
		var r := layout.rect_of(owner)
		if r == Rect2():
			break
		# [top_y, bottom_y] 必须整个落在该 C 形块的肚子里（标题行以下、底边以上）
		if r.position.y + ROW_HEIGHT <= top_y and r.end.y >= bottom_y:
			return {"host_id": owner, "anchor_x": r.position.x + _nest_indent(layout, owner)}
		cur = owner
		owner = layout.owners.get(cur, 0)
	# 到顶了：cur 就是最外层积木，用它的左边缘作为整条链的基准线；
	# 断链时兜底用源块自己的左边缘（源块一定有布局，否则上游早就 return 了）。
	var base := layout.rect_of(cur)
	if base == Rect2():
		base = layout.rect_of(source_id)
	return {"host_id": 0, "anchor_x": base.position.x}


## 积木左边缘锚点：[param mid_y] 为真取竖直中点（到达端），否则取标题行中点（出发端）。
static func anchor_left(layout: LayoutResult, id: int, mid_y: bool = false) -> Vector2:
	return _anchor(layout, id, mid_y, false)


## 积木右边缘锚点：C 形块右侧是缺口，只能落在标题行，[param mid_y] 对它无效。
static func anchor_right(layout: LayoutResult, id: int, mid_y: bool = false) -> Vector2:
	return _anchor(layout, id, mid_y and not _has_nest(layout, id), true)


static func _anchor(layout: LayoutResult, id: int, mid_y: bool, right: bool) -> Vector2:
	if layout == null:
		return Vector2.ZERO
	var rect := layout.rect_of(id)
	var y := rect.position.y + (rect.size.y * 0.5 if mid_y else HEADER_HALF)
	return Vector2(rect.position.x + (rect.size.x if right else 0.0), y)


## C 形块的巢内缩进：真值是 slot_offsets 里巢行的 x（BlockView 用 margin*4 算），
## 拿不到时用 NEST_INDENT 兜底（与默认 margin=6 一致）。
static func _nest_indent(layout: LayoutResult, id: int) -> float:
	if layout == null:
		return NEST_INDENT
	var metrics: BlockMetrics = layout.metrics.get(id)
	if metrics != null and not metrics.slot_offsets.is_empty():
		var indent := INF
		for offset in metrics.slot_offsets.values():
			indent = minf(indent, offset.x)
		if not is_inf(indent):
			return indent
	return NEST_INDENT


## C 形块的判据：只有 nest 行会写 slot_offsets。
static func _has_nest(layout: LayoutResult, id: int) -> bool:
	if layout == null:
		return false
	var metrics: BlockMetrics = layout.metrics.get(id)
	return metrics != null and not metrics.slot_offsets.is_empty()


## 根据目标积木 ID 生成固定颜色（黄金分割乘法哈希）。
static func color_for(target_id: int) -> Color:
	var h: int = (hash(target_id) * 2654435761) & 0x7FFFFFFF
	return Color.from_hsv(float(h % 360) / 360.0, 0.65, 0.95)


## 通道内纯整数装箱：排序主键是跨度，保证「内束先处理」恒成立 —— 包含让道是单向扫描，
## 只看已处理束，若让回跳加分/支线减分能反转处理顺序，内束就会跑到外道横穿容器
## （实测基线的 span 升序反而没这个问题）。支线与回跳只在同跨度内决先后：
## 支线多的先占内道，回跳的退到外道包住内部。
static func _assign_lanes(bundles: Array[Dictionary]) -> void:
	bundles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var span_a: int = int(a["bottom"]) - int(a["top"])
		var span_b: int = int(b["bottom"]) - int(b["top"])
		if span_a != span_b:
			return span_a < span_b
		var branches_a: int = maxi(0, (a["starts"] as Array).size() - 1)
		var branches_b: int = maxi(0, (b["starts"] as Array).size() - 1)
		if branches_a != branches_b:
			return branches_a > branches_b
		var flip_a: bool = bool(a["flipped"])
		var flip_b: bool = bool(b["flipped"])
		if flip_a != flip_b:
			return not flip_a
		return int(a["target"]) < int(b["target"])
	)

	for i in bundles.size():
		var cur: Dictionary = bundles[i]
		var cur_top: int = int(cur["top"])
		var cur_bottom: int = int(cur["bottom"])

		var base_lane := 0
		var occupied_lanes: Dictionary = {}

		for j in i:
			var other: Dictionary = bundles[j]
			var o_top: int = int(other["top"])
			var o_bottom: int = int(other["bottom"])

			# 包含让道：若 other 完整处在 cur 区间内部，cur 必须排在 other 外侧（轨道号 + 1）
			if o_top >= cur_top and o_bottom <= cur_bottom:
				base_lane = maxi(base_lane, int(other["lane"]) + 1)

			# 相交避让：若两束行号区间有重叠，拉黑 other 已占用的轨道号
			if cur_top < o_bottom and cur_bottom > o_top:
				occupied_lanes[int(other["lane"])] = true

		var lane := base_lane
		while occupied_lanes.has(lane):
			lane += 1
		cur["lane"] = lane


## 同链 4 点梯形折线（内部按起止高度算动态斜率）。
static func _route_curve(start: Vector2, end: Vector2, lane_x: float) -> PackedVector2Array:
	var span_y := absf(end.y - start.y)
	var span_x := absf(lane_x - end.x) + absf(lane_x - start.x)
	var slope := clampf((span_y - MIN_BUS) / span_x if span_x > 0.0 else 0.0, 0.0, CUT_RATIO)
	var dir_y := signf(end.y - start.y)

	return PackedVector2Array([
		start,
		Vector2(lane_x, start.y + dir_y * (start.x - lane_x) * slope),
		Vector2(lane_x, end.y - dir_y * (end.x - lane_x) * slope),
		end,
	])


## 跨链走廊折线：按两块的水平位置关系选端点与走廊；走廊落进任何块体内则退避到
## 该竖直区间所有块的左侧（左出左进）。三条分支共用同一套锚点，谁都不检查走廊落点，
## 这里统一兜底。
static func _route_cross(layout: LayoutResult, source_id: int, target_id: int) -> PackedVector2Array:
	var drop := Vector2(0.0, END_DROP)
	var sl := anchor_left(layout, source_id)
	var sr := anchor_right(layout, source_id)
	var tl := anchor_left(layout, target_id, true) - drop
	var tr := anchor_right(layout, target_id, true) - drop

	var start: Vector2
	var end: Vector2
	var mid_x: float
	if sr.x <= tl.x:
		# 源在左：右出 -> 左进，走廊走两链正中间
		start = sr
		end = tl
		mid_x = (sr.x + tl.x) * 0.5
	elif sl.x >= tr.x:
		# 源在右：左出 -> 右进，走廊走两链正中间
		start = sl
		end = tr
		mid_x = (sl.x + tr.x) * 0.5
	else:
		# 两链水平重叠：从左侧外绕
		start = sl
		end = tl
		mid_x = minf(sl.x, tl.x) - LANE_GAP

	var pts := _cross_polyline(start, end, mid_x, false)
	if _poly_hits_block(layout, pts):
		# 退避：改左出左进，竖直段挪到区间内所有块左侧。
		# 残余情形（别的链与源块同行、挡在更左）任何左绕都要穿它，留给布局-路由回灌。
		start = sl
		end = tl
		mid_x = _corridor_x(layout, start.y, end.y)
		pts = _cross_polyline(start, end, mid_x, true)
	return pts


## 按 [param mid_x] 的竖直走廊生成跨链折线；两端几乎齐平时连直线（[param force_curved]
## 为真时跳过直线特例 —— 退避后的走廊必须有竖直段才有意义）。
static func _cross_polyline(start: Vector2, end: Vector2, mid_x: float, force_curved: bool) -> PackedVector2Array:
	var dy := end.y - start.y
	if not force_curved and absf(dy) <= END_DROP and start.x != end.x:
		return PackedVector2Array([start, end])

	var dir_y := 1.0 if dy >= 0.0 else -1.0
	var chamfer := clampf(
			minf(absf(mid_x - start.x), absf(end.x - mid_x)) * 0.4,
			0.0, minf(absf(dy) * 0.3, CROSS_CHAMFER)
	)
	# 不再回落 4 点直角版：chamfer→0 时倒角版自然退化为直角（中间点重合），
	# 两版拐角位置不同会让相邻 dy 的竖直段长度跳变约 2.5 倍。
	var out_dir := signf(mid_x - start.x)
	var in_dir := signf(end.x - mid_x)
	return PackedVector2Array([
		start,
		Vector2(mid_x - out_dir * chamfer, start.y),
		Vector2(mid_x, start.y + dir_y * chamfer),
		Vector2(mid_x, end.y - dir_y * chamfer),
		Vector2(mid_x + in_dir * chamfer, end.y),
		end,
	])


## [param pts] 是否穿过任何块体（与收缩 0.5px 的块矩形判定，锚点贴在块边缘不算穿）。
static func _poly_hits_block(layout: LayoutResult, pts: PackedVector2Array) -> bool:
	if layout == null:
		return false
	for id in layout.rects:
		var r: Rect2 = layout.rects[id]
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if _poly_hits_rect(pts, r.grow(-0.5)):
			return true
	return false


static func _poly_hits_rect(pts: PackedVector2Array, r: Rect2) -> bool:
	for i in pts.size() - 1:
		if _seg_hits_rect(pts[i], pts[i + 1], r):
			return true
	return false


static func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	# 段的包围盒先粗筛；轴对齐段宽或高为 0，grow 后才能与矩形相交（否则漏检）
	if not Rect2(minf(a.x, b.x), minf(a.y, b.y), absf(b.x - a.x), absf(b.y - a.y)).grow(0.5).intersects(r):
		return false
	if _strictly_inside(a, r) or _strictly_inside(b, r):
		return true
	var corner := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corner[i], corner[(i + 1) % 4]) != null:
			return true
	return false


static func _strictly_inside(p: Vector2, r: Rect2) -> bool:
	return p.x > r.position.x and p.x < r.end.x and p.y > r.position.y and p.y < r.end.y


## 走廊退避位：与 [y_from, y_to] 相交的所有块的左边缘最小值再往左 LANE_GAP ——
## 竖直段就不会穿任何带内块。
static func _corridor_x(layout: LayoutResult, y_from: float, y_to: float) -> float:
	var top := minf(y_from, y_to)
	var bottom := maxf(y_from, y_to)
	var x := INF
	for id in layout.rects:
		var r: Rect2 = layout.rects[id]
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if r.position.y < bottom and r.end.y > top:
			x = minf(x, r.position.x)
	return (x if not is_inf(x) else 0.0) - LANE_GAP
