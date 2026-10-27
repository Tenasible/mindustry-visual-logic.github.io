class_name SelectorData
extends RefCounted

## 选择器候选集（单位 / 建筑 / …）：读 `blocks/selectors/*.json`，加候选只改数据。

const DIR: String = "res://blocks/selectors"
const UNITS: StringName = &"units"
const SENSORS: StringName = &"sensors"

static var _cache: Dictionary[StringName, Variant] = {}


## 取平铺候选列表：Array[Dictionary]，元素含 value / icon。
static func options(kind: StringName) -> Array:
	var data := _load(kind)
	var out: Array = []
	if data.has("values"):
		out.assign(data["values"])
	elif data.has("groups"):
		for group_name in data["groups"]:
			out.append_array(data["groups"][group_name])
	return out


static func groups(kind: StringName) -> Dictionary:
	var data := _load(kind)
	return data.get("groups", {})


static func exists(kind: StringName) -> bool:
	return not _load(kind).is_empty()


static func _load(kind: StringName) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var result: Dictionary = {}
	var path := DIR.path_join("%s.json" % String(kind))
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				result = parsed
			else:
				push_warning("选择器数据格式不正确：%s" % path)
	else:
		push_warning("缺少选择器数据：%s" % path)
	_cache[kind] = result
	return result
