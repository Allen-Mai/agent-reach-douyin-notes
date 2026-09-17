<#
.SYNOPSIS
    诊断抖音抓取链路 —— 逐项检查前置条件，定位失败原因

.DESCRIPTION
    按顺序检查：Node / opencli / 浏览器扩展连接 / 抖音登录态 / ffprobe。
    每一项给出 ✅ 或 ❌ 以及修复建议。

.EXAMPLE
    .\scripts\doctor.ps1
#>
[CmdletBinding()]
param(
    [string]$Session = 'douyin'
)

$ErrorActionPreference = 'Continue'
$pass = 0
$fail = 0

function Write-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '', [string]$Fix = '')
    if ($Ok) {
        $script:pass++
        Write-Host "  [OK]   $Name" -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
    }
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
    if (-not $Ok -and $Fix) { Write-Host "         → $Fix" -ForegroundColor Yellow }
}

Write-Host "`n抖音抓取链路诊断" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan

# ---------------------------------------------------------------- Node.js
Write-Host "`n[运行环境]" -ForegroundColor White
$node = Get-Command node -ErrorAction SilentlyContinue
Write-Check 'Node.js 可用' ([bool]$node) $(if ($node) { "路径: $($node.Source)" } else { '' }) '安装 Node.js: https://nodejs.org'

# ---------------------------------------------------------------- opencli 入口
$openCliMain = Join-Path $env:APPDATA 'npm\node_modules\@jackwener\opencli\dist\src\main.js'
$openCliOk = Test-Path $openCliMain
Write-Check 'opencli 入口文件存在' $openCliOk $(if ($openCliOk) { $openCliMain } else { '' }) '安装: npm install -g opencli'

if ($openCliOk) {
    $ver = & node $openCliMain --version 2>&1 | Select-Object -First 1
    Write-Check 'opencli 可执行' ($LASTEXITCODE -eq 0) "版本: $ver"
}

# ---------------------------------------------------------------- 浏览器扩展
Write-Host "`n[浏览器扩展]" -ForegroundColor White
if ($openCliOk) {
    $doctor = & node $openCliMain doctor 2>&1 | Out-String
    $extOk = $doctor -match 'Extension:\s*connected'
    $extLine = ($doctor -split "`n" | Where-Object { $_ -match 'Extension:' } | Select-Object -First 1)
    Write-Check 'OpenCLI 扩展已连接' $extOk $extLine.Trim() @'
安装扩展: https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk
（Edge 也可以从 Chrome 商店安装）
安装后保持浏览器打开，再跑一次本诊断。
'@

    $daemonOk = $doctor -match 'Daemon:\s*running'
    Write-Check 'OpenCLI daemon 运行中' $daemonOk
}

# ---------------------------------------------------------------- 抖音登录态
Write-Host "`n[抖音登录态 —— 最关键的一项]" -ForegroundColor White
if ($openCliOk) {
    try {
        & node $openCliMain browser $Session open 'https://www.douyin.com/' --window foreground 2>&1 | Out-Null
        Start-Sleep -Seconds 6
        $body = (& node $openCliMain browser $Session eval 'document.body.innerText.slice(0,3000)' 2>&1 | Out-String)

        $hasLoginBtn = $body -match '登录'
        $hasFeed = $body -match '推荐|关注|朋友'
        # 未登录特征：出现"下载 APP""手机随时看更方便"，且没有实际内容
        $looksLoggedOut = ($body -match '下载 APP' -or $body -match '手机随时看更方便')

        if ($hasLoginBtn -and $looksLoggedOut) {
            Write-Check '抖音已登录' $false '检测到「登录」按钮和下载 APP 提示，当前是未登录状态' @'
请在弹出的浏览器窗口里点击右上角「登录」扫码。
登录完成后重新运行本诊断。
'@
        } elseif ($hasFeed) {
            Write-Check '抖音已登录' $true '页面返回了正常的频道内容'
        } else {
            Write-Check '抖音登录态未知' $false "页面内容异常，前 120 字：$($body.Substring(0, [Math]::Min(120, $body.Length)))"
        }
    } catch {
        Write-Check '抖音登录态检测失败' $false $_.Exception.Message
    }
}

# ---------------------------------------------------------------- ffprobe
Write-Host "`n[可选工具]" -ForegroundColor White
$ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
if (-not $ffprobe) {
    $ffprobe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffprobe.exe -ErrorAction SilentlyContinue | Select-Object -First 1
}
Write-Check 'ffprobe 可用（仅用于下载后校验）' ([bool]$ffprobe) $(if ($ffprobe) { '已找到' } else { '未安装，不影响下载' }) '可选安装: winget install Gyan.FFmpeg'

# ---------------------------------------------------------------- 总结
Write-Host "`n" -NoNewline
Write-Host ("=" * 50) -ForegroundColor Cyan
if ($fail -eq 0) {
    Write-Host "全部通过 ($pass 项)。可以开始抓取：" -ForegroundColor Green
    Write-Host '  .\scripts\douyin-download.ps1 "<抖音链接>"' -ForegroundColor White
} else {
    Write-Host "通过 $pass 项，失败 $fail 项。请按上面的提示修复。" -ForegroundColor Yellow
}
Write-Host ''
