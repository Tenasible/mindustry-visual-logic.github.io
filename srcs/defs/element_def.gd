class_name ElementDef
extends RefCounted

## 一个块定义里的元素（XML 的一个子标签）；生效条件挂在元素自己身上（[ConditionDef]），不用罗列可见元素 id。
## 「怎么建控件、怎么读值」由 [ElementRegistry] 决定，新增种类不必改解析器与视图。

class OptionItem extends RefCounted:
	var text: String = ""
	## 导出进 mlog 的值。为空时等于 [member text]。
	var value: String = ""
	## 旧名字（`<Item alias="atan2">`）：导入时认它，存回用规范值；游戏 `LParser.opNameChanges` 也带这张表。
	var alias: String = ""
	func _init(p_text: String = "") -> void:
		text = p_text

	func set_text(p_text: String) -> void:
		text = p_text

	func value_or_text() -> String:
		return value if value != "" else text

	func accepts(candidate: String) -> bool:
		return candidate == value_or_text() or (alias != "" and candidate == alias)


## 全部候选取值（规范值）；导入时按取值合法性把模板结构相同的候选块分开（`ucontrol` 的各变体）。
func option_values() -> PackedStringArray:
	var out := PackedStringArray()
	for item in items:
		out.append(item.value_or_text())
	return out


## 规范值：合法值返回自身，旧名字返回它现在的值，都认不出返回 ""。
func canonical_value(candidate: String) -> String:
	for item in items:
		if item.value_or_text() == candidate:
			return candidate
	for item in items:
		if item.alias != "" and item.alias == candidate:
			return item.value_or_text()
	return ""


var type: StringName = &""

## 元素 id：既是可见性引用的名字，也是导出时取值的字段名。
var id: StringName = &""

var text: String = ""

var placeholder: String = ""

var items: Array[OptionItem] = []

## `<Option>` 控件的宽度预算：引擎的 fit_to_longest_item 会让每个新实例自己把全部候选量一遍
## （45 项约 90 ms），而拖动起手要为每个被拖块新建整棵控件 —— 首次建控件时让引擎量一次真实宽度存在这里，
## 同定义的块之后直接复用。-1 表示尚未量过。
var option_text_width: float = -1.0

var default_index: int = 0

## 字段默认值：新块入图时写进节点；未写 default 时用 [member placeholder]。
var default_value: String = ""

## 生效条件（`when="…"`）；null 表示恒真。
var condition: ConditionDef = null

var selector_kind: StringName = &""

## 原始属性兜底：新元素类型可以自带属性，解析器不必认识它们。
var attrs: Dictionary = {}


## 条件化排位（`<Place when="…" before|after="元素 id"/>`）：条件成立时把元素挪到另一个元素的前 / 后；默认顺序 = 书写顺序。
class Placement extends RefCounted:
	var when: ConditionDef = null
	## 挪到谁的前面 / 后面（同一行内的元素 id）。
	var before: StringName = &""
	var after: StringName = &""

	func describe() -> String:
		var where: String = "after %s" % after if after != &"" else "before %s" % before
		return where


## 本元素的排位规则，按书写顺序取第一条成立的。
var placements: Array[Placement] = []

func _init(p_type: StringName = &"", p_id: StringName = &"") -> void:
	type = p_type
	id = p_id


## 这个元素是否承载一个"字段值"（由注册表里的构建器自报，本层不枚举元素种类）。
func is_field() -> bool:
	return ElementRegistry.is_field(type)


func is_slot() -> bool:
	return ElementRegistry.is_slot(type)


func set_text(value: String) -> void:
	text = value


## 单看元素自身的条件是否成立（不含所在行的条件）。
func is_active_here(value_of: Callable) -> bool:
	return condition == null or condition.matches(value_of)
