# godot-verify.ps1 — 导入 + 运行 MVL 工程并汇总 ERROR/WARNING（改脚本/场景后的一键校验）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File godot-verify.ps1 [-Project <path>] [-Frames 300]
param(
    [string]$Project = '',
    [int]$Frames = 300
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
$importLog = Join-Path $logDir ("verify-import-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
$runLog = Join-Path $logDir ("verify-run-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

try {
    Write-Output '== 阶段 1/2: 导入 =='
    & $console --headless --import --path $proj *> $importLog
    $importCode = $LASTEXITCODE
    Write-Output ("导入退出码: {0}" -f $importCode)

    Write-Output '== 阶段 2/2: 运行 =='
    & $console --path $proj --quit-after $Frames *> $runLog
    $runCode = $LASTEXITCODE
    Write-Output ("运行退出码: {0}" -f $runCode)
} finally {
    $env:APPDATA = $oldAppData
}

Write-Output '== 导入日志汇总 =='
Write-Output (Get-MvlLogSummary -LogPath $importLog)
Write-Output '== 运行日志汇总 =='
Write-Output (Get-MvlLogSummary -LogPath $runLog)
Write-Output '== 运行日志末尾 25 行 =='
Get-Content $runLog -Tail 25 -ErrorAction SilentlyContinue

# 判定：脚本级错误（SCRIPT ERROR / Nil / Parse JSON failed / Invalid call）算失败
$bad = Get-Content $runLog -ErrorAction SilentlyContinue |
    Select-String -Pattern 'SCRIPT ERROR|Invalid call|base ''Nil''|Parse JSON failed'
if ($bad.Count -gt 0) {
    Write-Output ("校验失败：发现 {0} 处脚本级错误" -f $bad.Count)
    exit 1
}
if ($importCode -ne 0 -or $runCode -ne 0) {
    Write-Output '校验失败：引擎退出码非 0（已知例外：无外网时公告请求失败不在此列）'
    exit 1
}
Write-Output '校验通过：导入与运行均无脚本级错误。'
exit 0
