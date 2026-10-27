class_name BlockLibrary
extends RefCounted

## 块定义库：把 `blocks/{locale}/*.xml` 解析成 [BlockDef]。
## 布局 = 显式的行 + 条件：`<Row [when]>` 分行，行与元素都能带 `when`（`&` `|` `~` 与括号）；
## `<Group when>` 共享条件、`<Export [when]>` 是导出模板、`<Kind hidden>` 不进调色板、`<Block entry>` 是入口块。
## `<Br/>` / `<Pressed>` / `<Item show>` 不再支持，会进 [member warnings]。

class Kind extends RefCounted:
	var id: StringName = &""
	var color: Color = Color.WHITE
	var blocks: Array[BlockDef] = []
	## XML 里 `hidden="true"`：这个类别不进调色板（里面的块仍能用，比如自动放的入口块）。
	var hidden: bool = false

	func _init(p_id: StringName = &"", p_color: Color = Color.WHITE) -> void:
		id = p_id
		color = p_color


const DIR: String = "res://blocks"
const FALLBACK_LANG: String = "en_US"

var warnings: PackedStringArray = []
var kinds: Array[Kind] = []

var _by_id: Dictionary[StringName, BlockDef] = {}


## 按 locale 读块定义（`locale` 是 Godot 的写法：en / zh_CN / zh_TW…）。
## 该语言目录不存在时回退到 [constant FALLBACK_LANG]。
static func load_localized(locale: String = "") -> BlockLibrary:
	var library := BlockLibrary.new()
	var lang := locale if locale != "" else OS.get_locale()
	# 只提供 en_US / zh_CN 两套：zh* 一律用 zh_CN，其余语言交给回退目录
	var name := "zh_CN" if lang.begins_with("zh") else lang
	var dir := DIR.path_join(name)
	if not DirAccess.dir_exists_absolute(dir):
		dir = DIR.path_join(FALLBACK_LANG)
	library.load_dir(dir)
	return library


func load_dir(dir: String) -> void:
	kinds.clear()
	_by_id.clear()
	warnings.clear()
	if not DirAccess.dir_exists_absolute(dir):
		warnings.append("块定义目录不存在：%s" % dir)
		return
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file_name in files:
		if file_name.get_extension().to_lower() != "xml":
			continue
		_parse_file(dir.path_join(file_name))


func by_id(block_id: StringName) -> BlockDef:
	return _by_id.get(block_id)


func is_entry(block_id: StringName) -> bool:
	var def := by_id(block_id)
	return def != null and def.entry


func has(block_id: StringName) -> bool:
	return _by_id.has(block_id)


## 程序入口块（`entry="true"`，目前是 Start）：新页起点 + 导出从哪儿开始。
func entry_def() -> BlockDef:
	for kind in kinds:
		for block in kind.blocks:
			if block.entry:
				return block
	return null


## 图上现有的入口块节点；没有（或没定义入口块类型）返回 null。
func find_entry(graph: LogicGraph) -> LogicNode:
	var def := entry_def()
	if def == null:
		return null
	for id in graph.all_ids():
		var node := graph.get_node_by_id(id)
		if node != null and node.type_id == def.id:
			return node
	return null

func block_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_by_id.keys())
	return out



#region 解析

