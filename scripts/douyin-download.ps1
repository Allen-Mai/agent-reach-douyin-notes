<#
.SYNOPSIS
    抖音视频下载 —— 通过 OpenCLI 浏览器自动化 + curl

.DESCRIPTION
    绕过 yt-dlp（其 Douyin extractor 在 App-Bound Encryption 下无法读取浏览器 cookie），
    改用 OpenCLI 驱动真实浏览器会话抓取视频直链。

    前置条件：
      1. OpenCLI 扩展已安装并连接（运行 opencli doctor 应显示 Extension: connected）
      2. 浏览器里已登录抖音（未登录时页面会停在「视频数据加载中」）
      3. 脚本运行期间不要关闭 OpenCLI 打开的浏览器窗口

.PARAMETER Url
    抖音视频链接。支持电脑端链接、短链（v.douyin.com）以及整段分享文本
    （会自动提取其中的 URL）。

.PARAMETER OutDir
    输出目录，默认 $env:TEMP\douyin-downloads

.EXAMPLE
    .\douyin-download.ps1 "https://v.douyin.com/ZwH8yoqq0XM/"

.EXAMPLE
    # 直接粘贴抖音 App 的分享文本也可以
    .\douyin-download.ps1 "2.89 复制打开抖音，看看【方师傅的作品】... https://v.douyin.com/ZwH8yoqq0XM/ 04/02"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url,

    [string]$OutDir = (Join-Path $env:TEMP 'douyin-downloads'),

    [string]$Session = 'douyin',

    [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 定位 opencli
# 关键：不要调用 opencli.cmd / opencli.ps1。
#   - .ps1 在部分环境下无法被 PowerShell 读取（加密/保护层）
#   - .cmd 会把 JS 参数再交给 cmd.exe 解析一遍，引号和 | 会被破坏
# 直接用 node 调用入口文件可以完全绕开这两层问题。
function Get-OpenCliMain {
    $candidates = @(
        (Join-Path $env:APPDATA 'npm\node_modules\@jackwener\opencli\dist\src\main.js')
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    throw "找不到 opencli 入口文件。请确认已安装：npm install -g opencli"
}

$OpenCliMain = Get-OpenCliMain

function Invoke-OpenCli {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgs)
    $output = & node $OpenCliMain @CliArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "opencli 执行失败：opencli $($CliArgs -join ' ')`n$($output -join "`n")"
    }
    return $output
}

# ---------------------------------------------------------------- 解析输入
# 从整段分享文本里提取第一个 http(s) 链接
$linkMatch = [regex]::Match($Url, 'https?://[^\s]+')
if (-not $linkMatch.Success) { throw "输入里没找到有效链接：$Url" }
$cleanUrl = $linkMatch.Value.TrimEnd('，', '。', ',', '.', ')', '）')

Write-Host "[1/6] 打开页面: $cleanUrl" -ForegroundColor Cyan
Invoke-OpenCli browser $Session open $cleanUrl --window foreground | Out-Null

Write-Host "[2/6] 等待视频元素出现（最多 ${TimeoutSec}s）..." -ForegroundColor Cyan
Write-Host "      如果超时，请确认浏览器里已登录抖音。" -ForegroundColor DarkGray

$js = "document.querySelectorAll(String.fromCharCode(118,105,100,101,111)).length"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$found = $false
while ((Get-Date) -lt $deadline) {
    try {
        $n = (Invoke-OpenCli browser $Session eval $js | Out-String).Trim()
        if ($n -match '^\d+$' -and [int]$n -gt 0) { $found = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}
if (-not $found) {
    throw "等待视频元素超时。最常见原因：浏览器里没有登录抖音。`n请在浏览器窗口里扫码登录后重试。"
}
Write-Host "      视频元素已出现" -ForegroundColor Green

# ---------------------------------------------------------------- 抓取页面内容
Write-Host "[3/6] 提取页面内容..." -ForegroundColor Cyan
$contentJson = (Invoke-OpenCli browser $Session extract) -join "`n"
$pageContent = ($contentJson | ConvertFrom-Json).content

# 短链会被重定向，取真实 URL 才能拿到视频 ID
$pageUrl = (Invoke-OpenCli browser $Session get url | Out-String).Trim()
$videoId = $null
$idMatch = [regex]::Match($pageUrl, '/video/(\d+)')
if ($idMatch.Success) { $videoId = $idMatch.Groups[1].Value }

# 从页面文本里提取作者与标题，用于生成可读文件名
$author = $null
$title = $null
if ($pageContent) {
    $lines = $pageContent -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

    # 作者：出现在「粉丝 X万获赞 Y万」附近
    # 注意：extract 输出是 markdown，作者名前面常有头像图片/链接行，必须过滤掉
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '粉丝.+获赞') { continue }
        # 从紧邻的上方找最近的一个「干净」行：不含 URL / markdown 链接 / 图片标记
        for ($j = $i - 1; $j -ge 0 -and $j -ge ($i - 4); $j--) {
            $cand = $lines[$j]
            if ($cand -match 'http|douyin\.com|\]\(') { continue }
            if ($cand -match '^\s*[\[\]()!]') { continue }
            if ($cand.Length -gt 30) { continue }
            $author = $cand
            break
        }
        break
    }

    # 标题：含话题标签（#）的那一行，或含「第N集」的那一行
    foreach ($l in $lines) {
        if ($l -match '#' -and $l.Length -gt 8) { $title = $l; break }
    }
    if (-not $title) {
        foreach ($l in $lines) { if ($l -match '第\d+集') { $title = $l; break } }
    }
}
if ($title) { Write-Host "      标题: $title" }
if ($author) { Write-Host "      作者: $author" }

