extends Object
class_name SaveLoadUtils


## 将对象中的所有导出变量保存到字典中
static func save_export_vars_to_dict(obj: Object) -> Dictionary:
	var result := {}
	var properties := obj.get_property_list()
	
	for property in properties:
		var name: String = property["name"]
		
		# 检查是否是导出变量（同时具有 SCRIPT_VARIABLE 和 EDITOR 使用标志）
		if (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) and \
			(property["usage"] & PROPERTY_USAGE_EDITOR):
			
			# 获取变量值
			var value = obj.get(name)
			result[name] = value
	
	return result

## 从字典加载值到对象的导出变量
static func load_export_vars_from_dict(obj: Object, data: Dictionary) -> void:
	var properties := obj.get_property_list()
	
	for property in properties:
		var name: String = property["name"]
		
		# 检查是否是导出变量且字典中有对应键
		if (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) and \
			(property["usage"] & PROPERTY_USAGE_EDITOR) and \
			data.has(name):
			
			# 设置变量值
			obj.set(name, data[name])
