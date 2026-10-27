class_name BlockDef
extends RefCounted

## 一种逻辑块的定义（对应 XML 里的一个 `<Block>`）。
## 行是显式的（[RowDef]），条件（[ConditionDef]）挂在行与元素上 —— 内部只有这一种机制。

## 一种「导出模板 + 生效条件」的组合；`<Pressed>`/`<Released>` 会带上 button/pressed 提示供导入回填。
class ExportVariant extends RefCounted:
	var condition: ConditionDef = null
	var parts: Array[ExportPart] = []
	var button: StringName = &""
	var pressed: bool = false

	## 条件是否恰好形如 `开关=true/false`：是的话顺带记下按钮与状态。
	func derive_button_from_condition() -> void:
		if condition == null or condition.kind != ConditionDef.Kind.COMPARE:
			return
		if condition.values.size() != 1 or condition.negated:
			return
		var value := condition.values[0]
		if value != "true" and value != "false":
			return
		button = condition.field
		pressed = value == "true"


## 一行：一个条件 + 若干单元格。
class RowDef extends RefCounted:
	var condition: ConditionDef = null
	var cells: Array[ElementDef] = []

	func is_active(value_of: Callable) -> bool:
		return condition == null or condition.matches(value_of)


var id: StringName = &""
var kind: StringName = &""
var color: Color = Color.WHITE
## 程序入口块（XML `<Block entry="true">`，目前是 Start）：一个文档只应有一个。
var entry: bool = false
## 结构块标记（XML `<Block marker="if">`）：导出时在指令行尾写 `#if 字段=值…`，导入靠它把这一行还原成结构块。
var marker: String = ""
## 循环块（XML `<Block loop="true">`，While）：巢里的 Break / Continue 以它为目标。
var loop: bool = false
## 跳出 / 继续（XML `<Block loop_jump="break|continue">`）：导出时把 `<AfterSubtree/>` 那一格换成所属循环的行号。
var loop_jump: StringName = &""

var elements: Array[ElementDef] = []


func option_element(field_id: StringName) -> ElementDef:
	for element in elements:
		if element.type == &"Option" and element.id == field_id:
			return element
	return null
var rows: Array[RowDef] = []

var export_parts: Array[ExportPart] = []
## 条件化的导出模板：第一个条件成立的优先，都不成立时用 [member export_parts]。
var export_variants: Array[ExportVariant] = []
## 尾跳模板（XML `<Tail>`）：整段巢之后额外补的那一行，结构块用它跳回自己的头部（`<SelfLine/>`）。
var tail_parts: Array[ExportPart] = []
## 解析期收集的条件（整块解析完再统一校验字段与取值）
var pending_conditions: Array[Dictionary] = []
var order: int = 0

var _by_id: Dictionary[StringName, ElementDef] = {}
var _row_of: Dictionary[StringName, RowDef] = {}
var _slots: Array[StringName] = []
var _fields: Array[StringName] = []
var _references: Array[StringName] = []
var _indexed: bool = false


func _init(p_id: StringName = &"", p_kind: StringName = &"") -> void:
	id = p_id
	kind = p_kind


## 建立 id 索引。解析结束后调用一次；手工构造 BlockDef 时也要调。
func build_index() -> void:
	_by_id.clear()
	_row_of.clear()
	_slots.clear()
	_fields.clear()
	_references.clear()
	for row in rows:
		for cell in row.cells:
			_row_of[cell.id] = row
	for element in elements:
		if element.id == &"":
			continue
		if not _by_id.has(element.id):
			_by_id[element.id] = element
		# 「承载字段值 / 是子槽位」由构建器自报，本层不枚举元素种类
		if element.is_slot():
			if not _slots.has(element.id):
				_slots.append(element.id)
		elif element.is_field():
			if not _fields.has(element.id):
				_fields.append(element.id)
	_collect_references()
	_indexed = true


## 导出模板是「哪些字段是块引用」的唯一真相（元素种类只管怎么编辑它）。
func _collect_references() -> void:
	for part in export_parts:
		_register_reference(part)
	for variant in export_variants:
		for part in variant.parts:
			_register_reference(part)


func _register_reference(part: ExportPart) -> void:
	if part != null and part.kind == ExportPart.Kind.FIELD and part.link \
			and not _references.has(part.field):
		_references.append(part.field)


func element(element_id: StringName) -> ElementDef:
	if not _indexed:
		build_index()
	return _by_id.get(element_id)


func slot_ids() -> Array[StringName]:
	if not _indexed:
		build_index()
	return _slots.duplicate()


func field_ids() -> Array[StringName]:
	if not _indexed:
		build_index()
	return _fields.duplicate()

## 本块声明为块引用的字段 id（Jump 的目标）：值存节点引用，不直接进 mlog 文本。
func reference_fields() -> Array[StringName]:
	if not _indexed:
		build_index()
	return _references.duplicate()


func is_reference_field(field_id: StringName) -> bool:
	return reference_fields().has(field_id)


func row_of(element_id: StringName) -> RowDef:
	if not _indexed:
		build_index()
	return _row_of.get(element_id)


## 行条件与元素条件都成立，这个元素才生效。
func is_element_active(element: ElementDef, value_of: Callable) -> bool:
	if element == null:
		return false
	var row := row_of(element.id)
	if row != null and not row.is_active(value_of):
		return false
	return element.is_active_here(value_of)


func is_field_active(field_id: StringName, value_of: Callable) -> bool:
	return is_element_active(element(field_id), value_of)


func export_parts_for(value_of: Callable) -> Array[ExportPart]:
	for variant in export_variants:
		if variant.condition == null or variant.condition.matches(value_of):
			return variant.parts
	return export_parts


## 新块入图时预置的字段值（字段 id → 值）：不预置会导出 `wait 0` 之类的错误指令。
func default_field_values() -> Dictionary:
	var out: Dictionary = {}
	for element in elements:
		if not element.is_field():
			continue
		# 每种元素的默认值规则长在它自己的构建器上
		var value: Variant = ElementRegistry.default_value(element)
		if value != null:
			out[element.id] = value
	return out


func apply_defaults(node: LogicNode) -> void:
	if node != null:
		node.apply_fields(default_field_values())