# ---------------------------------------------------------------- 抓视频直链
Write-Host "[4/6] 捕获网络请求，检索视频直链..." -ForegroundColor Cyan
$netRaw = (Invoke-OpenCli browser $Session network --since 5m --all --raw) -join "`n"
$netObj = $netRaw | ConvertFrom-Json

$videoUrl = $null
foreach ($e in $netObj.entries) {
    if ($e.url -match 'video/tos|douyinvod|v3-web' -and $e.url -match 'mime_type=video') {
        $videoUrl = $e.url
        break
    }
}
if (-not $videoUrl) {
    foreach ($e in $netObj.entries) {
        if ($e.url -match 'video/tos|douyinvod') { $videoUrl = $e.url; break }
    }
}
if (-not $videoUrl) {
    throw "没在最近的网络请求里找到视频直链。`n可能原因：页面未真正播放、或请求已超出 5 分钟窗口。`n请刷新页面后再试。"
}
Write-Host ("      直链长度: " + $videoUrl.Length) -ForegroundColor Green

# ---------------------------------------------------------------- 下载
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 生成可读文件名：作者_标题_视频ID.mp4，缺失的部分自动跳过
$nameParts = @()
foreach ($p in @($author, $title)) {
    if (-not $p) { continue }
    $clean = $p -replace '[#\r\n]', '' -replace '[\\/:*?"<>|]', '_'
    $clean = ($clean -replace '\s+', ' ').Trim()
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    if ($clean) { $nameParts += $clean }
}
if ($videoId) { $nameParts += $videoId }
if ($nameParts.Count -eq 0) { $nameParts += (Get-Date -Format 'yyyyMMddHHmmss') }

$outFile = Join-Path $OutDir (($nameParts -join '_') + '.mp4')
Write-Host "[5/6] 下载中（必须带 referer，否则 CDN 会 403）..." -ForegroundColor Cyan

# 注意：必须带 Referer，抖音 CDN 有防盗链
# -s 关闭进度条（curl 把进度写 stderr，PowerShell 会当成 NativeCommandError 而中断）
# -S 保留真实错误信息
# --retry 处理抖音 CDN 常见的 TLS 抖动（schannel: server closed abruptly）
$curlArgs = @(
    '-L'
    '-s'
    '-S'
    '--fail'
    '--retry', '4'
    '--retry-delay', '2'
    '--retry-all-errors'
    '--max-time', '600'
    '-o', $outFile
    '--referer', 'https://www.douyin.com/'
    '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36'
    $videoUrl
)

$curlExit = 1
for ($attempt = 1; $attempt -le 3; $attempt++) {
    if ($attempt -gt 1) {
        Write-Host "      第 $attempt 次尝试..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    & curl.exe @curlArgs
    $curlExit = $LASTEXITCODE
    if ($curlExit -eq 0) { break }
}
if ($curlExit -ne 0) {
    throw "curl 下载失败（已重试 3 次），退出码 $curlExit`n常见原因：直链已过期（URL 含 expire 参数）或网络不稳定。请重新运行脚本获取新直链。"
}

# ---------------------------------------------------------------- 校验
Write-Host "[6/6] 校验文件..." -ForegroundColor Cyan
$f = Get-Item $outFile
Write-Host ("      文件: " + $f.FullName)
Write-Host ("      大小: " + [Math]::Round($f.Length / 1MB, 2) + " MB")

# 若安装了 ffprobe 则顺带校验媒体信息
$ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
if (-not $ffprobe) {
    $ffprobe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffprobe.exe -ErrorAction SilentlyContinue | Select-Object -First 1
}
if ($ffprobe) {
    $probePath = if ($ffprobe.Source) { $ffprobe.Source } else { $ffprobe.FullName }
    $info = & $probePath -v error -show_entries 'format=duration,size' -show_entries 'stream=codec_type,codec_name,width,height' -of default=noprint_wrappers=1 $outFile 2>&1
    Write-Host "      ffprobe:" -ForegroundColor DarkGray
    $info | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
}

Write-Host "`n完成: $outFile" -ForegroundColor Green
