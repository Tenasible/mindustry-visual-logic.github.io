class_name MlogExporter
extends RefCounted

## 逻辑图 → mlog 文本（纯函数：只读图与块库，不碰控件）。遍历按链顺序深度优先：块自己一行，再是各槽位内容，最后下一个兄弟。
## 块引用是「第几行」，行号得排完整段才知道 —— 第一趟 [_walk] 排行号表，第二趟渲染时用同一份 walk 把引用换成行号（表与输出必然对得上）。

## 导出整张图。[param warnings] 收集无法处理的块与失效的跳转目标。
static func export(graph: LogicGraph, library: BlockLibrary, warnings: Array[String] = []) -> String:
	if graph == null or library == null:
		return ""
	var walk := _walk(graph, library, warnings)
	var table := _table_of(walk)
	var lines := PackedStringArray()
	for entry in walk:
		var def: BlockDef = entry["def"]
		var node: LogicNode = entry["node"]
		var line := render_entry(entry, table, warnings)
		if line != "":
			lines.append(line)
	if lines.is_empty():
		return ""
	# 末尾默认补一条停止：跑出程序末尾本来就等于停住，写明它之后指向程序外的 jump（after == count）也有了落点
	if not _ends_with_halt(lines):
		lines.append("stop")
	return "\n".join(lines) + "\n"


## 末尾那条指令是不是 `stop` / `end`（后面只跟注释也算）：是就不再补。
static func _ends_with_halt(lines: PackedStringArray) -> bool:
	for i in range(lines.size() - 1, -1, -1):
		var line := String(lines[i])
		if not MlogText.is_instruction(line):
			continue
		var head := line.split(" ", false)
		return not head.is_empty() and (head[0] == "stop" or head[0] == "end")
	return false


## [param after_line] 是本块子树之后的第一条指令行号（`<AfterSubtree/>` 用它；算不出来时传 -1）。
static func render_node(def: BlockDef, node: LogicNode, resolver: Callable = Callable(),
		after_line: int = -1) -> String:
	var out := _render_parts(def, node, def.export_parts_for(node.value_reader()), resolver, after_line, -1)
	# 行尾标记只写在头部那一条上，尾跳没有标记
	if out != "" and def.marker != "":
		out += " #%s%s" % [def.marker, marker_fields(def, node)]
	return out


## 结构块的尾跳（XML `<Tail>`）：整段巢之后补的那一条，`<SelfLine/>` 取本块头部那一行。
static func render_tail(def: BlockDef, node: LogicNode, self_line: int) -> String:
	return _render_parts(def, node, def.tail_parts, Callable(), -1, self_line)


## 渲染一条 entry（导入侧数指令序号时只关心它会不会成为指令，行号给 -1 即可）。
static func render_entry(entry: Dictionary, table: Dictionary = {}, warnings: Array[String] = []) -> String:
	var def: BlockDef = entry["def"]
	var node: LogicNode = entry["node"]
	if bool(entry.get("tail", false)):
		return render_tail(def, node, int(table.get("line_of", {}).get(node.id, -1)))
	if table.is_empty():
		return render_node(def, node)
	var after: int = int(table.get("after", {}).get(node.id, -1))
	if def.loop_jump != &"":
		after = int(table.get("loop", {}).get(node.id, -1))
		if after < 0:
			warnings.append("%s 不在循环里：跳转目标按 -1 导出" % def.id)
	return render_node(def, node, _resolver(node, table, warnings), after)


static func _render_parts(def: BlockDef, node: LogicNode, parts: Array[ExportPart], resolver: Callable,
		after_line: int, self_line: int) -> String:
	if parts.is_empty():
		return ""
	var value_of := node.value_reader()
	var out := ""
	for part in parts:
		var text := _render_part(def, node, part, value_of, resolver, after_line, self_line)
		if text == "":
			continue
		if part.space_before and out != "":
			out += " "
		out += text
	return out


## 结构块写在行尾的字段快照（`#if a=1 cmp=equal b=2`）：导入靠它把这一行还原成结构块。
## 字段要写全 —— 模板里的比较是取反导出的，从行里认不回原来的取值。
static func marker_fields(def: BlockDef, node: LogicNode) -> String:
	var out := ""
	for field_id in def.field_ids():
		if def.is_reference_field(field_id):
			continue
		out += " %s=%s" % [String(field_id), _marker_value(String(node.get_field(field_id, "")))]
	return out


## 标记里的一个值：空值 / 含空白 / 含引号就加引号（注释里也按 mlog 字面量的转义写法写）。
static func _marker_value(value: String) -> String:
	var simple := value != ""
	for ch in [" ", "\t", "\n", "\r", "\""]:
		simple = simple and not value.contains(ch)
	return value if simple else "\"" + MlogText.escape(value) + "\""


