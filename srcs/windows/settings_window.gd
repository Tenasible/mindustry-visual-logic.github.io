class_name SettingsWindow
extends Window

## 设置窗口：帧率上限 / UI 缩放 / 语言 / 失焦时自动导出。
## 只做「值 ↔ 控件」，应用是 [Main] 的事；改动即时生效，关闭窗口时才写盘。

signal changed()
signal closed()

@onready var nMaxFpsSlider: HSlider = %MaxFpsSlider
## 用 LineEdit 而不是 SpinBox：后者的样式长在内部控件上，主题覆盖不到。
@onready var nMaxFpsEdit: LineEdit = %MaxFpsEdit
@onready var nUiScaleSlider: HSlider = %UiScaleSlider
@onready var nUiScaleEdit: LineEdit = %UiScaleEdit
@onready var nLanguageOption: OptionButton = %LanguageOption
@onready var nExportToggle: CheckButton = %ExportOnFocusLost

var settings: AppSettings = null

## 正在「数据 → 控件」地铺值：此时控件发出的 value_changed 不该再写回数据（否则打转）。
var _loading: bool = false


## 打开窗口：每次都从数据重新铺一遍，避免上次没保存的残留值留在控件上。
func open() -> void:
	if settings != null:
		_show_values(settings)
	popup_centered()


func _ready() -> void:
	nLanguageOption.item_selected.connect(_on_language_selected)
	_apply_styles()

func setup(p_settings: AppSettings) -> void:
	settings = p_settings
	_show_values(settings)


## 语言变了（应用在 [Main]）：把下拉框的选项文本也重取一遍（“跟随系统”那句要翻译）。
func refresh_language() -> void:
	_show_values(settings)


func _show_values(data: AppSettings) -> void:
	if data == null:
		return
	_loading = true
	nMaxFpsSlider.value = data.max_fps
	nMaxFpsEdit.text = str(data.max_fps)
	nUiScaleSlider.value = data.ui_scale
	nUiScaleEdit.text = "%.2f" % data.ui_scale
	_fill_language_options()
	nLanguageOption.select(AppSettings.LANGUAGES.find(data.language))
	nExportToggle.button_pressed = data.export_on_focus_lost
	_loading = false


## 语言下拉框：语言名用它自己的语言写，只有「跟随系统」要翻译。
func _fill_language_options() -> void:
	nLanguageOption.clear()
	for code in AppSettings.LANGUAGES:
		var label := tr("LANGUAGE_SYSTEM") if code == AppSettings.LANGUAGE_SYSTEM else (
			"简体中文" if code == AppSettings.LANGUAGE_ZH else "English")
		nLanguageOption.add_item(label)


#region 控件回调

func _on_max_fps_changed(value: float) -> void:
	_apply_number(value, AppSettings.MIN_MAX_FPS, AppSettings.MAX_MAX_FPS, _set_max_fps)


func _on_ui_scale_changed(value: float) -> void:
	_apply_number(value, AppSettings.MIN_UI_SCALE, AppSettings.MAX_UI_SCALE, _set_ui_scale)


## 输入框提交（回车或失焦）：认不出的值就退回当前值，不做“猜你想要”。
func _on_max_fps_submitted(_text: String = "") -> void:
	if settings != null:
		_apply_number(_number_in(nMaxFpsEdit, settings.max_fps),
			AppSettings.MIN_MAX_FPS, AppSettings.MAX_MAX_FPS, _set_max_fps)


func _on_ui_scale_submitted(_text: String = "") -> void:
	if settings != null:
		_apply_number(_number_in(nUiScaleEdit, settings.ui_scale),
			AppSettings.MIN_UI_SCALE, AppSettings.MAX_UI_SCALE, _set_ui_scale)


## 数值改动的统一出口：钳进范围 → 写回数据 → 回填控件 → 通知外壳。
func _apply_number(value: float, minimum: float, maximum: float, setter: Callable) -> void:
	if _loading or settings == null:
		return
	setter.call(clampf(value, minimum, maximum))
	_show_values(settings)
	changed.emit()


static func _number_in(edit: LineEdit, fallback: float) -> float:
	var text := edit.text.strip_edges()
	return text.to_float() if text.is_valid_float() else fallback


func _set_max_fps(value: float) -> void:
	settings.max_fps = int(roundf(value))


func _set_ui_scale(value: float) -> void:
	settings.ui_scale = value


func _on_language_selected(index: int) -> void:
	if _loading or settings == null or index < 0 or index >= AppSettings.LANGUAGES.size():
		return
	settings.language = AppSettings.LANGUAGES[index]
	_show_values(settings)
	changed.emit()


func _on_export_toggled(pressed: bool) -> void:
	if _loading or settings == null:
		return
	settings.export_on_focus_lost = pressed
	changed.emit()


func _on_defaults_pressed() -> void:
	if settings == null:
		return
	settings.reset_to_defaults()
	_show_values(settings)
	changed.emit()


func _on_close_pressed() -> void:
	hide()
	closed.emit()

#endregion


## 样式统一由 [UiStyle] 提供（场景里不再内联 StyleBox）。
func _apply_styles() -> void:
	var panel := get_node_or_null("Panel")
	if panel is PanelContainer:
		panel.add_theme_stylebox_override("panel", UiStyle.panel_style())
	var bottom := get_node_or_null("Panel/Layout/BottomBar")
	if bottom is PanelContainer:
		bottom.add_theme_stylebox_override("panel", UiStyle.bar_style())
	for edit in [nMaxFpsEdit, nUiScaleEdit]:
		edit.add_theme_stylebox_override("normal", UiStyle.edit_style(false))
		edit.add_theme_stylebox_override("focus", UiStyle.edit_style(true))
	for slider in [nMaxFpsSlider, nUiScaleSlider]:
		slider.add_theme_stylebox_override("slider", UiStyle.slider_track_style())
		slider.add_theme_stylebox_override("grabber_area", UiStyle.slider_fill_style())
		slider.add_theme_stylebox_override("grabber_area_highlight", UiStyle.slider_fill_style())
	for toggle in [nLanguageOption, nExportToggle]:
		toggle.add_theme_stylebox_override("normal", UiStyle.toggle_style(false))
		toggle.add_theme_stylebox_override("hover", UiStyle.toggle_style(false, true))
		toggle.add_theme_stylebox_override("pressed", UiStyle.toggle_style(true))
