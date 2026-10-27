class_name UiStyle
extends RefCounted

## UI 深色配色与 StyleBox 的单一来源。
## 主主题只覆盖了 Button/Label/MenuBar/PopupMenu/TabContainer/Tree/ScrollBar，
## PanelContainer/LineEdit/HSlider/CheckButton 会顶引擎默认皮肤 —— 这里统一兜底。
## 改色时只改这一处，各窗口与选择器面板自动同步。

#region 调色板

const PANEL_BG: Color = Color(0.207843, 0.180392, 0.25098, 1.0)         # #35304A
const BAR_BG: Color = Color(0.258824, 0.223529, 0.309804, 1.0)          # #423956
const BORDER: Color = Color(0.101961, 0.086275, 0.121569, 1.0)         # #1A161F
const EDIT_BG: Color = Color(0.212113, 0.181757, 0.255897, 1.0)
const EDIT_FOCUS_BORDER: Color = Color(0.398337, 0.3869, 0.73, 1.0)
const SLIDER_TRACK: Color = Color(0.149020, 0.125490, 0.180392, 1.0)
const SLIDER_FILL: Color = EDIT_FOCUS_BORDER
const TOGGLE_NORMAL_BG: Color = Color(0, 0, 0, 0.258824)
const TOGGLE_HOVER_BG: Color = Color(1, 1, 1, 0.552941)
const TOGGLE_PRESSED_BG: Color = Color(1, 1, 1, 0.258824)
const CELL_NORMAL_BG: Color = EDIT_BG
const CELL_HOVER_BG: Color = BAR_BG
const CELL_PRESSED_BG: Color = Color(0.309804, 0.270588, 0.368627, 1.0)
const BAR_TOP_BORDER: Color = Color(0, 0, 0, 0.419608)

#endregion

#region StyleBox 构造

## 统一起手：背景 + 可选边框 + 可选圆角，content_margin 留给调用方按用途调。
static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0,
		radius: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if border_width > 0:
		style.set_border_width_all(border_width)
		style.border_color = border
	if radius > 0:
		style.set_corner_radius_all(radius)
	return style

#endregion

#region 面板与窗口样式

## 窗口 / 浮层的主面板：深色底 + 暗边框 + 阴影，子控件紧贴边框。
static func panel_style() -> StyleBoxFlat:
	var style := box(PANEL_BG, BORDER, 2)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	style.set_content_margin_all(0.0)
	return style

## 标题条：深色底 + 顶部暗分隔线。
static func bar_style() -> StyleBoxFlat:
	var style := box(BAR_BG)
	style.border_width_top = 5
	style.border_color = BAR_TOP_BORDER
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 4.0
	return style

#endregion

#region 输入控件样式

## LineEdit 普通态：深色底 + 暗边框 + 小圆角。
static func edit_style(focused: bool) -> StyleBoxFlat:
	var style := box(EDIT_BG, EDIT_FOCUS_BORDER if focused else BORDER, 2, 2)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style

## HSlider 轨道。
static func slider_track_style() -> StyleBoxFlat:
	var style := box(SLIDER_TRACK)
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style

## HSlider 填充区。
static func slider_fill_style() -> StyleBoxFlat:
	var style := box(SLIDER_FILL)
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style

## CheckButton 三态。
static func toggle_style(pressed: bool, hovered: bool = false) -> StyleBoxFlat:
	var bg := TOGGLE_PRESSED_BG if pressed else (TOGGLE_HOVER_BG if hovered else TOGGLE_NORMAL_BG)
	var style := box(bg)
	style.content_margin_left = 5.0
	style.content_margin_top = 5.0
	style.content_margin_right = 5.0
	style.content_margin_bottom = 5.0
	return style

#endregion

#region 选择器面板专用

## 格子三态样式（主题里 Button 的 content margin 高达 30，会把 40px 格子撑成 115px）。
static func cell_style(state: StringName) -> StyleBoxFlat:
	var bg := CELL_PRESSED_BG if state == &"pressed" else (
		CELL_HOVER_BG if state == &"hover" else CELL_NORMAL_BG)
	var style := box(bg, BORDER, 2)
	style.set_content_margin_all(4.0)
	return style

#endregion


#region 公告条目

## 公告条目面板：比主面板暗的底 + 亮边框 + 大留白（与主面板区分）。
static func notice_item_style() -> StyleBoxFlat:
	var style := box(Color(0.17598, 0.1533, 0.21, 1.0), Color(0.25792, 0.2232, 0.31, 1.0), 5)
	style.content_margin_left = 15.0
	style.content_margin_top = 15.0
	style.content_margin_right = 15.0
	style.content_margin_bottom = 15.0
	return style

#endregion
