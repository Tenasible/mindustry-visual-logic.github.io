class_name ElementBuilders
extends RefCounted

## 内置元素构建器 + 注册。每个构建器只覆盖自己关心的回调（契约见 [ElementBuilder]），host 是 [BlockView]。
## 新增一种元素类型：在这里加个子类并注册即可 —— 解析、条件校验、默认值都不用动。

static func install() -> void:
	ElementRegistry.register(&"Text", TextBuilder.new())
	ElementRegistry.register(&"LineBox", InputBuilder.new())
	ElementRegistry.register(&"Option", OptionBuilder.new())
	ElementRegistry.register(&"Button", ToggleBuilder.new())
	ElementRegistry.register(&"Selector", SelectorBuilder.new())
	ElementRegistry.register(&"Nest", NestBuilder.new())
	ElementRegistry.register(&"JumpTarget", JumpTargetBuilder.new())


static func make_edit(element: ElementDef, host: Object, min_width: float) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = element.placeholder
	edit.text = String(host.field_value(element.id, element.default_value))
	edit.custom_minimum_size = Vector2(min_width, 0)
	host.apply_font(edit)
	if host.is_preview():
		edit.editable = false
		edit.focus_mode = Control.FOCUS_NONE
	else:
		edit.text_changed.connect(func(text: String) -> void:
			host.commit_field(element.id, text, true))
		edit.focus_exited.connect(func() -> void:
			host.flush_history_group())
	return edit


## 回填输入框：正在输入的控件不动，避免光标跳位。
static func apply_edit_value(control: Control, value: String, force: bool = false) -> void:
	var edit := resolve_edit(control)
	if edit == null:
		return
	if force or not edit.has_focus():
		edit.text = value


## 组合控件（Selector）里真正存值的那个输入框：先看控件自己，再看 value_control 元数据。
static func resolve_edit(control: Control) -> LineEdit:
	if control is LineEdit:
		return control
	if control != null and control.has_meta(&"value_control"):
		var inner: Variant = control.get_meta(&"value_control")
		if inner is LineEdit:
			return inner
	return null


## 开关一个元素控件：用 disabled（而不是 mouse_filter）是为了连键盘也不响应，且不会发出信号改数据。
static func set_control_enabled(control: Control, enabled: bool) -> void:
	var edit := resolve_edit(control)
	if edit != null:
		edit.editable = enabled
		edit.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		if not enabled and edit.has_focus():
			edit.release_focus()
	_set_buttons_disabled(control, not enabled)


static func _set_buttons_disabled(node: Node, disabled: bool) -> void:
	if node is BaseButton:
		(node as BaseButton).disabled = disabled
	for child in node.get_children():
		_set_buttons_disabled(child, disabled)


## 承载字段值的元素：默认按输入框处理（回填 / 禁用）；按钮类字段只覆写 apply_value。
class FieldBuilder extends ElementBuilder:
	func is_field() -> bool:
		return true

	func apply_value(_element: ElementDef, control: Control, value: String, force: bool = false) -> void:
		ElementBuilders.apply_edit_value(control, value, force)

	func set_enabled(_element: ElementDef, control: Control, enabled: bool) -> void:
		ElementBuilders.set_control_enabled(control, enabled)


## 静态文本：不吃鼠标，从标签上按下也能拖动整块。
class TextBuilder extends ElementBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		var label := Label.new()
		label.text = element.text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.apply_font(label)
		return label


## 文本输入框：连续输入合并成一条撤销记录。
class InputBuilder extends FieldBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		return ElementBuilders.make_edit(element, host, 64.0)


