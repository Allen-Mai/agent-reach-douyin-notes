# 抖音视频抓取实战笔记

用 **OpenCLI 浏览器自动化**绕开 yt-dlp 抓取抖音视频的完整记录 —— 包括四条失败路线、根因分析，以及最终跑通的方案。

> 2026-09-17 于 Windows 11 实测通过。抖音风控变化频繁，本文的结论有时效性，请以最新实测为准。

---

## 一句话结论

**`yt-dlp` 抓抖音在当前环境已不可用**（Edge/Chrome 的 cookie 被 App-Bound Encryption 保护，且抖音要求登录态）；
**改用 OpenCLI 驱动真实浏览器会话可以稳定跑通** —— 实测下载到完整视频（34.29 MB / 3分51.6秒 / H.264 1080×1920 + AAC）。

---

## 目录

- [测试环境](#测试环境)
- [四条失败路线（以及为什么失败）](#四条失败路线以及为什么失败)
- [根因分析](#根因分析)
- [可用方案：OpenCLI + curl](#可用方案opencli--curl)
- [快速开始](#快速开始)
- [踩坑清单](#踩坑清单)
- [能力边界](#能力边界)
- [验证记录](#验证记录)
- [合规提醒](#合规提醒)

---

## 测试环境

| 组件 | 版本 |
|---|---|
| OS | Windows 11 家庭版 中文版 build 26200 |
| 浏览器 | Microsoft Edge 153.0.4234.32 |
| Node.js | v26.7.0 |
| Python | 3.14.6 |
| Agent Reach | 1.5.0 |
| yt-dlp | 2026.08.19 |
| OpenCLI | 1.8.7（浏览器扩展 1.0.24） |

---

## 四条失败路线（以及为什么失败）

### 1. 直接 `yt-dlp <url>` —— 报缺 cookie

```
ERROR: [Douyin] 7682736756080315711: Fresh cookies (not necessarily logged in) are needed
```

注意：短链（`v.douyin.com/xxx`）能正常解析出视频 ID，说明 URL 解析没问题，卡在数据获取。

### 2. `yt-dlp --impersonate chrome` —— TLS 指纹伪装无效

```
ERROR: [Douyin] 7682736756080315711: Fresh cookies (not necessarily logged in) are needed
```

一开始我怀疑是 TLS 指纹被识别（这是很多站点的常见风控），实测证明**不是**。`curl_cffi` 的 Chrome 指纹伪装对抖音这个接口无效，它确实在查 cookie。

### 3. `yt-dlp --cookies-from-browser edge` —— 解不开加密

```
ERROR: Failed to decrypt with DPAPI.
```

Edge 运行时会锁死 cookie 数据库（连共享读都打不开）：

```
Copy-Item : 文件"...\Network\Cookies"正由另一进程使用，因此该进程无法访问此文件。
[System.IO.File]::Open(..., FileShare::ReadWrite)  →  同样失败
```

完全关闭 Edge 后文件可以读取了，但 yt-dlp 依然失败 —— 因为 **App-Bound Encryption**。

### 4. `browser_cookie3.edge()` —— 同样的墙

```python
BrowserCookieError: Unable to get key for cookie decryption
```

换一个库也不行，证明这不是 yt-dlp 的实现问题，而是**加密层本身**在阻止第三方读取。

---

## 根因分析

失败由**两层原因叠加**造成，缺一不可：

### 第一层：App-Bound Encryption 挡住 cookie 提取

新版 Chromium 系浏览器（Edge / Chrome）把 cookie 加密密钥与浏览器可执行文件绑定，第三方程序无法解密即使用户是本人、即使浏览器已关闭。

相关 issue：
- [yt-dlp#10927 — Failed to decrypt with DPAPI](https://github.com/yt-dlp/yt-dlp/issues/10927)
- [yt-dlp#7271 — Could not copy Chrome cookie database](https://github.com/yt-dlp/yt-dlp/issues/7271)

### 第二层：抖音要求登录态才返回数据

这一层更根本，也更容易被忽略。实测证据 —— 在**真实浏览器**里打开抖音首页，未登录时页面正文只有：

```
开启读屏标签 / 精选 / 推荐 / 关注 / 朋友 / 我的 / 小游戏
2026 © 抖音 / 京ICP备16016397号-3 / ...
手机随时看更方便 / 下载 APP
```

视频详情页则永远停在 **「视频数据加载中」**，`<video>` 元素数量为 0，右侧推荐位全是骨架屏占位。

> 所以即使绕过了第一层的 cookie 加密（比如手工导出 cookie），只要没有登录态，抖音依然不给数据。

### 其他相关 issue

- [yt-dlp#16831 — Unable to download videos from Douyin](https://github.com/yt-dlp/yt-dlp/issues/16831)（已关闭，标记 duplicate + site-bug，报告者带 282 个 cookie 仍失败）
- [yt-dlp#16867 — Fresh cookies issue with valid cookies on nightly](https://github.com/yt-dlp/yt-dlp/issues/16867)
- [yt-dlp#17464 — Douyin extractor is currently unable to download videos](https://github.com/yt-dlp/yt-dlp/issues/17464)

---

## 可用方案：OpenCLI + curl

核心思路：**不碰 cookie 提取，直接驱动用户已登录的真实浏览器**。

OpenCLI 通过浏览器扩展接管一个真实标签页，所以它天然拥有用户的登录态 —— 而抖音要的正是登录态。

```
opencli browser <session> open <url>      # 打开页面（用真实浏览器）
opencli browser <session> extract         # 提取页面文字内容
opencli browser <session> network --raw   # 抓网络请求，找到视频分片直链
curl <直链> --referer https://www.douyin.com/   # 下载
```

### 关键点

1. **必须登录抖音**。这是唯一无法自动化的步骤 —— 需要用户在浏览器窗口里扫码。
2. **视频用 MSE blob**（`video.src` 是 `blob:https://...`），所以读 `<video>` 标签拿不到东西，必须从网络请求里抓分片地址。
3. **下载必须带 `Referer: https://www.douyin.com/`**，否则 CDN 拒绝（防盗链）。

### 工具依赖

真正不可替代的只有 **OpenCLI**，其余都是通用工具。完整清单见 [`tools/README.md`](tools/README.md)。

| 工具 | 版本（实测） | 必需性 | 作用 |
|---|---|---|---|
| **OpenCLI** | 1.8.7 | **必需** | 浏览器自动化层，绕过 cookie 加密 |
| └ 浏览器扩展 | 1.0.24 | **必需** | 必须手动安装 |
| Node.js | v26.7.0 (18+) | **必需** | OpenCLI 运行时 |
| curl | 8.21.0 | **必需** | 下载分片（Win10+ 自带） |
| ffmpeg / ffprobe | 9.0.1 | 可选 | 校验分辨率时长、音频提取 |

**一键还原**：

```powershell
.\tools\install-tools.ps1              # 安装可自动化的部分并验证
.\tools\install-tools.ps1 -SkipFfmpeg  # 不需要校验工具
```

> 浏览器扩展那一步无法自动化（浏览器安全模型限制），脚本会输出指引。

---

## 快速开始

### 前置条件

```powershell
# 0. 一键安装工具链（推荐）
.\tools\install-tools.ps1

# 或者手动：
# 1. 安装 OpenCLI
npm install -g opencli

# 2. 安装浏览器扩展（Edge 也可从 Chrome 商店安装）
#    https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk

# 3. 验证连接 —— 应显示 Extension: connected
opencli doctor

# 4. 在浏览器里登录抖音
```

### 使用

```powershell
# 支持完整链接，也支持直接粘贴抖音 App 的分享文本
.\scripts\douyin-download.ps1 "https://v.douyin.com/ZwH8yoqq0XM/"

.\scripts\douyin-download.ps1 "2.89 复制打开抖音，看看【方师傅的作品】... https://v.douyin.com/ZwH8yoqq0XM/ 04/02"
```

脚本会依次完成：打开页面 → 等待视频元素 → 提取内容 → 抓取直链 → 下载 → ffprobe 校验。

---

## 踩坑清单

这一节是本文最有价值的部分 —— 都是实际调试中撞到的，不是理论推测。

### 坑 1：`opencli eval` 的引号会被三层解析破坏

**现象**：任何含双引号或 `|` 的 JS 都报 `SyntaxError: Unexpected end of input` / `Invalid or unexpected token`，甚至出现：

```
'aweme' is not recognized as an internal or external command
```

**原因**：参数经过 `PowerShell → cmd.exe → node` 三层，引号被逐层剥掉，`|` 被 cmd 当成管道符。

**解决**：**不要调用 `opencli.cmd`，直接用 node 调入口文件**：

```powershell
$main = "$env:APPDATA\npm\node_modules\@jackwener\opencli\dist\src\main.js"
node $main browser douyin eval "JSON.stringify({t:document.title})"   # ✅ 引号正常工作
```

入口路径可以从 `opencli.cmd` 里读出来（`cmd /c type "%APPDATA%\npm\opencli.cmd"` 最后一行）。

**变通写法**（如果必须走 `.cmd`）：用 `String.fromCharCode` 代替字符串字面量，并保持单行：

```javascript
// 代替 document.querySelector("video")
document.querySelector(String.fromCharCode(118,105,100,101,111))
```

### 坑 2：`browser state` 在抖音页面直接崩

```
TypeError: Cannot read properties of null (reading 'getAttribute')
    at buildTree (<anonymous>:4:29)
```

抖音页面 DOM 结构复杂（含大量自定义元素和动态节点），OpenCLI 的无障碍树构建会空指针。

**解决**：用 `browser extract` 代替 `state` 获取页面内容。

### 坑 3：npm 全局目录下的 `.ps1` 和 `package.json` 读取异常

**现象**：`get-content` / 读取工具读到的内容是二进制乱码，但**执行完全正常**：

```
mcporter.ps1:1 字符: 8
+ 噠cb )?澐tj/,鬵? ...
表达式或语句中包含意外的标记")"。
```

`mcporter.cmd`、`opencli.cmd`、`npm.ps1` 全部如此，EFS 属性显示未加密（只有 `Archive`）。

**解决**：
- 执行用 `.cmd`（能正常运行）
- 读取内容用 `cmd /c type`（能读出正确明文）
- 需要传参时用**坑 1** 的 node 直调方案

**结论**：这台机器上有安全软件/EDR 在拦截 PowerShell 对特定路径的直接读取，属于环境特性，不是文件损坏。

### 坑 4：视频是 MSE blob，拿不到直链

```javascript
document.querySelector('video').src
// → "blob:https://www.douyin.com/dc86c25c-c1b6-47f1-a620-c6aec330c846"
```

**解决**：用 `network --all --raw` 抓底层请求，筛选 `video/tos` / `douyinvod` / `v3-web` 且含 `mime_type=video` 的条目。

**注意**：`network` 输出可能很大（一次抓到 128 条、落盘 684 KB），**先落盘再检索**，不要反复调用。

### 坑 5：下载被 CDN 拒绝（防盗链）

必须带 Referer：

```powershell
curl.exe -L -o out.mp4 `
  --referer "https://www.douyin.com/" `
  --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ... Chrome/150.0.0.0 Safari/537.36" `
  "<直链>"
```

带上后返回 `206` / `200`，`content-type: video/mp4`。

### 坑 6：画质会波动 —— 同一条视频可能抓到不同码率

这是实测中反复出现的现象，**同一条视频、同一个链接**，多次抓取拿到的分片码率不同：

| 抓取次数 | 文件大小 | 分辨率 |
|---|---|---|
| 第 1 次 | 34.29 MB | 1080×1920 |
| 第 2 次 | 14.06 MB | 576×1024 |
| 第 3 次 | 14.06 MB | 576×1024 |
| 第 4 次 | 34.29 MB | 1080×1920 |

**原因**：抖音用 MSE（Media Source Extensions）+ 自适应码率（ABR），播放器会根据网络状况、窗口大小等因素动态请求不同清晰度的分片。`network` 命令抓到的只是"当时实际在播的那一档"。

**应对**：
- 下载后用 `ffprobe` 校验分辨率，不满意就重跑（脚本已内置校验输出）
- 更彻底的做法是在页面上显式切换到「高清 1080P」再抓取（本项目未实现，欢迎 PR）
- 页面上的清晰度选项实测有：高清 1080P / 标清 540P / 智能

### 坑 7：下载偶发 TLS 抖动

```
curl: (56) schannel: server closed abruptly (missing close_notify)
```

抖音 CDN 偶发中断连接，重跑通常就好。脚本已加 `--retry 4 --retry-delay 2 --retry-all-errors` 以及外层 3 次重试。

### 坑 8：脚本文件必须是 UTF-8 with BOM

在中文 Windows + PowerShell 5.1 下，**无 BOM 的 UTF-8 脚本会被按 GBK 解析**，导致中文注释和字符串全部乱码，甚至 here-string 的终止符都被吃掉：

```
+     Write-Check 'OpenCLI 鎵╁睍宸茶繛鎺? $extOk ...
字符串缺少终止符: '@。
```

**解决**：保存为 **UTF-8 with BOM**。

```powershell
$text = [System.IO.File]::ReadAllText($f, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($f, $text, (New-Object System.Text.UTF8Encoding($true)))
```

> 注意：很多编辑器/工具在保存时会**去掉 BOM**，改完脚本需要复查一遍。

### 坑 9：关闭 Edge 后 cookie 库才可读（但仍无用）

如果确实需要读磁盘 cookie，必须先完全结束所有 Edge 进程：

```powershell
Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
```

注意 Edge 会有**后台驻留进程**：用户关闭窗口后仍可能有 8–11 个 `msedge` 进程存活（连主窗口标题都不显示），此时 cookie 库依然被锁。

但如前所述，即使读出文件也解不开 App-Bound Encryption —— 所以这条路**不必再试**。

---

## 能力边界

| 能做 | 做不到 |
|---|---|
| 单条视频下载（含无水印直链） | 批量抓某博主全部作品（需另写翻页+限流） |
| 标题 / 作者 / 标签 / 互动数据 | 评论区完整抓取 |
| 页面自带章节要点（AI 摘要） | 站内搜索、热榜 |
| 音频提取（可接 Whisper 转文字） | 绕过风控的长期稳定方案 |
| 下载后 ffprobe 校验 | **稳定拿到最高画质**（受 ABR 影响在 576p–1080p 间波动，见坑 6） |

**时效性警告**：直链 URL 里带 `expire` 和 `x-signature` 参数，**会过期**。抓到后要立即下载，不要缓存起来以后用。

---

## 验证记录

实测样本：`https://v.douyin.com/ZwH8yoqq0XM/`（方师傅《当你有个懂金融的老爸(120期)》）

```
http=200  size=35953711 bytes  time=5.76s

ffprobe 输出：
  codec_name=aac        codec_type=audio
  codec_name=h264       codec_type=video
  width=1080  height=1920
  format_name=mov,mp4,m4a,3gp,3g2,mj2
  duration=231.595011
  size=35953711
```

页面同时提取到的元数据：

- 标题：`第124集 | 当你有个懂金融的老爸(120期)2种退休金制度`
- 作者：方师傅（粉丝 75.2万 / 获赞 588.7万）
- 发布：2026-09-07 21:00
- 数据：1.9万赞 / 776评论 / 3207收藏 / 1.3万分享
- 合集：老爸金融

---

## 合规提醒

- 本文记录的是**技术可行性**，不代表对任何具体用途的授权。
- 下载的视频版权归原作者所有。请勿用于商业传播、二次分发或任何侵犯著作权的用途。
- 抖音风控会记录异常访问模式。**建议使用小号**操作，避免主账号受限。
- 请遵守目标平台的服务条款及所在地区法律法规。

---

## 参考

### 本项目用到的工具

- [OpenCLI](https://github.com/jackwener/OpenCLI) —— **核心**，浏览器自动化层（[扩展商店](https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk)）
- [Node.js](https://nodejs.org) —— OpenCLI 运行时
- [curl](https://curl.se) —— 下载视频分片
- [FFmpeg](https://ffmpeg.org) —— 校验下载结果（可选）

完整清单、版本与安装方式见 [`tools/README.md`](tools/README.md)。

### 相关项目与背景

- [Agent Reach](https://github.com/Panniantong/agent-reach) —— 本次环境搭建用的基础设施（顺带装上了 OpenCLI、yt-dlp；**它本身不支持抖音**）
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) —— 视频下载工具（本文记录了其抖音提取器当前失效的情况）

### 相关 issue

- [#16831 — Unable to download videos from Douyin](https://github.com/yt-dlp/yt-dlp/issues/16831)
- [#16867 — Fresh cookies issue with valid cookies on nightly](https://github.com/yt-dlp/yt-dlp/issues/16867)
- [#10927 — Failed to decrypt with DPAPI](https://github.com/yt-dlp/yt-dlp/issues/10927)
- [#17464 — Douyin extractor is currently unable to download videos](https://github.com/yt-dlp/yt-dlp/issues/17464)

## License

MIT
