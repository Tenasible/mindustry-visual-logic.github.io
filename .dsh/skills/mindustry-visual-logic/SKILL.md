---
name: mindustry-visual-logic
description: 在本仓库（Mindustry 可视化逻辑编辑器 MVL，Godot 4.7 工程）中可靠地驱动 Godot：定位/暂存引擎、导入资源、运行抓日志、校验警告错误，以及常见的工程事实与避坑指南。当任务涉及启动运行、检查脚本警告/报错、导入导出或验证修改后的场景时使用本技能。
---

# Mindustry Visual Logic (MVL) Godot 工程操作指南

本仓库是 Mindustry（像素工厂）可视化逻辑编辑器 MVL 的 Godot 工程（engine 4.7，GL Compatibility，主场景 `res://Scenes/main.tscn`，应用名 `MVL_可视化逻辑编辑`，版本 0.2.0）。下面是经实测验证的可靠驱动方式，任何需要“跑一下项目/看警告/验修改”的操作都应走这些脚本，而不是手写临时的启动命令。

## 机器事实

- Godot 控制台版可用于捕获 stdout/stderr；若只有主程序（GUI 版）或控制台版缺少同级主程序，先跑 `tools/dsh/godot-common.ps1` 的暂存逻辑（`Get-MvlGodotConsole`），它会把主程序与控制台版成对复制到 `%TEMP%\godotrun_mvl\`。
- 已知可用引擎：
  - `C:\Users\ASUS\Desktop\Godot_v4.7.2-stable_win64.exe`（完整主程序）
  - `C:\Users\ASUS\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（控制台版，198KB，需要同目录有主程序才能运行）
- 工程目录：`<仓库根>` 即含 `project.godot` 的目录；本仓库就是 `.git` 根。

## 可靠命令（首选封装脚本，Windows PowerShell 5.1 兼容）

所有脚本在 `<仓库根>\tools\dsh\`，用法：

```powershell
# 1) 运行游戏 N 帧并抓取完整控制台输出（默认 600 帧），日志写到 %TEMP%\MVL_DSH\
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dsh\godot-run.ps1 -Frames 600

# 2) 导入资源 + 运行 + 统计 WARNING/ERROR（改场景/脚本后先跑这个）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dsh\godot-verify.ps1 -Frames 300

# 3) 仅导入
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dsh\godot-import.ps1
```

- 脚本自带：引擎定位/暂存、把 `APPDATA` 重定向到临时目录（避免污染用户真实 `user://` 配置、也兼容受限环境）、日志落盘与“ERROR/WARNING 行数 + 片段”汇总。
- 退出码：引擎正常退出为 0；脚本自身把引擎退出码透传，另以 `$LASTEXITCODE` 可判。

## 如何阅读运行日志与判定“干净”

- 运行日志在 `%TEMP%\MVL_DSH\`（例如 `run-*.log`）。汇总输出会打印 `ERROR lines / WARNING lines` 计数与匹配行首部。
- 项目自身“启动干净”的标准：
  - 无 `SCRIPT ERROR` / `Parse JSON failed` / `Invalid call ... base 'Nil'`；
  - 无 `W` 前缀的 GDScript 编译警告（`GDScript::reload ... UNUSED_*` 等）——这类警告只在 Godot 编辑器按 ▶ 运行时于 Output 面板出现，直接跑控制台版看不到；静态审计可用“函数头到下一个函数头”的片段做参数使用检查，未用参数应加 `_` 前缀。
- 已知无害噪音（勿误判为项目问题）：
  - 退出时的 `RID allocations ... leaked at exit` + 若干 `Texture with GL ID ... leaked` + `RenderingServer::get_singleton() is null`：这是 main 里 7 个自定义鼠标光标纹理在引擎关闭阶段的内部释放提示，与代码无关。
  - 本机无外网/证书库受限时，公告 HTTP 请求（`Scenes/notice_window.tscn` 访问 `https://textdb.online/MindVisualLogic`）会失败；代码已静默处理（JSON 实例解析 + 非 Dictionary 直接 return），不会崩、不刷错误。
- 历史修复速查：`notice_window` 曾对 `JSON.parse_string` 的 null 调用 `has` 崩溃（已修：解析失败/非对象直接返回）；全项目 27 处未使用参数已加 `_` 前缀（`UNUSED_PARAMETER`）。

