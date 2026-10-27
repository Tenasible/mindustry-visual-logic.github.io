class_name EditorCamera
extends Camera2D

## 画布相机：滚轮缩放 + 中键平移（左键留给框选，两者不再冲突）。
@export var zoom_speed: float = 1.1
@export var zoom_min: float = 0.25
@export var zoom_max: float = 3.0

var panning: bool = false

var _last_pos: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				panning = event.pressed
				_last_pos = event.position
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_by(zoom_speed)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_by(1.0 / zoom_speed)
	elif event is InputEventMouseMotion and panning:
		position += (_last_pos - event.position) / zoom
		_last_pos = event.position


func stop_panning() -> void:
	panning = false


func _zoom_by(factor: float) -> void:
	var value := clampf(zoom.x * factor, zoom_min, zoom_max)
	zoom = Vector2(value, value)
