<p align="center"><img src="docs/images/icon.png" width="120" alt="Nunsseop 图标"></p>

<h1 align="center">Nunsseop</h1>

<p align="center">
  <b>你的 MacBook 刘海，终于有用了。</b><br>
  音乐、通话、文件、类 Spotlight 启动器、AI 用量、代理通知、日历和系统 HUD，悬停即达。
</p>

<p align="center">
  <a href="https://github.com/namekun/Nunsseop/releases/latest"><img src="https://img.shields.io/github/v/release/namekun/Nunsseop?color=111111&label=release" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14 或更高版本">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555" alt="MIT 许可证"></a>
  <img src="https://img.shields.io/badge/Swift-native-orange?logo=swift&logoColor=white" alt="原生 Swift">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <b>简体中文</b> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="https://namekun.github.io/Nunsseop/">网站</a>
</p>

<p align="center">
  <img src="docs/images/home.png" width="720" alt="展开的刘海，显示正在播放的内容和日历">
</p>

*Nunsseop*（눈썹）在韩语里是*眉毛*的意思，也就是屏幕上方那道小小的弧线。它免费、开源，无需账户，没有订阅，也不做任何跟踪。

## 30 秒安装

```sh
brew install --cask namekun/tap/nunsseop
```

需要 [Homebrew](https://brew.sh)。Homebrew 会清除隔离属性，所以应用可以直接打开。要更新，请运行 `brew update && brew upgrade --cask nunsseop`；有新版本时，设置 › 通用 › 更新中的“拷贝更新命令”会把这条命令拷贝到剪贴板（如果应用是用旧的 dmg 安装的，拷贝的则是把它迁移到 Homebrew 的命令）。

需要 macOS 14 Sonoma 或更高版本。支持 Apple 芯片和 Intel，也支持没有刘海的屏幕。

## 上手第一分钟

1. **把指针移到刘海上。** 它会展开；指针移开后，它会自动收回。
2. **在“音乐”、Spotify、YouTube Music 或任意浏览器里播放点什么。** 刘海会自动识别，收起时还会显示一个小小的封面和可视化效果。
3. **右键点按刘海 → 设置**，选择要用的标签、它们的顺序、想看的弹出提示以及尺寸。

没有程序坞图标。Nunsseop 就住在刘海里。

## 功能一览

| | |
| :---: | :---: |
| <img src="docs/images/tab-search.png" alt="搜索，显示一个应用、一条命令和一项设置"><br>**搜索。** 一个可以查找应用、文件、命令、剪贴板、表情符号和算式的启动器，快捷键随你定。 | <img src="docs/images/tab-ai.png" alt="Claude Code 和 Codex 的 AI 用量"><br>**AI 用量。** Claude Code 和 Codex 的用量上限，无需登录。 |
| <img src="docs/images/shelf.png" alt="文件架子，带隔空投送卡片"><br>**架子。** 把文件暂放在刘海里，或直接拖到隔空投送上。 | <img src="docs/images/tab-timer.png" alt="计时器标签"><br>**计时器。** 倒计时、番茄钟和秒表，时长随意设置。 |
| <img src="docs/images/tab-tools.png" alt="工具标签"><br>**工具。** 音频输出、麦克风静音、保持唤醒、屏幕录制、取色器和文本提取。 | <img src="docs/images/tab-system.png" alt="系统标签，显示设备电量"><br>**系统。** CPU、内存、磁盘、网络和设备电量。 |
| <img src="docs/images/tab-emoji.png" alt="表情符号选择器"><br>**表情符号。** 所有表情符号都能搜索，点一下即可拷贝。 | <img src="docs/images/hud-headphones.png" alt="耳机电量 HUD"><br>**HUD。** 音量、亮度、AirPods 电量等等。 |
| <img src="docs/images/collapsed-call.png" alt="Zoom 通话期间收起的刘海"><br>**通话。** 显示通话所用的应用和已通话的时长。 | <img src="docs/images/collapsed-idle.png" alt="收起的刘海，显示 Claude Code 剩余用量和天气"><br>**一目了然。** 自己选择收起的刘海两侧各显示什么。 |

## 全部功能

**🎵 音乐**
- **任意应用的正在播放内容。** 支持“音乐”、Spotify、YouTube Music，以及 Safari、Chrome、Arc、Dia、Aside 等浏览器。有封面、播放控制，进度条还可以拖动。
- **同步歌词**来自 [LRCLIB](https://lrclib.net)，可以显示在标题下方，也可以在你工作时显示在刘海下方。
- **预览。** 曲目切换时，标题会短暂滑出。
- **播客和长视频**在播放器支持时，提供 15 秒快进快退和倍速按钮（1× 到 2×）。

**🗂️ 高效办事**
- **架子。** 把文件拖到刘海上，之后再拖出来，图片、PDF 和视频还能预览。截图和下载完成的文件可以自动放进来。拖动文件时在任何地方晃动指针，指针旁边就会出现一个小小的放置区域。
- **日历和提醒事项。** 用大号数字显示今天的日期，本周中有日程的日子带一个圆点，还有今天的日程和可以勾选完成的提醒事项。添加到 macOS 的所有账户都能用（Google、iCloud、Exchange 等），显示哪些日历由你决定。
- **即将开始的日程。** 有具体时间的日程开始前 5 分钟，刘海会显示它的标题和还有多久开始。带有 Zoom、Google Meet、Teams、Webex、FaceTime、Whereby 或 Chime 链接的日程，会在主页上出现绿色的“加入”按钮，点按提示即可加入会议。
- **可以取代 Spotlight 或 Raycast 的搜索。** 能搜索应用（包括不在“应用程序”文件夹里的）、文件、系统命令和设置、剪贴板历史、表情符号（以 `:` 开头）以及 `12*(3+4)` 这样的算式，并按你最常打开的程度排序。支持首字母：输入 `vsc` 就能找到 Visual Studio Code。方向键选择，Return 键打开。
- **你的快捷键。** 默认是 <kbd>⇧⌘Space</kbd>，也可以在设置中录制任意组合。如果 macOS 或其他应用已经占用了它，Nunsseop 会告诉你。
- **计时器、剪贴板历史、便笺和表情符号选择器。** 剪贴板历史只保存在内存里，并会跳过密码管理器标记为机密的内容。拷贝链接时，`utm_`、`fbclid` 之类的跟踪参数会被移除。

**💻 你的 Mac**
- **系统 HUD。** 音量、亮度（包括支持 DDC 的外接显示器）、键盘背光、充电、大写锁定和 AirPods 电量都显示在刘海里。它还可以接管音量和亮度键，让系统自带的 HUD 不再出现。
- **系统状态和电量。** CPU、内存、磁盘、网络，以及鼠标、键盘和触控板的电量，电量不足时会提醒。
- **相机和麦克风指示。** 任何应用在使用它们时，刘海上会出现一个圆点。
- **工具。** 切换音频输出、调节每个应用的音量（实验性，需要 macOS 14.2 或更高版本）、麦克风静音、让 Mac 保持唤醒、录制屏幕、推出磁盘、从屏幕上任意位置取色，以及拷贝屏幕上任意区域里的文字。
- **天气、下载、镜子和程序坞应用**，悬停即达。

**📞 收起时也不闲着**
- **通话。** 在 Zoom、FaceTime、Teams、Slack、Discord、WhatsApp 或 Google Meet 通话期间，收起的刘海会显示通话所用的应用和已通话的时长。它根据哪个应用在使用麦克风来判断，所以不需要额外权限。对于 Zoom、FaceTime 和 Meet，你可以直接在刘海上给麦克风静音或关闭相机，不必切换到通话窗口。
- **两侧显示什么，由你决定。** 没有播放内容时，可以显示 Claude Code 或 Codex 的剩余用量、工作中的代理、电池、天气或日期。
- **音乐和计时器。** 播放音乐时显示小小的封面和可视化效果，计时器运行时显示剩余时间。
- **下载。** Safari 或 Chrome 的下载进度以百分比显示，数据来自访达在文件上显示的同一份进度，无需轮询。

**🤖 面向开发者**
- **AI 用量。** 显示 Claude 和 Codex 的用量上限与重置时间，以及过去 5 小时和 7 天的令牌用量，统计范围涵盖 Claude Code、Codex、gjc、omo 和 OpenCode。数据读取自这些工具已经保存在你 Mac 上的文件，所以无需登录任何账户。
- **来自 Claude Code 的 Claude 用量上限。** 在设置 › 服务 › AI 用量中连接 Claude Code 的状态栏。Claude Code 每次回答都会把你的 5 小时和每周用量上限交给它，所以你工作时 AI 标签始终保持最新，Nunsseop 也无需向 Anthropic 请求任何数据。你原来的状态栏照常显示，点按“断开连接”即可恢复原状。
- **实时获取 Claude 用量上限（需手动开启）。** 如果你在别处使用 Claude，AI 标签会询问一次，是否通过 Claude Code 存在钥匙串里的登录信息，大约每小时从 Anthropic 获取一次你的 5 小时和每周 Claude 用量上限。你同意之前保持关闭；之后可在设置 › 服务中更改。以最新的那个来源为准。
- **来自代理和终端的通知。** Claude Code、Codex、Gemini CLI 和 OpenCode 的钩子，Muxy、cmux 和 herdr 中的代理，以及 tmux 和 WezTerm 的响铃，都会显示在刘海里。点按通知，即可把对应的终端、窗格或标签页调到前台（[设置方法见下文](#代理与终端通知)）。
- **通知标签。** 显示最近 30 条来自代理、终端和日历的通知，未读的带有角标；点按某一条就能回到它的来源。默认关闭（设置 › 刘海），且只保存在内存里。
- **工作中的代理。** 收起时的刘海上有一个项目，显示有多少个编程代理在等你（黄色的手）；没有在等你的，则显示有多少个正在工作（绿色的闪电）。目前跟随 herdr，以及通过钩子连接的 Claude Code（在“设置 › 提醒”中连接），用 `claude --bg` 启动的后台会话也会计入。

**🧩 随心定制**
- 自己选择标签及其顺序、顶部栏和收起的刘海显示什么，以及要哪些弹出提示。**关闭的功能就不会再运行。**
- 在 macOS 26 上，展开的刘海和其中的卡片使用 Liquid Glass，背后的内容会柔和地透出来。你可以调节玻璃的深浅，调到 100% 就是纯黑的刘海，也可以直接关闭玻璃效果。
- 在没有刘海的显示器上，收起的刘海是菜单栏里的一个小胶囊，也可以做成玻璃质感，上面是眉毛，一道白色的笔触。指针移到上面时眉毛会抬起。闲置一段时间后（3 到 60 秒，或者永不），眉毛会像闭上的眼睛一样落下并淡出，指针移到那里时又会回来；停留半秒就会展开，并贴在屏幕顶部。在这样的屏幕上，HUD、通知、歌词和预览都显示为一行，图标紧挨着电平条、百分比或文字。空闲显示只开一侧时，胶囊只按那个值的宽度伸长，值就紧挨着眉毛。
- 可以选择显示器、尺寸和悬停延迟，设置登录时打开，以及在合上盖子时隐藏刘海。
- 向下轻扫展开，向上轻扫收起，在主页左右轻扫切换曲目。
- 支持 English、한국어、日本語、简体中文、Español、Deutsch 和 Français，并跟随你的 Mac 设置。

## 常见问题

<details>
<summary><b>macOS 提示无法打开 Nunsseop。</b></summary>

这个应用还没有经过公证，所以请用 Homebrew 安装（`brew install --cask namekun/tap/nunsseop`）。Homebrew 会清除隔离属性，应用可以直接打开。
</details>

<details>
<summary><b>播放音乐时什么都没有显示。</b></summary>

Nunsseop 显示的是 macOS 列为“正在播放”的内容，所以播放器必须出现在控制中心里。大多数应用和浏览器都可以。备用方案请参阅[“正在播放”的工作原理](#正在播放的工作原理)。
</details>

<details>
<summary><b>搜索能取代 Spotlight 吗？</b></summary>

可以。打开设置 → 服务，点按快捷键并按下 <kbd>⌘Space</kbd>。Nunsseop 会提示 Spotlight 正在使用它，并打开键盘快捷键，你在那里取消勾选*显示“聚焦”搜索*即可。即使搜索标签被隐藏，搜索也能打开。
</details>

<details>
<summary><b>标签太多了。</b></summary>

右键点按刘海 → 设置 → 刘海，关掉你不需要的。关闭的功能会完全停止运行。
</details>

<details>
<summary><b>我的 Mac 没有刘海。</b></summary>

在没有刘海的显示器上（比如合上盖子使用的外接显示器），收起的刘海是浮在菜单栏里的一个小胶囊，上面是眉毛，一道白色的笔触。指针移到上面时眉毛会抬起，展开后刘海会以常规尺寸贴在屏幕顶部。HUD、通知、歌词和预览会显示为一行，而不是环绕摄像头。闲置时，眉毛会像闭上的眼睛一样落下，胶囊随之淡出；你可以在设置里关闭这一行为或更改延迟，也可以在那里选择它使用哪个显示器。
</details>

<details>
<summary><b>为什么 AI 用量显示的是旧的 Claude 用量上限？</b></summary>

默认情况下，Claude 的 5 小时和每周百分比来自其他工具写入的缓存：在终端里使用 Claude Code 时来自 [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) 的 HUD，或者来自 gjc。卡片上会显示它们上次更新的时间。想让用量上限保持最新，请在设置 › 服务 › AI 用量中连接 Claude Code 的状态栏：Claude Code 每次回答都会把用量上限交给它，而你自己的状态栏也照常工作。如果你在别处使用 Claude，请改为在 AI 标签或设置 › 服务中开启实时获取 Claude 用量上限。以最新的那个来源为准。令牌总数始终是实时的。
</details>

<details>
<summary><b>更新后，音量键不再显示 Nunsseop 的 HUD 了。</b></summary>

0.8.3 之前的版本使用的签名方式，会让 macOS 在每次更新后忘记辅助功能权限。从 0.8.3 起，这个权限会被保留。如果你是从旧版本升级的，请先在系统设置 → 隐私与安全性 → 辅助功能中移除 Nunsseop，然后重新允许一次；无需重启即可生效。
</details>

## 代理与终端通知

Nunsseop 在 `127.0.0.1:47750` 上监听来自 Mac 上各种工具的通知。请求必须带有保存在 `~/Library/Application Support/Nunsseop/notify-token` 中的密钥令牌。

打开设置 → 提醒，点按 Claude Code、Codex、Gemini CLI 或 OpenCode 旁边的**连接**。这里只会列出你在这台 Mac 上用过的工具。Nunsseop 会修改该工具的设置文件（`~/.claude/settings.json`、`~/.codex/config.toml`、`~/.gemini/settings.json`），或在 `~/.config/opencode/plugins` 中添加一个插件，并以 `.nunsseop-backup` 扩展名保留原文件。Codex 只允许一条 `notify` 命令，所以已有的那条会排在 Nunsseop 的之后继续运行。点按**断开连接**即可撤销。之后启动的会话会把通知发送到刘海。

如果想手动设置 Claude Code，请点按**拷贝 Claude Code 钩子命令**，然后把它添加到 `~/.claude/settings.json`：

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "<paste the copied command here>" }] }
    ]
  }
}
```

终端和代理应用不需要钩子：

- **Muxy** 和 **cmux：** 直接从应用读取它们自己的通知，应用位于前台时不显示。
- **herdr：** 所有会话中完成任务或等待输入的代理，都从 herdr 的套接字读取。
- **tmux：** 任何窗口的响铃。Nunsseop 只会向正在运行的 tmux 服务器添加钩子，不会修改 `tmux.conf`。
- **WezTerm：** 响铃，通过你从设置 › 提醒中拷贝并粘贴到 `~/.wezterm.lua` 里的几行配置实现。

它们在设置 › 提醒下各有一个开关（WezTerm 是一个用来拷贝配置行的按钮），并且只有在安装了对应工具时才会显示。已经通过自己的钩子连接的工具不会重复显示。

任何脚本也都可以发送通知：

```sh
curl -X POST http://127.0.0.1:47750/notify \
  -H "Authorization: Bearer $(cat ~/Library/Application\ Support/Nunsseop/notify-token)" \
  -d '{"title": "Build", "message": "Finished in 42 s"}'