## 编辑器侧对接

仓库带有 Godot 编辑器插件 `res://addons/deepseek_harness/`（在编辑器底部左侧 Dock “DeepSeek Harness 对接”）：可一键“运行项目并抓取日志 / 导入并校验 / 查看最新日志 / 打开 DeepSeek Harness 页面”。它通过 `powershell.exe` 调用本目录脚本，不依赖 DSH 进程常驻，断开也可用；删除该 addons 目录并清掉 `project.godot` 的 `[editor_plugins]` 即可卸载。

## 常规开发工作流建议

1. 改 GDScript / 场景后：跑 `godot-verify.ps1`，确认 ERROR/WARNING 计数不高于改动前基线（当前干净基线 ≈ 0 项目内 WARNING/ERROR；退出纹理噪音不计）。
2. 涉及新增积木（`Blocks/` 下某类 `.tscn`）时：新场景 `extends LogicBlocks`，实现 `compile()`（返回带 `\n` 的 Mindustry 指令行）与 `load_value()`，并在 `Scenes/editor.tscn` 的 `place_blocks()` 与剪贴板映射字典里登记。
3. 需要视觉/手动验证时：在 Godot 编辑器打开工程按 F5；行号、Jump 跳线等交互都在编辑器内调试。

## 工程文件（保存/打开，与剪贴板不同）

- 菜单「文件 ▸ 保存 / 另存为 / 打开工程文件」，格式为 JSON `.mvlp`（详见 `Scripts/project_io.gd`，类 `ProjectIO`）。
- 与剪贴板导出/导入的区别：文件保存的是**编辑态**（积木顺序=行号、每块控件状态、Jump 用目标 `label_value` 作锚点），不经 `compile()` 转译：
  - Jump 跳线在加载后**按锚点重连**并修正行号显示，插入/合并导致行号变化指向依然正确；
  - 剪贴板往返会丢失的状态（print/format 引号开关、draw 的第 7 参数、configure 动态行等）在文件中保留。
- 关键 API：`ProjectIO.capture_project(%UserBlocks)` / `apply_project(container, data, easyInput)` / `save_to_file` / `load_from_file`；编辑器页有 `save_project_file(path)` / `load_project_file(path)` 与 `project_path`。
- 回环测试（改序列化后必跑）：
  ```
  godot --headless --editor --path . --quit-after 600   # 先刷新全局类缓存（新增 class_name 后必需）
  godot --headless --path . res://tests/roundtrip.tscn --quit-after 8000
  ```
  输出 `ROUNDTRIP PASS` 且退出码 0 即通过（覆盖：顺序/标签/控件状态、draw 全字段、print 引号开关、configure 多行重建、Jump 锚点重连、文件往返）。

## 拖拽/落位（Pick & Drop）实现要点

- 判定与几何全部收敛到 `Scripts/block_drag.gd`（`BlockDrag`）：
  - `find_insert_slot(container, mouse_y, ignore) -> int`：纯函数，按“竖直中心在鼠标上方的子块计数”求插入槽位（0..n），单调稳定，不随占位符高度震荡；
  - `find_nearest_block(...)`：供 Jump 拖箭头选目标（自动排除自身）；
  - `logic_blocks.gd`（基类）与 `block_shell`、`jump` 三处复用同一套判定，避免口径漂移。
- 交互模型（保留）：拿起 → `Dragging` 层跟随鼠标 + 容器内占位阴影预览 → 松开按预览槽位落位。
- 占位预览优化：`logic_blocks._update_shadow_preview()` 只在目标槽位变化时才 `move_child` 占位符，不再每帧全量扫描+重排。
- 松手收敛为 `commit_drop()`（基类）单一入口：删除区（x < origin.x-100，半透明提示）→ 取消销毁；否则按“占位符索引==预览槽位”落位，随后显式调用容器 `_on_block_moved()` 刷新行号/跳线（不再依赖 sort_children 隐式触发）。
- 拖拽相关自动化验证：
  ```
  godot --headless --path . res://tests/dragtest.tscn --quit-after 8000
  ```
  输出 `DRAGTEST PASS`（覆盖槽位单调性/端点/空容器、最近块与排除自身、commit 落位顺序、删除区销毁、block_shell/jump 脚本可加载）。