func _parse_file(path: String) -> void:
	var xml := XMLParser.new()
	if xml.open(path) != OK:
		warnings.append("无法打开块定义：%s" % path)
		return
	var current_kind: Kind = null
	var block: BlockDef = null
	var option_element: ElementDef = null
	var row: BlockDef.RowDef = null
	var group_condition: ConditionDef = null
	# 当前的导出段目标：块的基础模板 / 某个 <Export> 变体 / <Tail> 尾跳
	var export_target: Array[ExportPart] = []
	var text_target: Variant = null
	# 当前打开的（非自闭合）元素：`<Place>` 写在它内部，所以要知道自己在谁肚子里
	var current_element: ElementDef = null
	var order := 0

	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := xml.get_node_name()
				var attrs := _attrs(xml)
				var self_closing := xml.is_empty()
				text_target = null
				match tag:
					"Kind":
						current_kind = Kind.new(
							StringName(attrs.get("name", "")),
							_parse_hex_color(String(attrs.get("color", "#FFFFFF")))
						)
						current_kind.hidden = _as_bool(attrs.get("hidden", "false"))
						order = 0
						kinds.append(current_kind)
					"Block":
						if current_kind == null:
							warnings.append("%s：<Block> 不在 <Kind> 内" % path)
						else:
							block = _make_block(attrs, current_kind, order)
							export_target = block.export_parts
							order += 1
							# 解析上下文按块重置：否则后续块会把单元格塞进上一个块的行里
							row = null
							group_condition = null
							option_element = null
					"Row":
						if block != null:
							row = _start_row(block, _condition_of(block, attrs))
					"Br", "Pressed", "Released":
						warnings.append("%s：<%s> 是旧写法，已不再支持（分行用 <Row [when]>，开关状态用 when 条件）"
							% [block.id if block != null else "?", tag])
					"Group":
						if block != null:
							var condition := _condition_of(block, attrs)
							group_condition = condition if group_condition == null \
								else ConditionDef.all_of([group_condition, condition])
					"Export":
						if block != null:
							export_target = _start_export(block, attrs)
					"Tail":
						if block != null:
							export_target = block.tail_parts
					"Literal":
						if block != null:
							var part := ExportPart.make_literal("")
							part.space_before = _space_before(attrs)
							export_target.append(part)
							text_target = part
					"Field":
						if block != null:
							var field_part := ExportPart.make_field(StringName(attrs.get("id", "")))
							field_part.space_before = _space_before(attrs)
							field_part.link = _as_bool(attrs.get("link", "false"))
							field_part.as_string = String(attrs.get("as", "")) == "string"
							field_part.allow_empty = _as_bool(attrs.get("allow_empty", "false"))
							export_target.append(field_part)
					"FirstOf":
						if block != null:
							export_target.append(
								ExportPart.make_first_visible(_ids(String(attrs.get("ids", ""))))
							)
					"AfterSubtree":
						if block != null:
							export_target.append(ExportPart.make_after_subtree())
					"SelfLine":
						if block != null:
							export_target.append(ExportPart.make_self_line())
					"Item":
						if option_element != null:
							var item := ElementDef.OptionItem.new("")
							item.value = String(attrs.get("value", ""))
							item.alias = String(attrs.get("alias", ""))
							option_element.items.append(item)
							text_target = item
					"Place":
						if current_element == null:
							warnings.append("%s：<Place> 只能写在元素内部（`<LineBox id=\"a\"><Place …/></LineBox>`）"
								% [block.id if block != null else "?"])
						else:
							var placement := ElementDef.Placement.new()
							placement.when = _condition_of(block, attrs)
							placement.before = StringName(attrs.get("before", ""))
							placement.after = StringName(attrs.get("after", ""))
							if (placement.before == &"") == (placement.after == &""):
								warnings.append("%s：元素 %s 的 <Place> 要且只要写 before= 或 after= 之一"
									% [block.id if block != null else "?", current_element.id])
							else:
								current_element.placements.append(placement)
					_:
						if block != null:
							if not ElementRegistry.has(tag):
								warnings.append("%s：未知元素种类 <%s>（已注册：%s）"
									% [block.id, tag, _join_ids(ElementRegistry.types())])
							else:
								var element := _make_element(tag, attrs, block, group_condition)
								block.elements.append(element)
								if row == null:
									row = _start_row(block, null)
								row.cells.append(element)
								if tag == "Option":
									option_element = element
								if tag == "Text":
									text_target = element
								current_element = element
				if self_closing:
					text_target = null
					# 自闭合的元素不可能有 <Place> 子元素，关掉它
					if current_element != null and tag == String(current_element.type):
						current_element = null
					if tag == "Option":
						option_element = null
			XMLParser.NODE_TEXT:
				if text_target != null:
					var text := xml.get_node_data()
					if text != "":
						text_target.set_text(text)
			XMLParser.NODE_ELEMENT_END:
				# 必须放在 match 之前：写进 match 会被具名分支吃掉，通配分支又会让后面的 "Block"/"Kind" 全走不到。
				if current_element != null and xml.get_node_name() == String(current_element.type):
					current_element = null
				match xml.get_node_name():
					"Text", "Item", "Literal":
						text_target = null
					"Place":
						pass
					"Option":
						option_element = null
					"Row":
						row = null
					"Group":
						group_condition = null
					"Export":
						export_target = block.export_parts if block != null else export_target
					"Tail":
						export_target = block.export_parts if block != null else export_target
					"Block":
						if block != null:
							# 先建索引：校验要用到 element() / row_of()
							block.build_index()
							_validate_conditions(block)
							_validate_placements(block)
							# 有尾跳却没 marker：导出仍然合法，只是导回来认不出这是结构块
							if not block.tail_parts.is_empty() and block.marker == "":
								warnings.append("%s：有 <Tail> 尾跳却没有 marker=，导回来会认不出这个结构块" % block.id)
						block = null
					"Kind":
						current_kind = null

	if block != null:
		block.build_index()


