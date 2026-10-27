class_name MlogImporter
extends RefCounted

## mlog 文本 → 逻辑节点（尚未入图，引用已绑好）。反向利用导出模板：行首字面量定位块类型，其余段按模板顺序回填字段 —— 模板是唯一真相，新增块自动可导入。
## jump 的行号按[b]这段文本自己[/b]重新分析：第 N 条指令就是文本里的第 N 条，与当前文档已有多少行无关 ——
## 否则导入/粘贴的片段里，jump 会直接连到文档里已有的块上。
## 结构块（XML `<Block marker="if">`）导出时会在指令行尾留一份字段快照 `#if 字段=值…`：导入靠它把这一行认回结构块、
## 还原字段与巢。没有标记的行照旧 —— 模板里 `<AfterSubtree/>` 那一格匹配不上，结构块导出的 jump 会当成普通 Jump 导进来。
const AFTER_KEY: StringName = &"@after"
## `<SelfLine/>`（本块自己那一行）：只用在尾跳模板上 —— 导入靠它把结构块的回跳从那一段里认出来。
const SELF_KEY: StringName = &"@self"


static func parse(
	text: String,
	library: BlockLibrary,
	graph: LogicGraph,
	warnings: Array[String] = []
) -> Array[LogicNode]:
	var out: Array[LogicNode] = []
	if text == "" or library == null or graph == null:
		return out
	var index := _build_index(library)
	var markers := _marker_index(library)
	## 与 out 平行：结构块的巢结束指令序号（-1 = 不是结构块）
	var ends: Array[int] = []
	## 与 out 平行：第 i 个节点在文本里的 0 基行号（只在警告里报位置）
	var src_lines: Array[int] = []
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	for line_index in lines.size():
		_import_line(String(lines[line_index]).strip_edges(), line_index,
				index, markers, graph, library, warnings, out, ends, src_lines)
	var structure := _build_structure(out, ends, library, warnings)
	var dropped: Dictionary = structure["dropped"]
	if not dropped.is_empty():
		# 尾跳不留在图里：它是导出时补的，导入还原时会重新生成
		var kept: Array[LogicNode] = []
		var kept_lines: Array[int] = []
		for i in out.size():
			if dropped.has(out[i].id):
				continue
			kept.append(out[i])
			kept_lines.append(src_lines[i])
		out = kept
		src_lines.assign(kept_lines)
	_resolve_links(out, structure["line_of"], src_lines, library, warnings)
	return out


## 导入一行：整行注释 / 带标记的指令行 / 普通语句行，各自的处理都在这一处。
static func _import_line(
	line: String,
	line_index: int,
	index: Dictionary,
	markers: Dictionary,
	graph: LogicGraph,
	library: BlockLibrary,
	warnings: Array[String],
	out: Array[LogicNode],
	ends: Array[int],
	src_lines: Array[int]
) -> void:
	if line == "":
		return
	# 注释行：整行余下部分就是注释块的文本（行尾标记只认指令行）
	if line.begins_with("#"):
		if library.has(&"Expression"):
			out.append(_make_node(graph, library.by_id(&"Expression"), {&"text": line.substr(1).strip_edges()}, {}))
			ends.append(-1)
			src_lines.append(line_index)
		return
	var marker := _read_marker(line, markers, warnings)
	for piece in MlogText.split_statements(line):
		var statement := piece.strip_edges()
		if statement == "":
			continue
		var tokens := MlogText.tokenize(statement)
		if tokens.is_empty():
			continue
		# 标签行没有对应的块了：出声说明，不静默丢掉这一行
		if tokens.size() == 1 and String(tokens[0]).ends_with(":"):
			warnings.append("mlog 的标签行（%s）不再支持：跳转目标改为在 Jump 上拖块锁定" % statement)
			continue
		# 带标记的行：按结构块自己的模板认，`<AfterSubtree/>` 那一格就是巢结束的行号
		if not marker.is_empty() and _import_marked(marker, tokens, statement, graph,
				warnings, out, ends, src_lines, line_index):
			continue
		var candidates: Array = index.get(StringName(tokens[0]), [])
		var hit: Variant = _try_defs(candidates, tokens)
		if hit == null:
			warnings.append("无法识别的 mlog 行：%s" % statement)
			continue
		out.append(_make_node(graph, hit["def"], hit["values"], hit["states"]))
		ends.append(-1)
		src_lines.append(line_index)


