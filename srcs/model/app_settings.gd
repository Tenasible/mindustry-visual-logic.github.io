class_name AppSettings
extends RefCounted

## 应用级设置（帧率上限 / UI 缩放 / 语言 / 失焦自动导出）：纯数据 + 一个 JSON 存盘；「谁来应用」是 [Main] 的事。

## 存盘路径（测试可以改成临时目录，避免写真实用户目录）。
static var path: String = "user://settings.json"


const DEFAULT_MAX_FPS: int = 60
const DEFAULT_UI_SCALE: float = 1.0
const MIN_MAX_FPS: int = 10
const MAX_MAX_FPS: int = 400
const MIN_UI_SCALE: float = 0.5
const MAX_UI_SCALE: float = 2.0
## [member language] 的取值：跟随系统 / 英文 / 简体中文（也是 Godot 的 locale 名）。
const LANGUAGE_SYSTEM: String = "system"
const LANGUAGE_EN: String = "en"
const LANGUAGE_ZH: String = "zh_CN"
const LANGUAGES: PackedStringArray = [LANGUAGE_SYSTEM, LANGUAGE_EN, LANGUAGE_ZH]

## 帧率上限：刻意不给 0（不限）—— 那会把编辑器拖到不可用。
var max_fps: int = DEFAULT_MAX_FPS
var ui_scale: float = DEFAULT_UI_SCALE
## 界面语言：[constant LANGUAGE_SYSTEM] 或某个 locale 名（
## [constant LANGUAGES] 里的字符串就是设置窗口下拉框的取值）。
var language: String = LANGUAGE_SYSTEM
## 窗口失焦（切到别的应用）时把当前页的 mlog 丢进剪贴板（默认开；空程序不动剪贴板）。
var export_on_focus_lost: bool = true


## 从磁盘读设置；文件不存在或读不动时返回一份默认值（不会失败）。
static func load_from_disk() -> AppSettings:
	var settings := AppSettings.new()
	if not FileAccess.file_exists(path):
		return settings
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return settings
	var text := file.get_as_text()
	file.close()
	return from_json(text)


func save_to_disk() -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json())
	file.close()
	return OK


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


func to_dict() -> Dictionary:
	return {
		"max_fps": max_fps,
		"ui_scale": ui_scale,
		"language": language,
		"export_on_focus_lost": export_on_focus_lost,
	}


## 解析（容错）：认不出的字段用默认值，超范围的钳回范围内。
static func from_json(text: String) -> AppSettings:
	var settings := AppSettings.new()
	# 用 JSON.parse() 而不是 parse_string()：后者失败会在控制台报引擎错误
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return settings
	var data: Dictionary = json.data
	settings.max_fps = clampi(int(data.get("max_fps", DEFAULT_MAX_FPS)), MIN_MAX_FPS, MAX_MAX_FPS)
	settings.ui_scale = clampf(float(data.get("ui_scale", DEFAULT_UI_SCALE)), MIN_UI_SCALE, MAX_UI_SCALE)
	settings.export_on_focus_lost = bool(data.get("export_on_focus_lost", true))
	var language := String(data.get("language", LANGUAGE_SYSTEM))
	settings.language = language if LANGUAGES.has(language) else LANGUAGE_SYSTEM
	return settings


func reset_to_defaults() -> void:
	max_fps = DEFAULT_MAX_FPS
	ui_scale = DEFAULT_UI_SCALE
	export_on_focus_lost = true
	language = LANGUAGE_SYSTEM


## 当前该用哪个 locale：跟随系统时把 zh* 归到 zh_CN、其余归到 en（只提供这两套翻译）。
func active_locale() -> String:
	if language != LANGUAGE_SYSTEM:
		return language
	return LANGUAGE_ZH if OS.get_locale().begins_with("zh") else LANGUAGE_EN
