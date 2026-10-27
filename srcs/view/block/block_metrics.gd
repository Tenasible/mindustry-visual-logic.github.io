class_name BlockMetrics
extends RefCounted

## 一个块自身的几何度量（相对左上角）：尺寸、尾锚点、槽位落点。
## 由定义层的度量函数算出 —— 尺寸永远自底向上，不依赖控件是否排过版。

var size: Vector2 = Vector2.ZERO

## 尾部吸附：下一个兄弟块的落点（相对块左上角）与吸附线宽度。
var tail_offset: Vector2 = Vector2.ZERO
var tail_width: float = 0.0

## 子槽位：槽位 id → 槽内第一个子块的落点（相对块左上角）。
var slot_offsets: Dictionary[StringName, Vector2] = {}

## 子槽位：槽位 id → 吸附线宽度。
var slot_widths: Dictionary[StringName, float] = {}