## 按结构标记导入一行（`#if 字段=值…`）；认不下来时报警并返回 false（调用方按普通语句再试）。
static func _import_marked(
	marker: Dictionary,
	tokens: PackedStringArray,
	statement: String,
	graph: LogicGraph,
	warnings: Array[String],
	out: Array[LogicNode],
	ends: Array[int],
	src_lines: Array[int],
	line_index: int
) -> bool:
	var def: BlockDef = marker["def"]
	var marked: Variant = _match_marked(def, tokens)
	if marked == null:
		warnings.append("结构标记 %s 与这一行不符，已按普通语句导入：%s" % [def.marker, statement])
		return false
	var values: Dictionary = marked["values"]
	var raw_after := String(values.get(AFTER_KEY, ""))
	var after := raw_after.to_int() if raw_after.is_valid_int() else -1
	if after < 0:
		warnings.append("结构标记 %s 的巢结束行号不是数字：%s" % [def.marker, raw_after])
	values.erase(AFTER_KEY)
	# 注释里的字段为准：模板里的比较是取反导出的，从行里认不回来
	values.merge(marker["fields"], true)
	out.append(_make_node(graph, def, values, marked["states"]))
	# 没有巢的标记块（Break / Continue）不参与结构还原
	ends.append(after if _nest_slot(def) != &"" else -1)
	src_lines.append(line_index)
	return true


## 把 [method parse] 的结果摊成若干棵子树（每棵是根在前、深度优先的节点表），形状正好给
## [method LogicGraph.insert_subtree] 用 —— 结构块的子节点已经挂在它的槽位里，不能再逐个插进链里。
static func subtrees(nodes: Array[LogicNode]) -> Array:
	var by_id: Dictionary = {}
	for node in nodes:
		by_id[node.id] = node
	var nested: Dictionary = {}
	for node in nodes:
		for slot_id in node.slots:
			for child_id in node.peek_slot(slot_id):
				nested[int(child_id)] = true
	var out: Array = []
	for node in nodes:
		if nested.has(node.id):
			continue
		var group: Array[LogicNode] = []
		_collect_subtree(by_id, node, group)
		out.append(group)
	return out


static func _collect_subtree(by_id: Dictionary, node: LogicNode, out: Array[LogicNode]) -> void:
	out.append(node)
	for slot_id in node.slots:
		for child_id in node.peek_slot(slot_id):
			var child: LogicNode = by_id.get(int(child_id))
			if child != null:
				_collect_subtree(by_id, child, out)


## 把跳转目标绑回块引用。数字行号指的是[b]这段文本自己[/b]的第 N 条指令（[param line_of] 由
## [method _build_structure] 按同一套数法算出），不查当前文档的行号表 —— 片段自成一体，不会连到已有的块上。
## 节点此刻尚未入图，不能用 graph.each_link_ref：按字段文本直接改写。
static func _resolve_links(nodes: Array[LogicNode], line_of: Dictionary, src_lines: Array[int],
		library: BlockLibrary, warnings: Array[String]) -> void:
	for i in nodes.size():
		var node := nodes[i]
		var at := int(src_lines[i]) + 1 if i < src_lines.size() else 0
		for field_id in _reference_fields_of(library, node):
			var raw := String(node.get_field(field_id, "")).strip_edges()
			if raw == "":
				continue
			if not raw.is_valid_int():
				# `jump label always 0 0` 这种标签引用：标签已不支持，按未锁定处理
				warnings.append("mlog 第 %d 行的跳转目标是标签 `%s`：标签已不支持，已按未锁定处理" % [at, raw])
				node.put_field(field_id, "")
				continue
			var want := int(raw)
			if want < 0:
				node.put_field(field_id, "")
			elif line_of.has(want):
				node.put_field(field_id, LogicGraph.make_link_ref(int(line_of[want])))
			else:
				warnings.append("mlog 第 %d 行的跳转目标（第 %d 行）不在导入的这段文本里，已按未锁定处理" % [at, want + 1])
				node.put_field(field_id, "")


