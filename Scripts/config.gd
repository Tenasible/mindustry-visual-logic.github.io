class_name EditorConfig
extends Resource


@export var max_fps: int = 60
@export var compile_when_close: bool = false
@export var ui_scale: float = 1.0
@export var current_version: int = 0

var config: Dictionary:
	get:
		return {
			"max_fps" : self.max_fps,
			"compile_when_close" : self.compile_when_close,
			"ui_scale" : self.ui_scale,
			"current_version" : self.current_version,
		}


func _init() -> void:
	var json = {}
	if FileAccess.file_exists("user://config.txt"):
		var file = FileAccess.open("user://config.txt", FileAccess.READ)
		json = JSON.parse_string(file.get_as_text())
		
	self.max_fps = json.get("max_fps", self.max_fps)
	self.compile_when_close = json.get("compile_when_close", self.compile_when_close)
	self.ui_scale = json.get("ui_scale", self.ui_scale)
	self.current_version = json.get("current_version", self.current_version)


func save():
	var file = FileAccess.open("user://config.txt", FileAccess.WRITE)
	file.store_string(JSON.stringify(self.config, "\t"))
