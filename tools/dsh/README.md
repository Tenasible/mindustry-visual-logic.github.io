# tools/dsh — DeepSeek Harness 对接 MVL 工程的驱动脚本

这些脚本把“在本机可靠驱动这个 Godot 工程”固化成命令，供 Harness 代理（以及
Godot 编辑器插件 `res://addons/deepseek_harness/`）调用。全部兼容 Windows PowerShell 5.1。

## 文件

| 脚本 | 作用 |
| --- | --- |
| `godot-common.ps1` | 公共函数：定位/成对暂存 Godot 控制台版、隔离 APPDATA、日志汇总。被其它脚本点源 |
| `godot-run.ps1` | 运行工程 N 帧并抓全量控制台输出到 `%TEMP%\MVL_DSH\run-*.log` |
| `godot-import.ps1` | 无头导入（刷新 `.godot` 缓存） |
| `godot-verify.ps1` | 导入 + 运行 + 汇总 ERROR/WARNING + 判定脚本级错误（一键校验） |

## 用法

```powershell
# 仓库根目录下执行：
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dsh\godot-verify.ps1 -Frames 300
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dsh\godot-run.ps1 -Frames 600
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dsh\godot-import.ps1
```

参数：`-Project <路径>` 可指向其它 Godot 工程；`-Frames N` 控制运行帧数。
可用环境变量 `GODOT_EXE` 直接指定引擎路径（优先于自动查找）。

## ⚠️ 编码注意事项（务必遵守）

这些 `.ps1` 含中文，且目标是 **Windows PowerShell 5.1**：PS 5.1 把“无 BOM 的 UTF-8”
当作 ANSI 读取，会乱码甚至破坏字符串引号导致语法错误。因此文件**必须带 UTF-8 BOM**。
- 用编辑工具/文本编辑器改完后，请确认仍带 BOM；丢了就补：
  ```powershell
  $t = [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
  ```
- 判断是否带 BOM：文件头三个字节应为 `EF BB BF`。

## 关键实现细节（为什么“可靠”）

- **引擎定位与暂存**：优先使用已配对的 `*_console.exe`（输出可被捕获）；若只有主程序
  或控制台版缺同级主程序，会把二者成对复制到 `%TEMP%\godotrun_mvl\` 再运行。
- **APPDATA 隔离**：运行期把 `APPDATA` 指到 `%TEMP%\godotappdata_mvl`，避免读取/写坏
  用户真实的 `user://config.txt`，同时在受限/沙箱环境也能正常工作。
- **日志落盘 + 汇总**：`ERROR/WARNING` 计数与行首片段、退出码透传，供代理快速判定。
- **已知噪音**：退出时的 7 个鼠标光标纹理释放提示（`RID allocations ... leaked at exit`
  等）是引擎内部行为，非项目问题；`godot-verify.ps1` 不据此判失败，只对
  `SCRIPT ERROR` / `Invalid call ... Nil` / `Parse JSON failed` 判失败。

## 校验基线

当前仓库干净基线：项目内 0 条 WARNING/ERROR（退出纹理噪音不计）。
新增积木或大改后若计数上升，按 SKILL.md 的“开发工作流”排查。