## 某节点的块引用字段（「哪些字段是引用」的真相在块定义上；库换成了另一种语言也能用）。
static func _reference_fields_of(library: BlockLibrary, node: LogicNode) -> Array[StringName]:
	var def := library.by_id(node.type_id) if library != null else null
	return def.reference_fields() if def != null else [] as Array[StringName]



#region 内部

static func _make_node(graph: LogicGraph, def: BlockDef, values: Dictionary, states: Dictionary) -> LogicNode:
	var node := graph.new_node(def.id)
	def.apply_defaults(node)
	for field_id in values:
		node.fields[field_id] = values[field_id]
	for button_id in states:
		node.fields[button_id] = "true" if bool(states[button_id]) else "false"
	return node


static func _build_index(library: BlockLibrary) -> Dictionary:
	var index: Dictionary = {}
	for block_id in library.block_ids():
		var def := library.by_id(block_id)
		for shape in _shapes(def):
			var tokens: Array = shape["tokens"]
			if tokens.is_empty():
				continue
			var head := String(tokens[0].get("literal", ""))
			if head == "":
				continue
			var bucket: Array = index.get(StringName(head), [])
			if not bucket.has(def):
				bucket.append(def)
			index[StringName(head)] = bucket
	return index


static func _shapes(def: BlockDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for variant in def.export_variants:
		out.append({
			"tokens": _parts_to_tokens(variant.parts),
			"states": {variant.button: variant.pressed},
		})
	if not def.export_parts.is_empty():
		out.append({"tokens": _parts_to_tokens(def.export_parts), "states": {}})
	return out


## 尾跳模板（`<Tail>`）：只在「这一行是不是某个结构块的回跳」时才拿来对。
static func _tail_shapes(def: BlockDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not def.tail_parts.is_empty():
		out.append({"tokens": _parts_to_tokens(def.tail_parts), "states": {}})
	return out


## 把导出段合并成 token 模板（`space_before` 处开新 token，紧贴的段并进当前）；<FirstOf> 要带上整串候选，只带第一个会把值回填到错字段上。
static func _parts_to_tokens(parts: Array[ExportPart]) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	for part in parts:
		var text := ""
		var string_field := false
		var field: StringName = &""
		var candidates: Array[StringName] = []
		var after := false
		var self_line := false
		match part.kind:
			ExportPart.Kind.LITERAL:
				text = part.literal
			ExportPart.Kind.FIELD:
				field = part.field
				string_field = part.as_string
			ExportPart.Kind.AFTER_SUBTREE:
				after = true
			ExportPart.Kind.SELF_LINE:
				self_line = true
			_:
				candidates = part.fields
				if not candidates.is_empty():
					field = candidates[0]
		if tokens.is_empty() or part.space_before:
			tokens.append({"literal": text, "field": field, "suffix": "",
				"string": string_field, "fields": candidates, "after": after, "self": self_line})
			continue
		var token: Dictionary = tokens[-1]
		token["after"] = bool(token.get("after", false)) or after
		token["self"] = bool(token.get("self", false)) or self_line
		if token.get("field", &"") == &"" and field != &"":
			token["field"] = field
			token["string"] = string_field
			token["fields"] = candidates
			token["suffix"] = text
		elif field == &"":
			if token.get("field", &"") == &"":
				token["literal"] = String(token["literal"]) + text
			else:
				token["suffix"] = String(token["suffix"]) + text
	return tokens


## 试一组候选块，返回 {def, values, states} 或 null；按选项取值合法性打分取最高 —— ucontrol 那种模板同构的变体只能这样分开。
static func _try_defs(defs: Array, tokens: PackedStringArray) -> Variant:
	var best: Variant = null
	var best_score := -2147483648
	for def in defs:
		for shape in _shapes(def):
			var values: Variant = _match(def, shape["tokens"], shape["states"], tokens)
			if values == null:
				continue
			var normalized := _canonicalize(def, values)
			var score := _score(def, normalized)
			if score > best_score:
				best_score = score
				best = {"def": def, "values": normalized, "states": shape["states"]}
	return best


## 选项字段取值不合法就扣分（不是直接丢掉：认不出的新类型也比丢行强）。
static func _score(def: BlockDef, values: Dictionary) -> int:
	var score := 0
	for field_id in values:
		var element := def.option_element(field_id)
		if element != null and element.canonical_value(String(values[field_id])) == "":
			score -= 100
	return score


## 把选项字段的旧名字换成现在的名字（XML 里 `<Item value="angle" alias="atan2">`）。
static func _canonicalize(def: BlockDef, values: Dictionary) -> Dictionary:
	var out := values.duplicate()
	for field_id in out:
		var element := def.option_element(field_id)
		if element == null:
			continue
		var canonical := element.canonical_value(String(out[field_id]))
		if canonical != "":
			out[field_id] = canonical
	return out


## 模板与 token 逐一对照，返回字段值或 null；允许行比模板短（缺的参数保持默认，同 LogicIO.read）。
## [param allow_lines]：只有带结构标记的行才允许 `<AfterSubtree/>` / `<SelfLine/>` 那两格取到行号。
static func _match(def: BlockDef, template: Array, states: Dictionary, tokens: PackedStringArray,
		allow_lines: bool = false) -> Variant:
	if tokens.size() > template.size():
		return null
	var values: Dictionary = {}
	var value_of := _value_reader(def, values, states)
	for i in tokens.size():
		var slot: Dictionary = template[i]
		var token := tokens[i]
		var line_key: StringName = SELF_KEY if bool(slot.get("self", false)) else AFTER_KEY
		if bool(slot.get("after", false)) or bool(slot.get("self", false)):
			if not allow_lines:
				return null
			values[line_key] = token
			continue
		var literal := String(slot.get("literal", ""))
		var field: StringName = slot.get("field", &"")
		var candidates: Array = slot.get("fields", [])
		if candidates.size() > 1:
			# 多候选的一格：按已解析出的选项值挑生效那支（与导出共用 is_field_active）
			var chosen: StringName = &""
			for candidate in candidates:
				if def.is_field_active(candidate, value_of):
					chosen = candidate
					break
			if chosen == &"":
				continue
			field = chosen
		if field == &"":
			if token != literal:
				return null
			continue
		if literal != "":
			if not token.begins_with(literal):
				return null
			token = token.substr(literal.length())
		var suffix := String(slot.get("suffix", ""))
		if suffix != "":
			if not token.ends_with(suffix):
				return null
			token = token.substr(0, token.length() - suffix.length())
		# 字符串字段：必须带引号，去引号后再解码转义（与导出的加引号对称）
		if bool(slot.get("string", false)):
			if not MlogText.is_literal(token):
				return null
			values[field] = MlogText.unescape(token.substr(1, token.length() - 2))
			continue
		values[field] = token
	return values

## 匹配时的取值来源：先看本行已解析出的字段，再看字段默认值（与 `apply_defaults` 对齐）。
static func _value_reader(def: BlockDef, values: Dictionary, states: Dictionary) -> Callable:
	return func(field_id: StringName) -> String:
		if states.has(field_id):
			return "true" if bool(states[field_id]) else "false"
		if values.has(field_id):
			return String(values[field_id])
		var element := def.element(field_id)
		return element.default_value if element != null else ""


## marker 名 → 块定义（结构块在 XML 里用 `<Block marker="if">` 声明）。
static func _marker_index(library: BlockLibrary) -> Dictionary:
	var out: Dictionary = {}
	for block_id in library.block_ids():
		var def := library.by_id(block_id)
		if def != null and def.marker != "":
			out[StringName(def.marker)] = def
	return out


## 解析行尾标记：`#<名字> 字段=值 …`（值可带引号）；不是本程序的标记就返回空字典。
static func _read_marker(line: String, markers: Dictionary, warnings: Array[String]) -> Dictionary:
	var tokens := MlogText.tokenize(MlogText.trailing_comment(line))
	if tokens.is_empty():
		return {}
	var def: BlockDef = markers.get(StringName(tokens[0]))
	if def == null:
		return {}
	var fields: Dictionary = {}
	var known := def.field_ids()
	for i in range(1, tokens.size()):
		var at := tokens[i].find("=")
		var field_id := StringName(tokens[i].substr(0, at)) if at > 0 else &""
		if at <= 0 or not known.has(field_id) or def.is_reference_field(field_id):
			warnings.append("结构标记 %s 里认不出的字段：%s" % [def.marker, tokens[i]])
			continue
		var raw := tokens[i].substr(at + 1)
		fields[field_id] = MlogText.unescape(raw.substr(1, raw.length() - 2)) if MlogText.is_literal(raw) else raw
	return {"def": def, "fields": fields}


## 标记行的匹配：与普通行同一套模板，只是允许 `<AfterSubtree/>` 那一格取行号。
static func _match_marked(def: BlockDef, tokens: PackedStringArray) -> Variant:
	for shape in _shapes(def):
		var values: Variant = _match(def, shape["tokens"], shape["states"], tokens, true)
		if values != null:
			return {"values": values, "states": shape["states"]}
	return null


## 按结构块的巢结束序号把扁表还原成嵌套：挂进槽位后顺序不变，仍是文档顺序。
## 返回 `{dropped, line_of}`：要丢掉的节点 id（结构块自己的尾跳，导出时补、不挂回巢里），
## 以及[b]本段文本自己的行号表[/b]（指令序号 → 节点 id，跳转引用据此绑回块）。
static func _build_structure(nodes: Array[LogicNode], ends: Array[int], library: BlockLibrary,
		warnings: Array[String]) -> Dictionary:
	## 打开着的结构块：{node, slot, end（巢结束序号）, line（头部指令序号）}
	var open: Array[Dictionary] = []
	var dropped: Dictionary = {}
	## 尾跳也占一个号但不记进来，与导出的数法一致
	var line_of: Dictionary = {}
	var instruction := 0
	for i in nodes.size():
		var node := nodes[i]
		# 走到下一条指令前，先把已经到头的结构块收掉
		while not open.is_empty() and int(open[-1]["end"]) <= instruction:
			open.pop_back()
		# 尾跳：这个结构块的巢到此为止（它自己那一行不挂回巢里）
		if not open.is_empty():
			var head: LogicNode = open[-1]["node"]
			if _is_tail(library, library.by_id(head.type_id), node, int(open[-1]["line"])):
				dropped[node.id] = true
				open.pop_back()
				if _is_instruction_node(library, node):
					instruction += 1
				continue
		if not open.is_empty():
			var owner: LogicNode = open[-1]["node"]
			owner.slot(open[-1]["slot"]).append(node.id)
		var def := library.by_id(node.type_id)
		if ends[i] >= 0:
			var slot := _nest_slot(def)
			if slot == &"":
				warnings.append("结构块 %s 没有槽位，巢放不进去" % node.type_id)
			elif ends[i] <= instruction:
				warnings.append("结构块 %s 的巢结束行号（%d）在自己这一行之前" % [node.type_id, ends[i]])
			else:
				open.append({"node": node, "slot": slot, "end": ends[i], "line": instruction})
		if _is_instruction_node(library, node):
			line_of[instruction] = node.id
			instruction += 1
	return {"dropped": dropped, "line_of": line_of}


## 这一行是不是这个结构块自己的尾跳：对得上 `<Tail>` 模板，且 `<SelfLine/>` 指着它的头部。
static func _is_tail(library: BlockLibrary, def: BlockDef, node: LogicNode, head_line: int) -> bool:
	if def == null or def.tail_parts.is_empty():
		return false
	var node_def := library.by_id(node.type_id)
	if node_def == null:
		return false
	var tokens := MlogText.tokenize(MlogExporter.render_node(node_def, node))
	for shape in _tail_shapes(def):
		var values: Variant = _match(def, shape["tokens"], shape["states"], tokens, true)
		if values == null:
			continue
		var self_text := String(values.get(SELF_KEY, ""))
		if self_text.is_valid_int() and self_text.to_int() == head_line:
			return true
	return false


static func _is_instruction_node(library: BlockLibrary, node: LogicNode) -> bool:
	var def := library.by_id(node.type_id)
	return def != null and MlogText.is_instruction(MlogExporter.render_node(def, node))

## 结构块装巢的槽位：它的第一个槽位（XML 里的 `<Nest>`）。
static func _nest_slot(def: BlockDef) -> StringName:
	if def == null:
		return &""
	var slots := def.slot_ids()
	return slots[0] if not slots.is_empty() else &""

#endregion
