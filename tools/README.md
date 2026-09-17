# 工具清单

抖音抓取链路上用到的全部工具，以及它们的**安装来源**和**验证方式**。

> 为什么不在仓库里直接放工具本体？
> 这些工具都是 Node/npm 生态的公开包和通用二进制（OpenCLI、curl、ffmpeg），体积大且各有自己的发布渠道和许可证。
> 把它们的**副本**塞进仓库会导致版本漂移、许可证纠缠。
> 所以这里放的是**可复现的清单 + 一键还原脚本** —— 拿到仓库就能把环境装回来。

**一句话依赖边界**：真正不可替代的只有 **OpenCLI**（浏览器自动化层）。其余都是通用工具。

---

## 依赖分层

```
抖音抓取
└── 必需
    ├── OpenCLI 1.8.7          ← 核心：驱动真实浏览器会话，绕过 cookie 加密
    │   └── 浏览器扩展 1.0.24  ← 必须手动装（浏览器安全限制）
    ├── Node.js 18+            ← OpenCLI 运行时（实测 v26.7.0）
    └── curl                   ← 下载视频分片（Windows 10+ 自带，实测 8.21.0）
└── 可选（校验/后处理）
    └── ffmpeg / ffprobe 9.0.1 ← 校验分辨率时长；音频提取
```

---

## 必需组件

### 1. OpenCLI — 核心，不可替代

| 项 | 值 |
|---|---|
| 版本（实测） | **1.8.7** |
| 来源 | npm 官方包 |
| 许可证 | 见上游仓库 |
| 上游 | https://github.com/jackwener/OpenCLI |
| 作用 | 通过浏览器扩展接管真实标签页，执行点击/导航/JS/网络抓取 |

```bash
npm install -g opencli
```

**为什么它是关键**：抖音要求登录态，而浏览器 cookie 被 App-Bound Encryption 保护，第三方程序（yt-dlp / browser_cookie3）都读不出来。OpenCLI 不读取 cookie，而是**直接在你的浏览器里操作**，天然继承了登录态。

#### OpenCLI 浏览器扩展（必须手动安装）

| 项 | 值 |
|---|---|
| 版本（实测） | **1.0.24** |
| 商店地址 | https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk |

**这一步无法自动化** —— 浏览器安全模型不允许程序静默安装扩展。需要人工点「添加至 Chrome」。

> Edge 也能从 Chrome 商店装扩展，不必为此安装 Chrome。

验证：

```powershell
node "$env:APPDATA\npm\node_modules\@jackwener\opencli\dist\src\main.js" doctor
# 期望输出：Extension: connected
```

---

### 2. Node.js

| 项 | 值 |
|---|---|
| 版本（实测） | v26.7.0（要求 18+） |
| 来源 | https://nodejs.org |
| 作用 | OpenCLI 运行时 |

```powershell
winget install OpenJS.NodeJS
```

---

### 3. curl

| 项 | 值 |
|---|---|
| 版本（实测） | 8.21.0（Windows 自带） |
| 位置 | `C:\Windows\System32\curl.exe` |
| 作用 | 下载视频分片，**必须带 `Referer`** 才不被防盗链拦截 |

Windows 10 (1803+) / Windows 11 自带，无需安装。验证：`curl.exe --version`

> ⚠️ 在 PowerShell 里要写 `curl.exe`。直接写 `curl` 会被解析成 `Invoke-WebRequest` 的别名，参数不兼容。

---

## 可选组件

### ffmpeg / ffprobe

| 项 | 值 |
|---|---|
| 版本（实测） | 9.0.1-full_build (gyan.dev) |
| 来源 | winget |
| 作用 | `ffprobe` 校验下载结果（分辨率/时长/编码）；`ffmpeg` 做音频提取 |

```powershell
winget install Gyan.FFmpeg
```

**注意**：winget 装完后 **PATH 需要新开终端才生效**。没有 ffmpeg 也能下载，只是少了校验。

---

## 完整还原（一键）

```powershell
.\tools\install-tools.ps1              # 安装所有可自动安装的部分
.\tools\install-tools.ps1 -SkipFfmpeg  # 不需要校验工具
```

脚本会：检查 Node → 安装 OpenCLI → 安装 ffmpeg → 输出扩展安装指引 → 验证。

---

## 与 Agent Reach 的关系

本项目的抖音方案**不依赖** [Agent Reach](https://github.com/Panniantong/agent-reach)。澄清一下边界：

| 组件 | 来源 |
|---|---|
| **OpenCLI** | Agent Reach 的渠道安装器装上的（抖音方案真正依赖的就是它） |
| `yt-dlp` | Agent Reach 的 Python 依赖（试错用，**抖音上已失效**） |
| `gh` / `mcporter` / `ffmpeg` | 手动安装（Agent Reach 在 Windows 上这几项安装失败） |

Agent Reach 本身**不支持抖音** —— 它的 16 个平台里没有抖音。本项目的抖音方案是独立于它的。

---

## 版本漂移提示

抖音风控和 OpenCLI 都在持续更新，本清单记录的是 **2026-09-17** 的实测状态。

如果脚本突然失效，按这个顺序排查：

1. `opencli doctor` —— 扩展是否还连着
2. 浏览器里是否还是登录态
3. `npm update -g opencli` —— 上游是否已适配抖音的新变化
4. 抖音的接口/风控是否又变了