## 整块解析完后统一校验条件：语法错误、字段是否存在、取值是否合法。
func _validate_conditions(block: BlockDef) -> void:
	for entry in block.pending_conditions:
		var text := String(entry["text"])
		for message in entry["errors"]:
			warnings.append("%s：when=\"%s\" —— %s" % [block.id, text, message])
		_validate_condition(block, text, entry["condition"])
	block.pending_conditions.clear()


## 校验 <Place>：目标元素得存在、得在同一行（否则排不了），也不能指向自己。
func _validate_placements(block: BlockDef) -> void:
	for element in block.elements:
		for placement in element.placements:
			var target: StringName = placement.after if placement.after != &"" else placement.before
			if target == element.id:
				warnings.append("%s：元素 %s 的 <Place> 指向了自己" % [block.id, element.id])
				continue
			var other := block.element(target)
			if other == null:
				warnings.append("%s：元素 %s 的 <Place> 指向了不存在的元素 %s"
					% [block.id, element.id, String(target)])
				continue
			if block.row_of(element.id) != block.row_of(other.id):
				warnings.append("%s：元素 %s 的 <Place> 指向了另一行的 %s —— 只能在同一行内换位"
					% [block.id, element.id, String(target)])


func _validate_condition(block: BlockDef, text: String, condition: ConditionDef) -> void:
	if condition == null:
		return
	if condition.kind == ConditionDef.Kind.COMPARE:
		if condition.field == &"":
			return
		var element := block.element(condition.field)
		if element == null:
			warnings.append("%s：when=\"%s\" —— 未知字段：%s（本块字段：%s）"
				% [block.id, text, String(condition.field), _join_ids(block.field_ids())])
			return
		for value in condition.values:
			var problem := ElementRegistry.validate_value(element, value)
			if problem != "":
				warnings.append("%s：when=\"%s\" —— %s" % [block.id, text, problem])
		return
	for child in condition.children:
		_validate_condition(block, text, child)
	if condition.child != null:
		_validate_condition(block, text, condition.child)


static func _join_ids(ids: Array[StringName]) -> String:
	var parts := PackedStringArray()
	for id in ids:
		parts.append(String(id))
	return ", ".join(parts)


func _start_row(block: BlockDef, condition: ConditionDef) -> BlockDef.RowDef:
	var row := BlockDef.RowDef.new()
	row.condition = condition
	block.rows.append(row)
	return row


