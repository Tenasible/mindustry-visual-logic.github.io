class_name SelectorPanel
extends Control

## 内容选择弹窗：候选项的图标网格（块定义里写 `<Selector kind="units" />`）。
##
## 铺满父级的浮层（遮罩点击即关，弹窗期间点不到画布）+ 居中面板，Esc 也关；带搜索框，边打边筛、回车选第一个。

signal picked(value: String)

const CELL_SIZE: Vector2 = Vector2(40, 40)
const COLUMNS: int = 7
const PANEL_SIZE: Vector2 = Vector2(344, 384)
const GRID_HEIGHT: float = 236.0

const COLOR_BACKDROP: Color = Color(0.0, 0.0, 0.0, 0.45)
## kind → 标题的翻译键（认不出就用 kind 本身）。
const TITLES: Dictionary[StringName, String] = {
	&"units": "SELECTOR_TITLE_UNITS",
	&"blocks": "SELECTOR_TITLE_BLOCKS",
	&"items": "SELECTOR_TITLE_ITEMS",
	&"liquids": "SELECTOR_TITLE_LIQUIDS",
	&"sensors": "SELECTOR_TITLE_SENSORS",
}

var _backdrop: ColorRect
var _panel: PanelContainer
var _title: Label
var _search: LineEdit
var _groups_bar: HBoxContainer
var _grid: GridContainer
var _count: Label
var _element: ElementDef = null

## 当前 kind 的分组（无分组时为空）；正在看的分组名（空 = 全部）。
var _groups: Dictionary = {}
var _group: StringName = &""
var _icon_cache: Dictionary[String, Texture2D] = {}
## 建好的格子：[{value, group, button}]，按数据顺序一次建齐，筛选只改 visible。
var _cells: Array[Dictionary] = []
## 当前搜索关键词：由 text_changed 带进来（不读控件，原因见 _ready）。
var _keyword: String = ""


func _ready() -> void:
	# 整层铺满父级：遮罩要盖住整个编辑器区域，面板在中间
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 200

	_backdrop = ColorRect.new()
	_backdrop.color = COLOR_BACKDROP
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.add_theme_stylebox_override("panel", UiStyle.panel_style())
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	# 顶部标题条（与设置窗/公告窗同一套）。
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.bar_style())
	box.add_child(bar)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	bar.add_child(_title)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 10)
	body_margin.add_theme_constant_override("margin_right", 10)
	body_margin.add_theme_constant_override("margin_bottom", 8)
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body_margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_child(body)

	_search = LineEdit.new()
	_search.placeholder_text = "SELECTOR_SEARCH"
	_search.clear_button_enabled = true
	# 主主题没有 LineEdit 条目，不自己带样式就会顶着引擎默认的浅色皮肤
	_search.add_theme_stylebox_override("normal", UiStyle.edit_style(false))
	_search.add_theme_stylebox_override("focus", UiStyle.edit_style(true))
	var font := load("res://assets/fonts/font.woff") as Font
	if font != null:
		_search.add_theme_font_override("font", font)
	# 用信号带过来的文本，不要去读 _search.text —— 回调比控件自身更新早一步，读到的是旧值
	_search.text_changed.connect(func(text: String) -> void:
		_keyword = text
		_refill())
	_search.text_submitted.connect(func(_text: String) -> void: _pick_first())
	body.add_child(_search)

	_groups_bar = HBoxContainer.new()
	_groups_bar.add_theme_constant_override("separation", 4)
	body.add_child(_groups_bar)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, GRID_HEIGHT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 11)
	body.add_child(_count)

	resized.connect(_recenter)
	# 面板尺寸可能因内容变化（字体/滚动条），居中要跟着走
	_panel.resized.connect(_recenter)



## 居中打开弹窗。
func open(element: ElementDef) -> void:
	if element == null or not SelectorData.exists(element.selector_kind):
		push_warning("没有选择器数据：%s（kind=%s）" % [
			element.id if element != null else "?",
			element.selector_kind if element != null else "?"])
		return
	_element = element
	_groups = SelectorData.groups(element.selector_kind)
	_group = &""
	_title.text = "%s · %s" % [tr(TITLES.get(element.selector_kind, String(element.selector_kind))), element.id]
	_keyword = ""
	_search.text = ""
	_build_groups()
	_build_cells()
	_refill()
	visible = true
	call_deferred("_fit_and_center")
	# 打开就能直接打字过滤；Esc 关掉由 _unhandled_key_input 兜
	_search.grab_focus()


func close() -> void:
	visible = false
	_element = null
	_group = &""


func is_open() -> bool:
	return visible


## 面板居中：父级矩形中心减去自身一半；父级比面板小就贴左上角，别跑出可视区。
func _recenter() -> void:
	if not PlacementPreview.is_valid_object(_panel):
		return
	var span := size - _panel.size
	_panel.position = Vector2(maxf(span.x * 0.5, 0.0), maxf(span.y * 0.5, 0.0))


