class_name ConditionDef
extends RefCounted

## 一个「何时生效」的条件表达式（AST）：行、元素、导出模板都可以挂一个。
## 字符串只用于手写与回写（[ConditionParser] 的 `&` `|` `~`、`字段=取值`、`mode=a|b`），解析后是这棵树。

enum Kind {
	ALWAYS,
	## 字段比较：field 的值落在 values 里（等值），或"字段为真"（values 为空）。
	COMPARE,
	AND,
	OR,
	NOT,
}

var kind: Kind = Kind.ALWAYS

var field: StringName = &""
## COMPARE：候选取值（或列表）；为空表示只判断"字段为真"。
var values: Array[String] = []
var negated: bool = false

var children: Array[ConditionDef] = []
var child: ConditionDef = null


static func always() -> ConditionDef:
	return ConditionDef.new()


static func compare(field_id: StringName, accepted: Array[String], is_negated: bool = false) -> ConditionDef:
	var condition := ConditionDef.new()
	condition.kind = Kind.COMPARE
	condition.field = field_id
	condition.values = accepted
	condition.negated = is_negated
	return condition


## 全部成立。空列表 = 恒真，单个子条件时直接返回它（避免无谓嵌套）。
static func all_of(list: Array[ConditionDef]) -> ConditionDef:
	if list.is_empty():
		return always()
	if list.size() == 1:
		return list[0]
	var condition := ConditionDef.new()
	condition.kind = Kind.AND
	condition.children = list
	return condition


## 任一成立；空列表 = 恒假（用一个永不成立的条件表示）。
static func any_of(list: Array[ConditionDef]) -> ConditionDef:
	if list.is_empty():
		return compare(&"", [""])
	if list.size() == 1:
		return list[0]
	var condition := ConditionDef.new()
	condition.kind = Kind.OR
	condition.children = list
	return condition


static func negate(inner: ConditionDef) -> ConditionDef:
	if inner == null:
		return always()
	var condition := ConditionDef.new()
	condition.kind = Kind.NOT
	condition.child = inner
	return condition


## 求值。[param value_of] 收字段 id、返回其当前值字符串（数据层为准）。
func matches(value_of: Callable) -> bool:
	match kind:
		Kind.COMPARE:
			# field 为空 = 恒假（any_of([]) 用它当哨兵）
			if field == &"":
				return false
			var raw := String(value_of.call(field))
			var hit := false
			if values.is_empty():
				hit = raw != "" and raw != "false"
			else:
				hit = values.has(raw)
			return not hit if negated else hit
		Kind.AND:
			for item in children:
				if not item.matches(value_of):
					return false
			return true
		Kind.OR:
			for item in children:
				if item.matches(value_of):
					return true
			return false
		Kind.NOT:
			return not (child != null and child.matches(value_of))
		_:
			return true


## 表达式里引用到的字段（去重，按出现顺序）。
func fields() -> Array[StringName]:
	var out: Array[StringName] = []
	_collect_fields(out)
	return out


func _collect_fields(out: Array[StringName]) -> void:
	if kind == Kind.COMPARE:
		if field != &"" and not out.has(field):
			out.append(field)
		return
	for item in children:
		item._collect_fields(out)
	if child != null:
		child._collect_fields(out)


func is_always() -> bool:
	return kind == Kind.ALWAYS


func describe() -> String:
	match kind:
		Kind.COMPARE:
			var plain := String(field) if field != &"" else "false"
			if values.is_empty():
				return ("~" + plain) if negated else plain
			var alternatives := PackedStringArray()
			for value in values:
				alternatives.append(_quote_if_needed(value))
			return "%s%s%s" % [plain, "!=" if negated else "=", "|".join(alternatives)]
		Kind.AND, Kind.OR:
			var glue := " & " if kind == Kind.AND else " | "
			var pieces := PackedStringArray()
			for item in children:
				var text := item.describe()
				if _needs_parens(item, kind):
					text = "(" + text + ")"
				pieces.append(text)
			if pieces.is_empty():
				return "true" if kind == Kind.AND else "false"
			return glue.join(pieces)
		Kind.NOT:
			var inner := child.describe() if child != null else "false"
			if child != null and child.kind == Kind.COMPARE:
				return "~" + inner
			return "~(" + inner + ")"
		_:
			return "true"


static func _needs_parens(item: ConditionDef, parent: Kind) -> bool:
	# ~ 比 & 紧、& 比 | 紧，所以只有「或」嵌在「与」里才需要括号
	if parent == Kind.AND:
		return item.kind == Kind.OR
	return false


static func _quote_if_needed(text: String) -> String:
	if text == "" or text.contains(" ") or text.contains("|") or text.contains("(") or text.contains(")"):
		return "\"" + text + "\""
	return text
