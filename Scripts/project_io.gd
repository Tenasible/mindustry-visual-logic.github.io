extends RefCounted
class_name ProjectIO
## MVL 工程文件的序列化/反序列化。
##
## 与剪贴板导出/导入不同，本格式保存的是“编辑态”本身：
##   - 积木顺序（即行号位置）、每块积木的场景与实例 label_value（稳定锚点）；
##   - 每块积木的控件状态（LineEdit 文本、OptionButton 选中、开关按钮、滑块/数字框）；
##   - Jump 积木的跳线目标通过锚点（目标积木的 label_value）保存，加载后按锚点重连，
##     因此插入/合并行导致行号变化时跳线指向依然正确；
##   - 支持 configure 积木动态增删的 ConfigSetting 行（按实际节点名重建）。
## 不经过 compile()/剪贴板文本，因此不存在导出过程中的不可逆转译。

const FORMAT := "mvl-project"
const VERSION := 1
const CONFIG_SETTING_SCENE := "res://Scenes/config_setting.tscn"

## 捕获 %UserBlocks 的整块工程数据（纯数据，不含引用；C 形积木身体递归进 children）
static func capture_project(userblocks: Node) -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"blocks": _capture_nodes(userblocks),
	}


static func _capture_nodes(container: Node) -> Array:
	var blocks: Array = []
	for block in container.get_children():
		if not (block is Control):
			continue
		var scene_path: String = block.scene_file_path
		if scene_path == "":
			push_warning("跳过无场景文件的积木: " + block.name)
			continue
		var entry := {
			"scene": scene_path,
			"label": _block_label(block),
			"ui": _capture_ui(block),
		}
		if _is_jump_block(block):
			entry["jump"] = {"anchor": _jump_anchor(block)}
		if block.has_method("cshape_body_children"):
			var body: Node = _body_of(block)
			if body != null:
				entry["children"] = _capture_nodes(body)
		blocks.append(entry)
	return blocks


static func _body_of(block: Node) -> Node:
	if block.has_method("body_container"):
		return block.call("body_container")
	return null


## 把工程数据应用到目标容器（可传入 empty 容器或已有内容的容器做“插入”）。
## 返回错误信息数组（空=成功）。
static func apply_project(userblocks: Node, data: Dictionary, easy_input: Node = null) -> Array:
	var errors: Array = []
	if data.get("format", "") != FORMAT:
		return ["不是有效的 MVL 工程文件（format 缺失或不符）"]
	var blocks: Array = data.get("blocks", [])
	var loaded: Array = []
	_apply_entries(userblocks, blocks, easy_input, loaded, errors)

	# 阶段2：按锚点重连 Jump 跳线（整棵树查找，此时所有积木都已就位）
	for block in loaded:
		var anchor = block.get("_mvl_load_anchor")
		if anchor != null and str(anchor) != "" and _is_jump_block(block):
			_relink_jump(block, str(anchor), userblocks)

	# 阶段3：让容器刷新行号/跳线布局
	if userblocks.has_method("_on_block_moved"):
		userblocks._on_block_moved()
	else:
		for block in _all_blocks(userblocks):
			if block.has_method("_on_any_block_moved"):
				block._on_any_block_moved()
	return errors


static func _apply_entries(container: Node, entries: Array, easy_input: Node, loaded: Array, errors: Array) -> void:
	for entry in entries:
		var scene_path: String = str(entry.get("scene", ""))
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			errors.append("缺少积木场景: " + scene_path)
			continue
		var scene: PackedScene = load(scene_path)
		var block: Control = scene.instantiate()
		container.add_child(block)
		_set_prop(block, "origin_node", container)
		if easy_input != null:
			_set_prop(block, "input_node", easy_input)
		if entry.has("label"):
			_set_prop(block, "label_value", str(entry["label"]))
		if entry.has("jump"):
			block.set("_mvl_load_anchor", str(entry["jump"].get("anchor", "")))
		# configure 积木：先按保存时的行重建（名字/数量/顺序一致）
		if _is_configure_block(block):
			_rebuild_configure_rows(block, entry, errors)
		_apply_ui(block, entry.get("ui", {}), errors)
		loaded.append(block)
		# C 形积木：递归恢复身体内子积木
		if entry.has("children") and block.has_method("cshape_body_children"):
			var body: Node = _body_of(block)
			if body == null:
				errors.append("C 形积木缺少身体容器: " + scene_path)
			else:
				_apply_entries(body, entry["children"], easy_input, loaded, errors)


