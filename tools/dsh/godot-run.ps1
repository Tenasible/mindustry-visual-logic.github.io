# godot-run.ps1 — 运行 MVL Godot 工程 N 帧并抓取完整控制台输出
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File godot-run.ps1 [-Project <path>] [-Frames 600]
param(
    [string]$Project = '',
    [int]$Frames = 600
)
# 原生命令的 stderr 经 *> 进日志；EAP 需为 Continue，否则 Godot ERROR 行会中断脚本
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'godot-common.ps1')

$proj = Resolve-MvlProject -Project $Project
$console = Get-MvlGodotConsole
$oldAppData = $env:APPDATA
$env:APPDATA = New-MvlAppData

$logDir = Join-Path $env:TEMP 'MVL_DSH'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("run-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

try {
    & $console --path $proj --quit-after $Frames *> $log
    $code = $LASTEXITCODE
} finally {
    $env:APPDATA = $oldAppData
}

Write-Output ("引擎退出码: {0}" -f $code)
Write-Output (Get-MvlLogSummary -LogPath $log)
Write-Output ("末尾 20 行：")
Get-Content $log -Tail 20 -ErrorAction SilentlyContinue
exit $code