## 遍历顺序表。不输出行的块也在表里（不占行号，但跳转落到它之后的第一条指令）；只导出入口块那条链，没有入口块就什么都不导出。
static func _walk(graph: LogicGraph, library: BlockLibrary, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entry := library.find_entry(graph) if library != null else null
	if entry == null:
		return out
	var where := graph.locate(entry.id)
	if where.is_empty():
		return out
	var siblings := graph.slot_items(int(where["owner_id"]), StringName(where["slot"]))
	var tail: Array[int] = []
	tail.assign(siblings.slice(int(where["index"])))
	_walk_chain(graph, library, tail, out, warnings, 0)
	return out


static func _walk_chain(
	graph: LogicGraph,
	library: BlockLibrary,
	ids: Array[int],
	out: Array[Dictionary],
	warnings: Array[String],
	loop_id: int
) -> void:
	for id in ids:
		var node := graph.get_node_by_id(id)
		if node == null:
			continue
		var def := library.by_id(node.type_id)
		if def == null:
			warnings.append("未知块类型：%s" % node.type_id)
			continue
		# 记下所属的最内层循环：Break / Continue 的跳转目标由它决定
		out.append({"node": node, "def": def, "loop": loop_id})
		var at := out.size() - 1
		var inner := id if def.loop else loop_id
		for slot_id in def.slot_ids():
			_walk_chain(graph, library, graph.slot_items(id, slot_id), out, warnings, inner)
		if not def.tail_parts.is_empty():
			out.append({"node": node, "def": def, "tail": true, "loop": loop_id})
		# 子树（连尾跳）在 walk 里是连续的：递归完它，out 的长度就是「本块之后」那个 entry 的下标
		out[at]["end"] = out.size()


## 排行号：[b]数的是指令而不是文本行[/b] —— 注释行与标签行不占行号，只记 fallback。
static func _table_of(walk: Array[Dictionary]) -> Dictionary:
	var line_of: Dictionary = {}
	var fallback: Dictionary = {}
	## 节点 id → 本块子树之后的第一条指令行号（结构块的条件跳转目标）
	var after: Dictionary = {}
	var count := 0
	var lines_at: Array[int] = []
	for entry in walk:
		var def: BlockDef = entry["def"]
		var node: LogicNode = entry["node"]
		var text := render_entry(entry)
		lines_at.append(count)
		# 尾跳也占一行，但「这个块在第几行」说的是它的头部那一条
		if not bool(entry.get("tail", false)):
			fallback[node.id] = count
			if MlogText.is_instruction(text):
				line_of[node.id] = count
		if MlogText.is_instruction(text):
			count += 1
	lines_at.append(count)
	var loop_tail: Dictionary = {}
	for entry in walk:
		var node: LogicNode = entry["node"]
		if bool(entry.get("tail", false)):
			continue
		var def: BlockDef = entry["def"]
		var end := int(entry.get("end", walk.size()))
		after[node.id] = lines_at[end]
		# 循环的回跳 / 条件判断点：Continue 要落到它上面才能重新判断条件
		if def.loop and end > 0 and bool(walk[end - 1].get("tail", false)):
			loop_tail[node.id] = lines_at[end - 1]
	# Break / Continue 的跳转目标：Break 去循环之后，Continue 回循环的回跳点
	var loop: Dictionary = {}
	for entry in walk:
		var def: BlockDef = entry["def"]
		if def.loop_jump == &"":
			continue
		var node: LogicNode = entry["node"]
		var owner := int(entry.get("loop", 0))
		var target := -1
		if owner > 0:
			if def.loop_jump == &"continue":
				target = int(loop_tail.get(owner, line_of.get(owner, -1)))
			else:
				target = int(after.get(owner, -1))
		loop[node.id] = target
	return {"line_of": line_of, "fallback": fallback, "after": after, "loop": loop, "count": count}



## 引用字段 → 行号；未锁定或目标已失效都按 -1 导出并记一条警告。
static func _resolver(node: LogicNode, table: Dictionary, warnings: Array[String]) -> Callable:
	var line_of: Dictionary = table["line_of"]
	var fallback: Dictionary = table["fallback"]
	return func(field_id: StringName) -> String:
		var target := LogicGraph.parse_link_ref(node.get_field(field_id, ""))
		if target <= 0:
			warnings.append("Jump 没有锁定跳转目标（按 -1 导出）")
			return "-1"
		if line_of.has(target):
			return str(line_of[target])
		if fallback.has(target):
			return str(fallback[target])
		warnings.append("Jump 的跳转目标已失效（按 -1 导出）")
		return "-1"


static func _render_part(
	def: BlockDef,
	node: LogicNode,
	part: ExportPart,
	value_of: Callable,
	resolver: Callable,
	after_line: int,
	self_line: int
) -> String:
	match part.kind:
		ExportPart.Kind.LITERAL:
			return part.literal
		ExportPart.Kind.FIELD:
			var text := _field_text(def, node, part.field, resolver, part.allow_empty)
			# 字符串字段：引号在这里加并转义 —— 否则用户打一个引号就会把整行写坏
			return _quoted(text) if part.as_string else text
		ExportPart.Kind.AFTER_SUBTREE:
			return str(after_line)
		ExportPart.Kind.SELF_LINE:
			return str(self_line)
		_:
			for field_id in part.fields:
				if def.is_field_active(field_id, value_of):
					return _field_text(def, node, field_id, resolver)
			return "0"


## 取字段的 mlog 文本：块引用换成行号，其余按原值；[param allow_empty] 时空值不补 0。
static func _field_text(def: BlockDef, node: LogicNode, field_id: StringName, resolver: Callable,
		allow_empty: bool = false) -> String:
	if def.is_reference_field(field_id) and resolver.is_valid():
		return String(resolver.call(field_id))
	var value := String(node.get_field(field_id, ""))
	if value != "" or allow_empty:
		return value
	return "0"


static func _quoted(text: String) -> String:
	return "\"" + MlogText.escape(text) + "\""
