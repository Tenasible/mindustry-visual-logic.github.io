extends RefCounted
class_name BlockExport
## 扁平化导出器：把“容器（可能含 C 形积木嵌套）里的积木树”转成一段 Mindustry 逻辑文本。
##
## 为什么需要它：普通导出中 jump 的数值目标是“所在容器内的行号”，一旦 C 形积木
## 把多个子积木内联成多行，容器行号就不再等于指令绝对行号。本导出器：
##  1) 第一遍：深度优先给【每一个积木】分配绝对起始行号（map[node]），并记录
##     每个 C 形积木的结束行（end[node]）；
##  2) 第二遍：逐节点生成文本；普通积木调用其 compile()（jump 通过临时属性
##     __mvl_line_map 读到全局行号映射）；C 形积木走 cshape_header/footer 钩子，
##     header 的 skip_line = 本积木结束后的下一条指令行号（end[node]）。
## C 形积木的识别：节点实现了 cshape_body_children()/cshape_header_count() 等钩子。

const PROP_MAP := "export_line_map"


static func is_cshape(node: Node) -> bool:
	return node.has_method("cshape_body_children")


static func container_blocks(container: Node) -> Array:
	var out := []
	for c in container.get_children():
		if c is Control:
			out.append(c)
	return out


## 单个节点将产生的指令行数（叶子 1；C 形 = 头 + 身体递归 + 尾）。
static func count_lines_node(node: Node) -> int:
	if is_cshape(node):
		var total := int(node.cshape_header_count())
		for child in node.cshape_body_children():
			total += count_lines_node(child)
		total += int(node.cshape_footer_count())
		return total
	return 1


## 导出整个容器（返回含 \n 的文本）。
static func export_text(container: Node) -> String:
	var map := {}
	var ends := {}
	var cur := 0
	for child in container_blocks(container):
		cur = _assign_node(child, map, ends, cur)
	var out := []
	for child in container_blocks(container):
		_emit_node(child, map, ends, out)
	return "".join(out)


static func _assign_node(node: Node, map: Dictionary, ends: Dictionary, cur: int) -> int:
	if is_cshape(node):
		map[node] = cur
		cur += int(node.cshape_header_count())
		for child in node.cshape_body_children():
			cur = _assign_node(child, map, ends, cur)
		cur += int(node.cshape_footer_count())
		ends[node] = cur
		return cur
	map[node] = cur
	ends[node] = cur + 1
	return cur + 1


static func _emit_node(node: Node, map: Dictionary, ends: Dictionary, out: Array) -> void:
	if is_cshape(node):
		if int(node.cshape_header_count()) > 0:
			_arm(node, map)
			out.append(str(node.cshape_header_line(int(ends[node]))))
		for child in node.cshape_body_children():
			_emit_node(child, map, ends, out)
		if int(node.cshape_footer_count()) > 0:
			_arm(node, map)
			out.append(str(node.cshape_footer_line()))
	else:
		_arm(node, map)
		var text := str(node.call("compile"))
		if text.length() > 0:
			out.append(text)


static func _arm(node: Node, map: Dictionary) -> void:
	if node.has_method("compile"):
		node.set(PROP_MAP, map)
