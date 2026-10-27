class_name LinkLayer
extends Node2D

## 纯静态跳线层：把 [LinkRouter] 算出的折线画出来（本层不做几何计算与动态选区绘制）。
## 仅在布局或连线关系改变时重绘，框选与拖拽预览已完全剥离至动态覆盖层 CanvasOverlay。

const LINE_WIDTH: float = 4.0
const ARROW_SIZE: float = 16.0
const ARROW_TIP_HALF: float = 1.0
const ARROW_DARKEN: float = 0.1

var canvas: EditorCanvas


func _draw() -> void:
	if canvas == null:
		return
	for segment in canvas.link_segments():
		var points: PackedVector2Array = segment["points"]
		var count := points.size()
		if count < 2:
			continue
		var color: Color = segment["color"]
		# 跨链跳转线淡化显示（弱化视觉噪音，突出同链控制流）
		if bool(segment.get("is_cross", false)):
			color.a = 0.45

		draw_polyline(points, color, LINE_WIDTH, true)

		# 两端箭头方向由首末段水平走向物理自动推导（兼容同链左进左出与跨链右出右/进）
		draw_arrow(self, points[count - 1], color, points[count - 1].x < points[count - 2].x)
		draw_arrow(self, points[0], color, points[1].x <= points[0].x)


## 端点箭头（公共静态绘制）：恒水平、朝向由 [param flip] 决定（false = 朝右，true = 朝左）。
## 供 LinkLayer 与 CanvasOverlay 共用，消灭跨文件重复代码。
static func draw_arrow(ci: CanvasItem, to: Vector2, color: Color, flip: bool = false) -> void:
	var dx := (-1.0 if flip else 1.0) * ARROW_SIZE
	var dy := ARROW_SIZE * 0.5
	ci.draw_colored_polygon(PackedVector2Array([
		to + Vector2(-0.4 * dx, -dy),
		to + Vector2(-0.1 * dx, -dy),
		to + Vector2(0.4 * dx, -ARROW_TIP_HALF),
		to + Vector2(0.4 * dx, ARROW_TIP_HALF),
		to + Vector2(-0.1 * dx, dy),
		to + Vector2(-0.4 * dx, dy),
	]), color.darkened(ARROW_DARKEN))