```

## 权限

Nunsseop 只会在你第一次使用某项功能、而它需要权限时才会请求。

| 功能 | 权限 | 何时请求 |
| --- | --- | --- |
| 日历 | 日历 | 在主页标签点按*允许访问*时 |
| 提醒事项 | 提醒事项 | 在主页标签点按*允许提醒事项*时 |
| 镜子 | 相机 | 在镜子标签点按*允许相机*时 |
| 屏幕录制，以及拷贝其他应用窗口中的文字 | 屏幕录制 | 第一次开始录制或提取文本时 |
| 带声音的录制 | 麦克风 | 第一次在开启麦克风音频的情况下录制时 |
| 接管音量、亮度和键盘背光键 | 辅助功能 | 在设置中开启该选项时 |
| “音乐”、Spotify 和浏览器的备用正在播放方案 | 自动化 | 仅在 MediaRemote 辅助库不可用时 |
| 显示浏览器中的 Google Meet、Zoom 和 Teams 通话 | 自动化（该浏览器） | 浏览器第一次使用麦克风时 |
| 登录时打开 | 登录项 | 在设置中开启时 |

## 隐私

Nunsseop 不会收集或发送个人数据。它只会在以下情况下联网：

- 每天向 `api.github.com` 检查一次是否有新版本（可以关闭）；
- 到 `lrclib.net` 查找同步歌词（可以关闭）；
- 从 `open-meteo.com` 获取你输入的城市的天气（输入城市之前保持关闭），当 Open-Meteo 找不到该城市时，会向 Apple 的地理编码服务查询城市的位置；
- 通过 HTTPS 从已知的音乐服务下载封面，仅在 MediaRemote 辅助库不可用时；
- 大约每小时向 `api.anthropic.com` 查询一次你的 Claude 用量上限，使用钥匙串中 Claude Code 的登录信息，仅在你开启实时获取 Claude 用量上限时。

其余一切都留在你的 Mac 上。通知服务器只接受来自这台 Mac 的连接。AI 用量读取自本地文件，包括 Claude Code 状态栏保存在这台 Mac 上的用量上限，除非你开启实时获取 Claude 用量上限。通知标签中的通知只保存在内存里。录制的视频保存在截图所在的位置。相机预览只在镜子标签打开时运行，也绝不会被录制。Nunsseop 退出时，剪贴板历史会被清除。

## 正在播放的工作原理

从 macOS 15.4 起，私有的 MediaRemote 框架只响应由 Apple 签名的进程。Nunsseop 自带一个小型辅助库（`Sources/NowPlayingHelper`），它运行在系统的 `/usr/bin/perl` 里，读取“正在播放”的状态，发送播放、暂停、跳转和拖动进度的命令，并以 JSON 行的形式把数据流式传回应用。

这依赖私有 API，所以未来的 macOS 更新可能会让它失效。如果发生这种情况，Nunsseop 会对“音乐”和 Spotify 改用 AppleScript，对浏览器则改为读取媒体标签页。这种备用方案需要在每个浏览器中打开*允许来自 Apple 事件的 JavaScript*。Dia 没有对应的菜单项，所以 Nunsseop 会提议带上 `--enable-applescript-javascript` 重新启动它。

## 从源码构建

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release      # build/Nunsseop.app
./scripts/make-dmg.sh            # build/Nunsseop-<version>.dmg
```

你需要安装 Xcode 命令行工具，并且 Swift 版本为 5.10 或更高。`scripts/bundle.sh` 会构建 Swift 包，并把它封装成使用临时签名（ad-hoc）的应用包。

## 许可证

[MIT](LICENSE)。欢迎提交 Issue 和 Pull Request。
