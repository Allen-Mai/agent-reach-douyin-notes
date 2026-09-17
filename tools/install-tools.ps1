<#
.SYNOPSIS
    安装抖音抓取所需的工具链

.DESCRIPTION
    检查并安装：Node.js / OpenCLI / ffmpeg，然后验证环境。
    浏览器扩展无法自动安装，脚本会给出指引。

.PARAMETER SkipFfmpeg
    跳过 ffmpeg 安装（仅用于校验，非必需）

.PARAMETER Force
    即使已安装也重新安装

.EXAMPLE
    .\tools\install-tools.ps1

.EXAMPLE
    .\tools\install-tools.ps1 -SkipFfmpeg
#>
[CmdletBinding()]
param(
    [switch]$SkipFfmpeg,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

function Write-Step { param([string]$m) Write-Host "`n$m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Bad  { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red }

# OpenCLI 的入口文件路径（npm 全局安装位置）
$openCliMain = Join-Path $env:APPDATA 'npm\node_modules\@jackwener\opencli\dist\src\main.js'

Write-Host "`n抖音抓取工具链安装" -ForegroundColor White
Write-Host ("=" * 52) -ForegroundColor Cyan

# ---------------------------------------------------------------- Node.js
Write-Step "[1/4] Node.js"
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $nodeVer = (& node --version 2>&1 | Select-Object -First 1)
    Write-Ok "已安装 $nodeVer"
} else {
    Write-Bad "未安装 Node.js"
    Write-Host "         安装命令: winget install OpenJS.NodeJS" -ForegroundColor Yellow
    Write-Host "         安装后请重开终端再运行本脚本。" -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------- OpenCLI
Write-Step "[2/4] OpenCLI"
$needInstall = $Force -or -not (Test-Path $openCliMain)

if (-not $needInstall) {
    $ver = (& node $openCliMain --version 2>&1 | Select-Object -First 1)
    Write-Ok "已安装 $ver"
} else {
    Write-Host "  正在安装 opencli ..." -ForegroundColor Gray
    & npm install -g opencli 2>&1 | Select-Object -Last 5
    if (Test-Path $openCliMain) {
        $ver = (& node $openCliMain --version 2>&1 | Select-Object -First 1)
        Write-Ok "安装成功 $ver"
    } else {
        Write-Bad "安装失败。请手动运行: npm install -g opencli"
    }
}

# ---------------------------------------------------------------- ffmpeg
Write-Step "[3/4] ffmpeg（可选，用于校验下载结果）"
if ($SkipFfmpeg) {
    Write-Warn "已按参数跳过"
} else {
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        $ffmpeg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($ffmpeg) {
        Write-Ok "已安装"
    } else {
        Write-Host "  正在通过 winget 安装 ..." -ForegroundColor Gray
        & winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements 2>&1 | Select-Object -Last 4
        Write-Warn "若刚装好，PATH 需要重开终端才生效"
    }
}

# ---------------------------------------------------------------- 浏览器扩展
Write-Step "[4/4] 浏览器扩展（必须手动安装）"
Write-Host @"
  这一步无法自动化 —— 浏览器安全模型不允许程序静默安装扩展。

  1. 打开: https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk
  2. 点击「添加至 Chrome」
  3. 保持浏览器打开，然后运行下面的验证命令
"@ -ForegroundColor Gray

# ---------------------------------------------------------------- 验证
Write-Host ("`n" + "=" * 52) -ForegroundColor Cyan
Write-Host "环境验证" -ForegroundColor White

if (Test-Path $openCliMain) {
    $doctor = & node $openCliMain doctor 2>&1 | Out-String
    $extOk = $doctor -match 'Extension:\s*connected'
    $daemonOk = $doctor -match 'Daemon:\s*running'

    if ($extOk) { Write-Ok "OpenCLI 扩展已连接" }
    else { Write-Bad "OpenCLI 扩展未连接 —— 请按上面第 4 步安装扩展" }

    if ($daemonOk) { Write-Ok "OpenCLI daemon 运行中" }
    else { Write-Warn "daemon 未运行（首次使用时会自动启动）" }

    Write-Host "`n  doctor 完整输出:" -ForegroundColor DarkGray
    $doctor -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}

Write-Host "`n下一步:" -ForegroundColor White
Write-Host "  1. 在浏览器里登录抖音" -ForegroundColor Gray
Write-Host "  2. .\scripts\doctor.ps1                        # 完整链路自检" -ForegroundColor Gray
Write-Host "  3. .\scripts\douyin-download.ps1 `"<链接>`"     # 开始下载" -ForegroundColor Gray
Write-Host ''