## 保存到文件；成功返回 OK
static func save_to_file(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入工程文件: " + path + " (" + str(FileAccess.get_open_error()) + ")")
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK


## 从文件读取；返回 Dictionary（失败返回 null）
static func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("工程文件不存在: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取工程文件: " + path)
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		push_error("工程文件 JSON 解析失败: " + path)
		return {}
	if not (parser.data is Dictionary):
		push_error("工程文件内容不是对象: " + path)
		return {}
	return parser.data


# ---------- 内部实现 ----------

static func _block_label(block: Node) -> String:
	if _has_prop(block, "label_value"):
		var v = block.get("label_value")
		if v != null:
			return str(v)
	return ""


static func _has_prop(node: Node, prop: String) -> bool:
	for p in node.get_property_list():
		if p["name"] == prop:
			return true
	return false


static func _set_prop(node: Node, prop: String, value) -> void:
	if _has_prop(node, prop):
		node.set(prop, value)


static func _scene_basename(block: Node) -> String:
	var p := block.scene_file_path
	return p.get_file().get_basename().to_lower()


static func _is_jump_block(block: Node) -> bool:
	return _scene_basename(block) == "jump"


static func _is_configure_block(block: Node) -> bool:
	return _scene_basename(block) == "configure"


static func _jump_anchor(block: Node) -> String:
	if not _has_prop(block, "jump_to"):
		return ""
	var target: Node = block.get("jump_to")
	if is_instance_valid(target) and target != null:
		return _block_label(target)
	return ""


## 深度收集积木子树内的“状态控件”（排除运行时索引标签等动态节点）。
static func _capture_ui(block: Node) -> Dictionary:
	var ui := {}
	_collect_controls(block, block, ui)
	return ui


static func _collect_controls(root: Node, node: Node, ui: Dictionary) -> void:
	for child in node.get_children():
		# 遇到“另一个积木的根”（嵌套在 C 形身体里的积木）不采集：
		# 它的状态由各自的 entry 递归保存，避免路径冲突/重复
		if child.has_method("spawn_index_node"):
			continue
		var value = _control_value(child)
		if value != null:
			ui[root.get_path_to(child)] = value
		_collect_controls(root, child, ui)


## 返回控件的可序列化值（字符串）；非状态控件返回 null
static func _control_value(node: Node):
	if node is LineEdit:
		return node.text
	elif node is OptionButton:
		return str(node.selected)
	elif node is SpinBox:
		return str(node.value)
	elif node is HSlider:
		return str(node.value)
	elif node is CheckBox or node is CheckButton:
		return "1" if node.button_pressed else "0"
	elif node is Button:
		# 只有 toggle 按钮的按下态才是有意义的持久状态（如 print/format 的引号开关）
		if node.toggle_mode:
			return "1" if node.button_pressed else "0"
	return null


static func _apply_ui(block: Node, ui: Dictionary, errors: Array) -> void:
	for path in ui:
		var node := block.get_node_or_null(str(path))
		if node == null:
			errors.append(block.name + " 缺少节点: " + str(path))
			continue
		_apply_value(node, str(ui[path]))


static func _apply_value(node: Node, value: String) -> void:
	if node is LineEdit:
		node.text = value
	elif node is OptionButton:
		var idx := int(value)
		if idx >= 0 and idx < node.item_count:
			node.selected = idx
	elif node is SpinBox:
		node.value = float(value)
	elif node is HSlider:
		node.value = float(value)
	elif node is CheckBox or node is CheckButton:
		node.button_pressed = value == "1"
	elif node is Button and node.toggle_mode:
		node.button_pressed = value == "1"


## configure 积木：把 Configures 下的行重建为保存时的行集合（名字/顺序一致）
static func _rebuild_configure_rows(block: Node, entry: Dictionary, errors: Array) -> void:
	var row_names: Array = []
	var ui: Dictionary = entry.get("ui", {})
	var prefix := "HBoxContainer/Configures/"
	for path in ui:
		var ps := str(path)
		if ps.begins_with(prefix):
			var rest := ps.trim_prefix(prefix)
			var segs := rest.split("/")
			if segs.size() >= 1 and not row_names.has(segs[0]):
				row_names.append(segs[0])
	var configures: Node = block.get_node_or_null("HBoxContainer/Configures")
	if configures == null:
		errors.append("configure 积木结构异常（缺少 %Configures）")
		return
	# 清空默认/旧行
	for row in configures.get_children():
		configures.remove_child(row)
		row.free()
	var row_scene: PackedScene = load(CONFIG_SETTING_SCENE)
	if row_scene == null:
		errors.append("缺少行场景: " + CONFIG_SETTING_SCENE)
		return
	for row_name in row_names:
		var row: Node = row_scene.instantiate()
		row.name = str(row_name)
		configures.add_child(row)


## 在行号最终确定后重连 jump 的跳线目标（按锚点在整棵积木树中查找）
static func _relink_jump(block: Node, anchor: String, userblocks: Node) -> void:
	if not _is_jump_block(block):
		return
	var target: Node = null
	if anchor != "":
		for cand in _all_blocks(userblocks):
			if is_instance_valid(cand) and _block_label(cand) == anchor:
				target = cand
				break
	if target != null and is_instance_valid(target):
		_set_prop(block, "jump_to", target)
		if _has_prop(block, "jump_index"):
			block.jump_index = target.get_index()
		# 同步显示行号（目标在其所在容器里的行号）
		var cnode: Node = block.get_node_or_null("%c")
		if cnode is LineEdit:
			cnode.text = str(target.get_index())
		if block.has_method("set_jump_dictionary"):
			block.set_jump_dictionary(target.get_index())
	else:
		_set_prop(block, "jump_to", null)
		if block.has_method("set_jump_dictionary"):
			block.set_jump_dictionary(-1)


## 收集积木树（含 C 形身体内嵌套）里的全部积木，深度优先。
static func _all_blocks(root: Node) -> Array:
	var out := []
	for child in root.get_children():
		if child is Control:
			_collect_block_rec(child, out)
	return out


static func _collect_block_rec(block: Node, out: Array) -> void:
	out.append(block)
	if block.has_method("cshape_body_children"):
		for gc in block.cshape_body_children():
			if gc is Control:
				_collect_block_rec(gc, out)