## 按内容重新定尺寸再居中：Control 只会变大不会自己缩回，最小尺寸又要等一帧，所以 deferred。
func _fit_and_center() -> void:
	if not PlacementPreview.is_valid_object(_panel):
		return
	_panel.reset_size()
	_panel.size = Vector2(
		minf(_panel.size.x, maxf(size.x - 24.0, 200.0)),
		minf(_panel.size.y, maxf(size.y - 24.0, 200.0)))
	_recenter()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## 分组按钮：全部 + 数据里的各组（没有分组数据时整条不显示）。
func _build_groups() -> void:
	for child in _groups_bar.get_children():
		PlacementPreview.dismiss(child)
	_groups_bar.visible = not _groups.is_empty()
	if _groups.is_empty():
		return
	_add_group_button("", tr("SELECTOR_ALL"))
	for group_name in _groups:
		_add_group_button(StringName(group_name), String(group_name))


func _add_group_button(id: StringName, text: String) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_group = id
		_refill()
		_search.grab_focus())
	_groups_bar.add_child(button)


## 建格子：一次建齐，筛选只改 visible（每敲一个字重建几百个按钮太贵）。
func _build_cells() -> void:
	for child in _grid.get_children():
		# 先摘掉再 free：queue_free 到帧末才生效，那一帧里旧按钮还可能被回车选中
		PlacementPreview.dismiss(child)
	_cells.clear()
	# 分组数据在 open() 里已经取过一次（_groups），这里直接用 —— 数据源只读一处
	if _groups.is_empty():
		for entry in SelectorData.options(_element.selector_kind):
			_add_cell(entry, &"")
	else:
		for group_name in _groups:
			for entry in _groups[group_name]:
				_add_cell(entry, StringName(group_name))


func _add_cell(entry: Variant, group: StringName) -> void:
	if not (entry is Dictionary):
		return
	var value := String((entry as Dictionary).get("value", ""))
	var button := _make_cell(value, String((entry as Dictionary).get("icon", "")))
	_grid.add_child(button)
	_cells.append({"value": value, "group": group, "button": button})


## 按「当前分组 + 搜索关键词」重排网格：只切可见性与顺序，不重建控件。
func _refill() -> void:
	if _element == null:
		return
	# 关键词以控件为准：程序化改 text（清空按钮）不一定走 text_changed
	if _keyword != _search.text:
		_keyword = _search.text
	var keyword := _keyword.strip_edges().to_lower()
	# 命中往前排（打 router 要先看到 @router）。
	var first: Array = []
	var rest: Array = []
	var shown := 0
	var total := 0
	for cell in _cells:
		if _group != &"" and StringName(cell["group"]) != _group:
			(cell["button"] as Button).visible = false
			continue
		total += 1
		var value: String = cell["value"]
		var hit := keyword == "" or _matches(value, keyword)
		(cell["button"] as Button).visible = hit
		if not hit:
			continue
		shown += 1
		if keyword == "" or _starts_with(value, keyword):
			first.append(cell)
		else:
			rest.append(cell)
	# 把排好序的可见格子挪到前面（隐藏的不占布局，位置无所谓）。
	var index := 0
	for cell in first + rest:
		_grid.move_child(cell["button"], index)
		index += 1
	_count.text = tr("SELECTOR_COUNT") % total if shown == total else tr("SELECTOR_COUNT_FILTERED") % [total, shown]


## 关键词匹配：`c` / `copper` / `@copper` 都能搜到 `@copper`。
## 只打一个 `@` 要列全部候选（[b]第一个分支不能删[/b]）：trim_prefix("@") 后 needle 是空串，contains 恒假。
func _matches(value: String, keyword: String) -> bool:
	var haystack := value.to_lower()
	return haystack.contains(keyword) or haystack.trim_prefix("@").contains(keyword.trim_prefix("@"))


## 名字（去掉 @）以关键词开头 —— 这种命中排最前。
func _starts_with(value: String, keyword: String) -> bool:
	return value.to_lower().trim_prefix("@").begins_with(keyword.trim_prefix("@"))


func _make_cell(value: String, icon_path: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CELL_SIZE
	button.tooltip_text = value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", UiStyle.cell_style(&"normal"))
	button.add_theme_stylebox_override("hover", UiStyle.cell_style(&"hover"))
	button.add_theme_stylebox_override("pressed", UiStyle.cell_style(&"pressed"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var texture := _texture_of(icon_path)
	if texture != null:
		button.icon = texture
		button.expand_icon = true
	else:
		# 没图标的候选退回显示短名字（全名在悬停提示里），免得长名字把整排格子撑宽
		var label := value.trim_prefix("@")
		button.text = label if label.length() <= 7 else label.substr(0, 6) + "…"
		button.add_theme_font_size_override("font_size", 10)
	button.pressed.connect(func() -> void: picked.emit(value))
	return button


func _pick_first() -> void:
	# 在有效格子里取网格顺序最靠前的（_refill 已把命中项排到前面）
	var best: Button = null
	var best_index := 1 << 30
	for cell in _cells:
		var button: Button = cell["button"]
		if not PlacementPreview.is_valid_object(button) or not button.visible:
			continue
		if button.get_index() < best_index:
			best_index = button.get_index()
			best = button
	if best != null:
		picked.emit(best.tooltip_text)


func _texture_of(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_icon_cache[path] = texture
	return texture