class OptionBuilder extends FieldBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		var option := OptionButton.new()
		for item in element.items:
			option.add_item(item.text)
		host.style_button(option)
		apply_value(element, option, String(host.field_value(element.id, "")))
		_fit_width(option, element, host)
		if host.is_preview():
			option.disabled = true
		else:
			option.item_selected.connect(func(selected: int) -> void:
				if selected < element.items.size():
					host.commit_field(element.id, element.items[selected].value_or_text(), false)
				host.refresh_visibility())
		return option

	## OptionButton 默认 fit_to_longest_item：每个新实例都要把全部候选量一遍（45 项约 90 ms），
	## 而拖动起手要为每个被拖块新建整棵控件树，这笔钱会把整帧卡住。
	## 做法：第一次让引擎量出真实宽度（保证逐像素一致）并缓存在元素定义上，之后的实例直接关掉 fit 沿用。
	func _fit_width(option: OptionButton, element: ElementDef, _host: Object) -> void:
		if element.option_text_width >= 0.0:
			_shrink(option, element.option_text_width)
			return
		option.ready.connect(_cache_fit_width.bind(option, element), CONNECT_ONE_SHOT)

	## 入树之后才能拿到带主题字号的真实宽度：量一次、记住、然后关掉 fit。
	func _cache_fit_width(option: OptionButton, element: ElementDef) -> void:
		if not is_instance_valid(option):
			return
		var width := option.get_combined_minimum_size().x
		if width > 0.0:
			element.option_text_width = width
		_shrink(option, width)
		# 关掉 fit 会把最小尺寸重新作废，让宿主按新宽度再量一次
		option.update_minimum_size()

	func _shrink(option: OptionButton, width: float) -> void:
		option.fit_to_longest_item = false
		if width > 0.0:
			option.custom_minimum_size.x = maxf(option.custom_minimum_size.x, width)

	func apply_value(element: ElementDef, control: Control, value: String, _force: bool = false) -> void:
		if control is OptionButton and not element.items.is_empty():
			(control as OptionButton).select(index_of(element, value))


	func validate_value(element: ElementDef, value: String) -> String:
		if element.items.is_empty():
			return ""
		var legal := element.option_values()
		if legal.has(value):
			return ""
		return "字段 %s 没有取值 `%s`（合法值：%s）" % [element.id, value, ", ".join(legal)]

	func default_value(element: ElementDef) -> Variant:
		if element.items.is_empty():
			return null
		return element.items[index_of(element, "")].value_or_text()

	## 导出值 → 候选项下标；认不出来时回落到 default（建控件与回填共用这一份）。
	func index_of(element: ElementDef, value: String) -> int:
		var fallback := clampi(element.default_index, 0, maxi(element.items.size() - 1, 0))
		if value == "":
			return fallback
		for i in element.items.size():
			if element.items[i].value_or_text() == value:
				return i
		return fallback


## 开关按钮：按下/松开各有自己的可见性规则，导出模板也可按状态切换。
class ToggleBuilder extends FieldBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		var button := Button.new()
		button.text = element.text
		button.toggle_mode = true
		host.style_button(button)
		apply_value(element, button, String(host.field_value(element.id, "false")))
		if host.is_preview():
			button.disabled = true
		else:
			button.toggled.connect(func(pressed: bool) -> void:
				host.commit_field(element.id, "true" if pressed else "false", false)
				host.refresh_visibility())
		return button

	func apply_value(_element: ElementDef, control: Control, value: String, _force: bool = false) -> void:
		if control is BaseButton:
			(control as BaseButton).set_pressed_no_signal(value == "true")


	func validate_value(element: ElementDef, value: String) -> String:
		if value == "true" or value == "false":
			return ""
		return "开关 %s 只能与 true / false 比较（实际 `%s`）" % [element.id, value]

	func default_value(element: ElementDef) -> Variant:
		return element.default_value if element.default_value != "" else "false"


class SelectorBuilder extends FieldBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var edit := ElementBuilders.make_edit(element, host, 72.0)
		box.add_child(edit)
		box.set_meta(&"value_control", edit)
		var pick := Button.new()
		pick.text = "▾"
		pick.custom_minimum_size = Vector2(26, 0)
		host.style_button(pick)
		box.add_child(pick)
		if host.is_preview():
			pick.disabled = true
		else:
			pick.pressed.connect(func() -> void:
				host.request_picker(element, box))
		return box


## 子槽位：只建一个占位控件；槽里的块是画布的直接子级，占位尺寸由布局求解灌入。
class NestBuilder extends ElementBuilder:
	func build(_element: ElementDef, _host: Object) -> Control:
		var placeholder := Control.new()
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return placeholder

	func is_slot() -> bool:
		return true


## 块引用（Jump 的目标）：不是文本框，而是「锁定到了哪一块」的按钮；拖拽锁定见 [LinkController]。
class JumpTargetBuilder extends FieldBuilder:
	const MIN_WIDTH: float = 84.0

	func build(element: ElementDef, host: Object) -> Control:
		var button := Button.new()
		button.custom_minimum_size = Vector2(MIN_WIDTH, 0)
		host.style_button(button)
		# apply_value 拿不到宿主，把宿主挂在控件上（与 Selector 的 value_control 同一手法）
		button.set_meta(&"link_host", host)
		apply_value(element, button, String(host.field_value(element.id, "")))
		if host.is_preview():
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
		else:
			button.button_down.connect(func() -> void:
				host.request_link(element, button))
		return button

	func apply_value(element: ElementDef, control: Control, value: String, _force: bool = false) -> void:
		if not (control is Button):
			return
		var host: Object = control.get_meta(&"link_host", null)
		var label := "未锁定"
		if host != null:
			label = String(host.reference_label(element.id))
		(control as Button).text = label
