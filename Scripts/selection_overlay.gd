extends Control
class_name SelectionOverlay
## 纯绘制的选中/框选覆盖层：负责
##  - 给每个被选中积木画高亮框；
##  - 拖拽框选时画矩形选区。
## 不做任何输入处理（mouse_filter 应设为 IGNORE），坐标均按本节点局部坐标传入。

var _boxes: Array = []     # Array[Rect2] 局部坐标
var _band_on := false
var _band := Rect2()

const FILL := Color(0.30, 0.55, 1.0, 0.16)
const EDGE := Color(0.45, 0.72, 1.0, 0.95)


func set_boxes(rects: Array) -> void:
	_boxes = rects.duplicate()
	queue_redraw()


func set_band(rect: Rect2, on: bool) -> void:
	_band = rect
	_band_on = on
	queue_redraw()


func _draw() -> void:
	for r in _boxes:
		draw_rect(r, FILL, true)
		draw_rect(r, EDGE, false, 2.0)
	if _band_on:
		draw_rect(_band, Color(0.30, 0.55, 1.0, 0.10), true)
		draw_rect(_band, EDGE, false, 1.5)
