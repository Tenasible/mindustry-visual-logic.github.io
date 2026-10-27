class_name MlogText
extends RefCounted

## mlog 文本工具（对齐 Mindustry 的 LParser）：字符串字面量读写 + 引号感知的行拆分。
## 字面量只认 `\n` `\"` `\\` `\uXXXX`，其余原样保留 —— 读写两侧必须共用这一套。
## 写：逻辑字符串 → 字面量内容（不含引号）。
static func escape(value: String) -> String:
	var out := ""
	for i in value.length():
		match value[i]:
			"\\":
				out += "\\\\"
			"\"":
				out += "\\\""
			"\n":
				out += "\\n"
			"\r":
				out += "\\n"
			_:
				out += value[i]
	return out


## 读：字面量内容（不含引号）→ 逻辑字符串。
static func unescape(raw: String) -> String:
	if not raw.contains("\\"):
		return raw
	var out := ""
	var i := 0
	while i < raw.length():
		var ch := raw[i]
		if ch == "\\" and i + 1 < raw.length():
			var next := raw[i + 1]
			if next == "n":
				out += "\n"
				i += 2
				continue
			if next == "\"" or next == "\\":
				out += next
				i += 2
				continue
			if next == "u" and i + 5 < raw.length():
				var code := raw.substr(i + 2, 4).hex_to_int()
				if code > 0:
					out += String.chr(code)
					i += 6
					continue
		out += ch
		i += 1
	return out


static func is_literal(token: String) -> bool:
	return token.length() >= 2 and token.begins_with("\"") and token.ends_with("\"")


## 把一行切成若干条语句：`;` 分隔语句，`#` 起行尾注释（引号里的不算，同 LParser）。
static func split_statements(line: String) -> PackedStringArray:
	return _scan(line, &"statement")


## 引号外按空白切 token（引号里的空白属于字面量）。
static func tokenize(line: String) -> PackedStringArray:
	return _scan(line, &"token")


## 引号感知的行扫描：一个循环服务上面两套切法 —— 引号里的字符一律原样保留。
## 只有 statement 模式把引号外的 `#` 当行尾注释截断；token 模式的调用方自带完整行（含标记行），
## 截断会误删标记内容。
static func _scan(line: String, mode: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var in_quote := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_quote = not in_quote
			current += ch
			continue
		if mode == &"statement" and not in_quote and ch == "#":
			break
		if not in_quote and (ch == ";" if mode == &"statement" else ch == " "):
			if mode == &"statement" or current != "":
				out.append(current)
				current = ""
			continue
		current += ch
	if mode == &"statement" or current != "":
		out.append(current)
	return out


## 行尾注释（不在引号里的第一个 `#` 之后的部分）；没有则返回 ""。
## 与 _scan 同一套「引号外才认 #」规则，但不切分、只找注释起点。
## 必须用 while：GDScript 的 for 循环变量在循环体内赋值不会影响迭代。
static func trailing_comment(line: String) -> String:
	var i := 0
	while i < line.length():
		var ch := line[i]
		if ch == "\"":
			# 跳过整段字符串；无闭引号时走到行尾（注释不会从字符串里开始）
			i += 1
			while i < line.length() and line[i] != "\"":
				i += 1
		elif ch == "#":
			return line.substr(i + 1).strip_edges()
		i += 1
	return ""


## 这一行会不会成为一条指令（导出与导入数行号用同一套规则）。
## 注释行不占行号；标签行 `label:` 已经造不出来了（跳转目标改成块引用），
## 但别人手写的 mlog 里还有，仍按 LParser 的数法不占行号。
static func is_instruction(text: String) -> bool:
	if text == "" or text.begins_with("#"):
		return false
	return not (text.ends_with(":") and not text.contains(" "))
