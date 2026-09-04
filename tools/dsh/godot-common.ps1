# godot-common.ps1 — MVL × DeepSeek Harness 公共函数
# Windows PowerShell 5.1 兼容；由 godot-run / godot-verify / godot-import 点源引用。

# 原生命令(Godot)的 stderr 会经 *> 重定向进日志；不可用 Stop，否则其 ERROR 行会变成终止错误
$ErrorActionPreference = 'Continue'

# 仓库根 = tools\dsh 的上两级
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:GodotExe = $env:GODOT_EXE            # 可选：环境变量直接指定引擎
$script:StagedDir = Join-Path $env:TEMP 'godotrun_mvl'

function Resolve-MvlProject {
    param([string]$Project = '')
    if ($Project) {
        $p = (Resolve-Path $Project -ErrorAction Stop).Path
    } else {
        $p = $script:RepoRoot
    }
    if (-not (Test-Path (Join-Path $p 'project.godot'))) {
        throw "不是 Godot 工程（缺少 project.godot）：$p"
    }
    return $p
}

# 定位一份可捕获输出的 Godot 控制台程序；必要时把 主程序+控制台版 成对复制到 %TEMP%\godotrun_mvl
function Get-MvlGodotConsole {
    if ($script:GodotExe) {
        if ((Test-Path $script:GodotExe)) { return $script:GodotExe }
    }

    $known = @(
        'C:\Users\ASUS\Desktop\Godot_v4.7.2-stable_win64.exe'
        'C:\Users\ASUS\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
    )
    $consoleCandidates = @()
    $mainCandidates = @()

    foreach ($k in $known) {
        if (Test-Path $k) {
            if ($k -match '_console\.exe$') { $consoleCandidates += $k }
            else { $mainCandidates += $k }
        }
    }

    # 其它常见位置再扫一轮（Desktop / Downloads 下的 Godot*.exe）
    $extraRoots = @(
        [Environment]::GetFolderPath('Desktop')
        (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads')
    )
    foreach ($r in $extraRoots) {
        if (-not (Test-Path $r)) { continue }
        Get-ChildItem -Path $r -Filter 'Godot*.exe' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '_console\.exe$') { $consoleCandidates += $_.FullName }
            elseif ($_.Length -gt 10MB) { $mainCandidates += $_.FullName }
        }
    }

    # 1) 已配对的 console 程序：直接用
    foreach ($c in $consoleCandidates) {
        $sibling = $c -replace '_console\.exe$', '.exe'
        if (Test-Path $sibling) { return $c }
    }

    # 2) 找一份主程序 + 任一份 console 版，成对暂存
    $main = $mainCandidates | Select-Object -First 1
    $console = $consoleCandidates | Select-Object -First 1
    if (-not $main -and -not $console) { throw '未找到 Godot 引擎，请设置环境变量 GODOT_EXE 指向控制台版或主程序。' }

    New-Item -ItemType Directory -Force -Path $script:StagedDir | Out-Null
    $baseName = 'Godot_v4.7.2-stable_win64'
    $dstMain = Join-Path $script:StagedDir "$baseName.exe"
    $dstConsole = Join-Path $script:StagedDir "${baseName}_console.exe"

    if ($main -and -not (Test-Path $dstMain)) { Copy-Item $main $dstMain -Force }
    if ($console -and -not (Test-Path $dstConsole)) { Copy-Item $console $dstConsole -Force }
    if (-not $main -and -not (Test-Path $dstMain)) {
        # 只有 console 的情况：需要主程序，报错提示
        throw '找到控制台版但缺少主程序，无法运行。'
    }
    if (-not $console -and -not (Test-Path $dstConsole)) {
        # 只有主程序：console 版可从 Downloads 目录复制，此处用主程序自身（无控制台输出则提示）
        return $dstMain
    }
    if (-not (Test-Path $dstMain) -or -not (Test-Path $dstConsole)) {
        throw '引擎暂存不完整，请手工设置 GODOT_EXE。'
    }
    return $dstConsole
}

# 创建本次运行使用的隔离 APPDATA（避免污染真实 user:// 配置，兼容受限环境）
function New-MvlAppData {
    $ud = Join-Path $env:TEMP 'godotappdata_mvl'
    New-Item -ItemType Directory -Force -Path $ud | Out-Null
    return $ud
}

# 汇总日志里的 ERROR / WARNING 行
function Get-MvlLogSummary {
    param([string]$LogPath)
    if (-not (Test-Path $LogPath)) { return "（无日志文件：$LogPath）" }
    $lines = Get-Content $LogPath
    $errs = @($lines | Select-String -Pattern '^(ERROR|SCRIPT ERROR|WARNING):|^\s*ERROR:' )
    $warns = @($lines | Select-String -Pattern '^\s*W\s+\d|^WARNING:')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("日志: $LogPath")
    [void]$sb.AppendLine(("ERROR 相关行数: {0}     WARNING 相关行数: {1}" -f $errs.Count, $warns.Count))
    foreach ($m in @($errs | Select-Object -First 12)) {
        [void]$sb.AppendLine(('  ' + $m.Line))
    }
    return $sb.ToString()
}