func _make_block(attrs: Dictionary, current_kind: Kind, order: int) -> BlockDef:
	var block := BlockDef.new(StringName(attrs.get("name", "")), current_kind.id)
	block.color = current_kind.color
	block.order = order
	block.entry = _as_bool(attrs.get("entry", "false"))
	block.marker = String(attrs.get("marker", "")).strip_edges()
	block.loop = _as_bool(attrs.get("loop", "false"))
	var loop_jump := String(attrs.get("loop_jump", "")).strip_edges()
	if loop_jump != "" and loop_jump != "break" and loop_jump != "continue":
		warnings.append("%s：loop_jump 只能是 break 或 continue（实际 `%s`）" % [block.id, loop_jump])
	elif loop_jump != "" and block.marker == "":
		# 行尾没有标记就认不回来，导出会变成一条普通 jump
		warnings.append("%s：loop_jump 要配套 marker，否则导回来只是普通 Jump" % block.id)
	block.loop_jump = StringName(loop_jump)
	if block.marker != "" and (block.marker.contains(" ") or block.marker.begins_with("#")):
		warnings.append("%s：marker 只能是不带空格、不带 # 的一个词（实际 `%s`）" % [block.id, block.marker])
	if block.id == &"":
		warnings.append("存在没有 name 的 <Block>（%s）" % current_kind.id)
	elif _by_id.has(block.id):
		warnings.append("块 id 重复：%s" % block.id)
	else:
		_by_id[block.id] = block
		for other in _by_id.values():
			# marker 是导入时认块的唯一线索，重名会让另一个块永远认不回来
			if other != block and other.marker != "" and other.marker == block.marker:
				warnings.append("块 %s 与 %s 的 marker 重名：%s" % [block.id, other.id, block.marker])
	current_kind.blocks.append(block)
	return block


func _make_element(tag: String, attrs: Dictionary, block: BlockDef, group: ConditionDef) -> ElementDef:
	var element := ElementDef.new(StringName(tag), StringName(attrs.get("id", "")))
	element.attrs = attrs.duplicate()
	element.text = String(attrs.get("text", ""))
	element.placeholder = String(attrs.get("placeholder", ""))
	element.selector_kind = StringName(attrs.get("kind", ""))
	element.condition = _condition_of(block, attrs)
	if element.condition == null:
		element.condition = group
	elif group != null:
		element.condition = ConditionDef.all_of([group, element.condition])
	if tag == "Option":
		element.default_index = int(attrs.get("default", 0))
	else:
		element.default_value = String(attrs.get("default", element.placeholder))
	return element


## 解析 `when="…"`；没有就返回 null（无法解析时也返回 null，并记进 warnings）。
func _condition_of(block: BlockDef, attrs: Dictionary) -> ConditionDef:
	var text := String(attrs.get("when", "")).strip_edges()
	if text == "":
		return null
	# 不在解析中途校验：条件可能引用本块后面才声明的字段 —— 校验推迟到整块解析完
	var result := ConditionParser.parse(text)
	var condition: ConditionDef = result["condition"]
	block.pending_conditions.append({"text": text, "condition": condition, "errors": result["errors"]})
	return condition


## 开一个 <Export>：带 when 的进 export_variants，不带的当场当基础模板；返回接下来这些段该往哪写。
func _start_export(block: BlockDef, attrs: Dictionary) -> Array[ExportPart]:
	var text := String(attrs.get("when", "")).strip_edges()
	var variant := BlockDef.ExportVariant.new()
	if text != "":
		var condition := _condition_of(block, attrs)
		variant.condition = condition
		variant.derive_button_from_condition()
		block.export_variants.append(variant)
		return variant.parts
	block.export_parts = variant.parts
	return block.export_parts

#endregion


#region 杂项

func _space_before(attrs: Dictionary) -> bool:
	if attrs.has("glue"):
		return not _as_bool(attrs.get("glue", "true"))
	return _as_bool(attrs.get("space_before", "true"))


func _as_bool(raw: Variant) -> bool:
	var text := String(raw).strip_edges().to_lower()
	return not (text == "false" or text == "0" or text == "no")


func _ids(raw: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for piece in raw.strip_edges().split(" ", false):
		if piece != "":
			out.append(StringName(piece))
	return out


func _attrs(xml: XMLParser) -> Dictionary:
	var out: Dictionary = {}
	for i in xml.get_attribute_count():
		out[xml.get_attribute_name(i)] = xml.get_attribute_value(i)
	return out


func _parse_hex_color(hex: String) -> Color:
	var digits := hex.strip_edges().lstrip("#")
	if digits.length() < 6:
		return Color.WHITE
	return Color(
		digits.substr(0, 2).hex_to_int() / 255.0,
		digits.substr(2, 2).hex_to_int() / 255.0,
		digits.substr(4, 2).hex_to_int() / 255.0
	)

#endregion
