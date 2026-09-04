# godot-import.ps1 — 导入 MVL Godot 工程资源（无头模式），用于刷新 .godot 缓存
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File godot-import.ps1 [-Project <path>]
param(
    [string]$Project = ''
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
$log = Join-Path $logDir ("import-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

try {
    & $console --headless --import --path $proj *> $log
    $code = $LASTEXITCODE
} finally {
    $env:APPDATA = $oldAppData
}

Write-Output ("导入退出码: {0}" -f $code)
Write-Output (Get-MvlLogSummary -LogPath $log)
Get-Content $log -Tail 15 -ErrorAction SilentlyContinue
exit $code
