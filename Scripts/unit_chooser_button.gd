extends Button


@export var unit :String
signal select_pressed(unit: String)


func _init():
	self.pressed.connect(selected)


func selected():
	emit_signal("select_pressed" , unit)