- “拖进 C 形身体”的两个端到端窗口化探针（真实 editor.tscn + if.tscn，全输入管线驱动）：
  ```
  godot --path . res://tests/dragbody.tscn --quit-after 20000   # 工作区抓取 -> 悬停身体
  godot --path . res://tests/dragpal.tscn  --quit-after 25000   # 积木栏拿起副本 -> 拖入身体
  ```
  均需窗口模式（headless 下 warp_mouse 无效）；输出 `DRAGBODY PASS` / `DRAGPAL PASS`。dragpal 会先在积木表面找“由根节点接收鼠标”的按下点（内部 STOP 控件会消费按下）。

## 框选 / 批量拖动 / 通用“选择”模型

- **通用模型 `Scripts/block_selection.gd`（`BlockSelection`）**：与容器/UI 解耦的多选模型——
  `select_only/add/remove/toggle/clear/select_range/set_many/is_selected/get_selected` + `changed` 信号。
  后续任何列表式多选（图层/文件列表等）均可直接复用。
- **控制器 `Scripts/editor_selection.gd`（编辑器页 `SelectionHost` 子节点）**：
  - 工程区空白处按住左键拖动 → 框选（矩形实时命中 `BlockDrag.blocks_in_rect`）；
  - 点击空白 → 清空选择；`shift` 点击 → 范围选择；`ctrl` 点击 → 切换；
  - **点击 vs 拖动（单块）**：按下时**不立即选中**，`_track_pending()` 跟踪到 LogicBlocks
    手势结束（`moving` 置 false）后按位移判定——位移 < `CLICK_MAX_MOVE`(6px) = 原地点击
    → `select_only`；位移 ≥ 6px = 真拖动 → `clear()`（**拖动放下不残留选中**，曾因按下即
    `select_only` 破坏手感）。空闲帧顺带 `selection.prune_valid()` 清理被销毁积木的残留引用；
  - 普通点击未选积木 → 单选并进入原单块拖动（`editor_on_block_press` 返回 false 交还 LogicBlocks）；
  - 点击已选积木且多选 → **整组拖动**：组占位预览（槽位变化才重排）→ 松手按 `BlockDrag.insert_run` 保序落位，或拖到删除区整组删除；
  - 失焦/窗口外松手有兜底（按钮已松开即结束动作）。
- **绘制层 `Scripts/selection_overlay.gd`（`SelectionOverlay`）**：只画高亮框与框选矩形，不做输入。
- **`BlockDrag` 泛化**：`find_insert_slot/find_nearest_block` 的 `ignore` 支持“节点或节点数组”；
  新增 `insert_run`（整组保序插入）与 `blocks_in_rect`。
- 交互钩子：`LogicBlocks._on_gui_input` 按下时沿父链查找带 `editor_on_block_press` 的节点询问；
  编辑器根节点把请求转发给 `SelectionHost`。
- 手动体验：Godot 编辑器打开工程，在右侧积木区空白拖拽框选、shift/ctrl 组合、拖已选积木组移动。

## C 形积木（嵌套容器）与扁平化导出

- **基类 `Scripts/cshape_blocks.gd`（`CShapeBlocks`，extends LogicBlocks）**：
  - 身体容器：优先 `%Body`，其次 `%UserBLocks`；身体容器加入组 `mvl_block_hosts`，
    使 LogicBlocks 拖拽可把积木拖入/拖出身体（拖拽目标=鼠标下“面积最小的宿主容器”）。
  - **注册时机必须是 `_enter_tree`（每次进树），不能只在 `_ready`**：`_ready` 一生只触发一次，
    `_exit_tree` 会把身体移出宿主组；C 形积木自己被拖放一次（reparent 进 Dragging 再 commit 回来）
    后 `_ready` 不会重跑 → 身体永久退出宿主组 → 之后拖任何积木到它上面都**完全静默**
    （无 [drop] 也无 [drop?]）。这是 2026-09 实锤的“工作区 If 不接收拖入”根因，
    回归用例 `tests/cshape_dup.tscn`（headless，`CSHAPEDUP PASS`）。
  - 导出钩子：`cshape_header_count/footer_count/header_line(skip_line)/footer_line`，默认 0 行——
    纯分组容器不产生任何代码；`cshape_body_count()` 递归统计身体行数。
