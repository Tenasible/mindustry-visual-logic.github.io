class_name ElementBuilder
extends RefCounted

## 一种元素种类的行为契约：建控件、回填、默认值、条件取值的合法性检查。
## 契约在定义层、实现在视图层（[code]view/elements/element_builders.gd[/code]）：新增种类 = 写个子类 + 注册，其余各层不用改。

## 建控件并接线。[param host] 是块视图，见 [ElementBuilders] 里的宿主接口说明。
func build(_element: ElementDef, _host: Object) -> Control:
	return null


## 是否承载字段值（决定它进不进导出取值与条件校验）。
func is_field() -> bool:
	return false


## 是否是子槽位（`<Nest>`）。
func is_slot() -> bool:
	return false


## 把数据层的值写回控件。[param force] 为假时跳过正在输入的控件（避免光标跳位）。
func apply_value(_element: ElementDef, _control: Control, _value: String, _force: bool = false) -> void:
	pass


## 开关本元素里全部可交互控件（输入框 / 下拉 / 开关 / 组合控件里的按钮）。
func set_enabled(_element: ElementDef, _control: Control, _enabled: bool) -> void:
	pass


## 校验条件里对该字段的取值；返回问题描述（空串 = 合法）。
func validate_value(_element: ElementDef, _value: String) -> String:
	return ""


## 新块的初始值；null 表示不预置。
func default_value(element: ElementDef) -> Variant:
	return element.default_value if element.default_value != "" else null