- **if 积木 `Blocks/Logics/if.tscn`**：基于 CShapeBlocks。语义=条件成立执行身体，否则跳过；
  导出为一行 `jump <跳过点> <取反比较> a b`（取反表 equal↔notEqual、小于↔大于等于等；`always` 或空身体不产生跳转行）。
- **`Scripts/block_export.gd`（`BlockExport.export_text(container)`）**：扁平化导出。
  第一遍深度优先给每个积木分配**绝对起始行号** map[node] 与结束行 end[node]；
  第二遍生成文本：C 形走 header/body/footer 钩子（header 的 skip_line=end[node]），
  普通块调 compile()；jump 通过基类成员 `export_line_map` 读到全局行号后输出绝对目标。
  编辑器“快捷导出”与“失焦导出”均走此路径（editor.tscn compile）。
- **ProjectIO 嵌套**：工程文件里 C 形块带 `children`（递归保存/恢复身体内子积木）；
  UI 采集会跳过嵌套块子树（每块各自保存）；jump 锚点在整棵树内查找重连。
- 已知限制：C 身体内的 jump 不绘制可视化跳线/不支持跨容器拖箭头（origin 无跳线基础设施时自动隐藏）；
  文件与导出对嵌套均无损（`EXPORTTEST PASS` 覆盖）。
- C 形相关测试：`tests/exporttest.tscn`（嵌套导出行号/取反/always/空身体/嵌套 apply 往返）。
  运行前需先 `godot --headless --editor --path . --quit-after 900` 刷新脚本类缓存。
- 探针输入管线的坑（写新探针时注意）：
  - `Input.parse_input_event` 的合成事件只更新 GUI 悬停/分发；`get_global_mouse_position()` 读的是
    Input/Viewport 的鼠标位置，**必须配合 `Viewport.warp_mouse(画布坐标 × content_scale_factor)`** 同步
    （warp 参数是窗口物理像素）。scale=1 时两者相等。
  - content_scale_factor != 1 时合成事件注入不可靠（悬停查询错乱）——拖放几何全是比例不变判定，
    以 scale=1 探针通过 + 布局等比缩放可推出任意 ui_scale 行为一致；勿在 scale>1 上纠缠注入怪癖。

### 避坑（Godot 4.x）
- `Node.add_child()` 不允许目标已有父节点（报 “already has a parent”），换父一律用 `reparent()`（无父节点才 `add_child`）——`BlockDrag.insert_run` 已按此实现；
- 连接带参信号到回调时，回调参数个数必须 ≥ 信号参数个数，否则每次 emit 刷 “Method expected N argument(s)”；
- 该引擎版本 `Control` 没有 `to_local`/`to_global`，坐标换算用“全局坐标差”实现（见 `editor_selection.gd::_to_local_rect`）。
- **基类解析错误会伪装成下游错误**：若 `logic_blocks.gd`/`cshape_blocks.gd` 编译失败，所有按字符串路径
  extends 它们的积木内嵌脚本会在 (1,1) 报 `Could not resolve class "LogicBlocks"/"CShapeBlocks"`（GUI 指向
  configure.tscn::GDScript_xxx 之类），**不要**先怀疑类缓存/extends 写法——先 `godot --headless --check-only
  --script res://Scripts/logic_blocks.gd` 查基类本身（2026-09 实锤：基类第 251 行 `var n := self` + `n is
  VBoxContainer` 静态不可能被判解析错误，导致 configure/if 全项目启动报错）。
- **遍历父链别用 `:= self`**：静态类型会把 `is <不同分支容器>` 判为解析错误；显式写 `var n: Node = self`。
- 积木内 STOP 子控件（LineEdit/Button/OptionButton）会消费按下事件：从积木的标题/边框/身体空白等
  非交互面按下才会拖起（Label/Container 默认 PASS/IGNORE 不影响）。这是设计行为，排查“拖不起来”时先验证按下点。
- 受限/重定向环境 `user://` 可能不可写：`tests/roundtrip.gd` 已改为写 OS 临时目录（`%TEMP%`）。
