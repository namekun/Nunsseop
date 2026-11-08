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
  <img src="docs/images/home.png" width="720" alt="展开的刘海，显示正在播放的内容、日历和天气">
</p>

*Nunsseop*（눈썹）在韩语里是*眉毛*的意思，也就是屏幕上方那道小小的弧线。它免费、开源，无需账户，没有订阅，也不做任何跟踪。

## 30 秒安装

**[下载 Nunsseop.dmg](https://github.com/namekun/Nunsseop/releases/latest/download/Nunsseop.dmg)**，打开后把 Nunsseop 拖到“应用程序”中。应用已经过 Apple 签名和公证，可以直接打开。有新版本时，设置 › 通用 › 更新中的“安装更新”会先展示新内容，安装后重新启动 Nunsseop（早于 0.38.0 的版本需要再下载一次新的 DMG）。

也可以用 [Homebrew](https://brew.sh) 安装：

```sh
brew install --cask namekun/tap/nunsseop
```

要更新，请运行 `brew update && brew upgrade --cask nunsseop`；有新版本时，设置 › 通用 › 更新中的“拷贝更新命令”会把这条命令拷贝到剪贴板。

需要 macOS 14 Sonoma 或更高版本。支持搭载 Apple 芯片的 Mac（不支持 Intel），也支持没有刘海的屏幕。

## 上手第一分钟

1. **把指针移到刘海上。** 它会展开；指针移开后，它会自动收回。
2. **在“音乐”、Spotify、YouTube Music 或任意浏览器里播放点什么。** 刘海会自动识别，收起时还会显示一个小小的封面和可视化效果。
3. **右键点按刘海 → 设置**，选择要用的标签、它们的顺序、想看的弹出提示以及尺寸。

没有程序坞图标。Nunsseop 就住在刘海里。

首次安装后，刘海会在一秒后自行展开，并带你走完四个简短的步骤：它如何展开和收起、各个标签、拖放文件与搜索，以及连接在这台 Mac 上找到的代理工具（没找到时则是“一切就绪”）。“跳过”、Esc 或“完成”都能结束它，在“设置 › 通用 › 再次显示新手引导”中可以重新播放。更新后会自动打开一次，介绍这个版本的新变化，之后就不再打扰。

## 功能一览

| | |
| :---: | :---: |
| <img src="docs/images/tab-search.png" alt="搜索，显示一个应用、一条命令和一项设置"><br>**搜索。** 一个可以查找应用、文件、命令、剪贴板、表情符号和算式的启动器，快捷键随你定。 | <img src="docs/images/tab-ai.png" alt="Claude Code 和 Codex 的 AI 用量"><br>**AI 用量。** Claude Code 和 Codex 的用量上限，无需登录。 |
| <img src="docs/images/shelf.png" alt="文件架子，显示所选文件的详情和隔空投送按钮"><br>**架子。** 把文件暂放在刘海里，或直接拖到隔空投送上。 | <img src="docs/images/tab-timer.png" alt="计时器标签"><br>**计时器。** 倒计时、番茄钟和秒表，时长随意设置。 |
| <img src="docs/images/tab-tools.png" alt="工具标签"><br>**工具。** 音频输出、麦克风静音、保持唤醒、屏幕录制、取色器和文本提取。 | <img src="docs/images/tab-system.png" alt="系统标签，显示设备电量"><br>**系统。** CPU、内存、磁盘、网络和设备电量。 |
| <img src="docs/images/tab-emoji.png" alt="带分类列表的表情符号选择器"><br>**表情符号。** 左侧是分类列表，所有表情符号都能搜索，点一下即可拷贝。 | <img src="docs/images/hud-headphones.png" alt="耳机电量 HUD"><br>**HUD。** 音量、亮度、AirPods 电量等等。 |
| <img src="docs/images/collapsed-call.png" alt="Zoom 通话期间收起的刘海"><br>**通话。** 显示通话所用的应用和已通话的时长。 | <img src="docs/images/collapsed-idle.png" alt="收起的刘海，显示 Claude Code 剩余用量和天气"><br>**一目了然。** 自己选择收起的刘海两侧各显示什么。 |

## 全部功能

**🎵 音乐**
- **任意应用的正在播放内容。** 支持“音乐”、Spotify、YouTube Music，以及 Safari、Chrome、Arc、Dia、Aside 等浏览器。有封面、播放控制，进度条还可以拖动。
- **同步歌词**来自 [LRCLIB](https://lrclib.net)，可以显示在标题下方，也可以在你工作时显示在刘海下方。
- **预览。** 曲目切换时，标题会短暂滑出。
- **播客和长视频**在播放器支持时，提供 15 秒快进快退和倍速按钮（1× 到 2×）。

**🗂️ 高效办事**
- **架子。** 把文件拖到刘海上，之后再拖出来，图片、PDF 和视频还能预览，缩略图会随架子的高度变大。截图和下载完成的文件可以自动放进来。拖动文件时在任何地方晃动指针，指针旁边就会出现一个小小的放置区域。
- **日历和提醒事项。** 用大号数字显示今天的日期，本周中有日程的日子带一个圆点，还有今天的日程和可以勾选完成的提醒事项。添加到 macOS 的所有账户都能用（Google、iCloud、Exchange 等），显示哪些日历由你决定。
- **即将开始的日程。** 有具体时间的日程开始前 5 分钟，刘海会显示它的标题和还有多久开始。带有 Zoom、Google Meet、Teams、Webex、FaceTime、Whereby 或 Chime 链接的日程，会在主页上出现绿色的“加入”按钮，点按提示即可加入会议。
- **可以取代 Spotlight 的搜索。** 能搜索应用（包括不在“应用程序”文件夹里的）、文件、系统命令和设置、剪贴板历史、表情符号（以 `:` 开头）以及 `12*(3+4)` 这样的算式，并按你最常打开的程度排序。支持首字母：输入 `vsc` 就能找到 Visual Studio Code。方向键选择，Return 键打开。
- **你的快捷键。** 搜索默认用 <kbd>⇧⌘Space</kbd> 打开，也可以录制任意组合。设置 › 通用 › 快捷键里还有一些起初为空的操作：前往等得最久的代理（它的终端会调到前台）、打开代理标签、前往最近一条通知的来源、打开或关闭刘海。已被其他操作占用的组合不会保存；如果 macOS 或其他应用已经占用了它，Nunsseop 会告诉你。
- **计时器、剪贴板历史、便笺和表情符号选择器。** 剪贴板历史只保存在内存里，并会跳过密码管理器标记为机密的内容。拷贝链接时，`utm_`、`fbclid` 之类的跟踪参数会被移除。
- **列表旁的详情。** 架子、剪贴板、应用、搜索和通知标签会在右侧显示指针下的项目（或用 ↑ ↓ 选中的项目）及其操作。点一下某一行仍会立即拷贝、打开或跳回来源。

**💻 你的 Mac**
- **系统 HUD。** 音量、亮度（包括支持 DDC 的外接显示器）、键盘背光、充电、大写锁定和 AirPods 电量都显示在刘海里。它还可以接管音量和亮度键，让系统自带的 HUD 不再出现。
- **系统状态和电量。** CPU、内存、磁盘、网络和这台 Mac 的电量以面板显示，另有鼠标、键盘和触控板的电量，电量不足时会提醒。
- **相机和麦克风指示。** 任何应用在使用它们时，刘海上会出现一个圆点。
- **工具。** 切换音频输出、调节每个应用的音量（实验性，需要 macOS 14.2 或更高版本）、麦克风静音、让 Mac 保持唤醒、录制屏幕、推出磁盘、从屏幕上任意位置取色，以及拷贝屏幕上任意区域里的文字。
- **天气、下载、镜子和程序坞应用**，悬停即达。天气在主页最下面一行。

**📞 收起时也不闲着**
- **通话。** 在 Zoom、FaceTime、Teams、Slack、Discord、WhatsApp 或 Google Meet 通话期间，收起的刘海会显示通话所用的应用和已通话的时长。它根据哪个应用在使用麦克风来判断，所以显示桌面应用的通话不需要权限；浏览器中的通话（Meet，以及网页版 Zoom、Teams）则需要对该浏览器的自动化权限。对于 Zoom、FaceTime 和 Meet，你可以直接在刘海上给麦克风静音（Zoom 和 Meet 还能关闭相机），不必切换到通话窗口；Zoom 和 FaceTime 需要辅助功能权限，Meet 需要在 Chromium 内核的浏览器中打开*允许来自 Apple 事件的 JavaScript*。
- **两侧显示什么，由你决定。** 没有播放内容时，可以显示 Claude Code 或 Codex 的剩余用量、工作中的代理、电池、天气或日期。
- **音乐和计时器。** 播放音乐时显示小小的封面和可视化效果，计时器运行时显示剩余时间。计时器、通话和下载会让两侧各自贴合自己的内容，单个图标旁不会留出大片空白。
- **下载。** Safari 或 Chrome 的下载进度以百分比显示，数据来自访达在文件上显示的同一份进度，无需轮询。

**🤖 面向开发者**
- **AI 用量。** 显示 Claude 和 Codex 的用量上限与重置时间，以及过去 5 小时和 7 天的令牌用量，统计范围涵盖 Claude Code、Codex、gjc、omo 和 OpenCode。数据读取自这些工具已经保存在你 Mac 上的文件，所以无需登录任何账户。用量上限达到 70% 时会变成橙色，并带上“!”。
- **来自 Claude Code 的 Claude 用量上限。** 在设置 › 服务 › AI 用量中连接 Claude Code 的状态栏。Claude Code 每次回答都会把你的 5 小时和每周用量上限交给它，所以你工作时 AI 标签始终保持最新，Nunsseop 也无需向 Anthropic 请求任何数据。你原来的状态栏照常显示，点按“断开连接”即可恢复原状。如果无法恢复你之前的命令，设置里会提示。
- **实时获取 Claude 用量上限（需手动开启）。** 如果你在别处使用 Claude，AI 标签会询问一次，是否通过 Claude Code 存在钥匙串里的登录信息，大约每小时从 Anthropic 获取一次你的 5 小时和每周 Claude 用量上限。该登录信息会在 Claude Code 运行时续期，所以一段时间没用后，AI 标签会提示你运行 Claude Code，而不是重新登录。你同意之前保持关闭；之后可在设置 › 服务中更改。以最新的那个来源为准；如果它不含套餐和各模型的用量条，则沿用之前的。
- **限额提醒。** Claude 或 Codex 的 5 小时或每周限额超过 80% 和 95% 时各提醒一次，用到这个程度的限额重置后也会告诉你。默认开启，可在设置 → 提醒 → AI 用量中关闭。
- **来自代理和终端的通知。** Claude Code、Codex、Gemini CLI、GitHub Copilot、Antigravity、Cursor 和 OpenCode 的钩子，omp、omo 和 pi 的扩展，Hermes 和 Amp 的插件，Muxy 2、cmux、herdr 和 Paseo 中的代理，以及 tmux 和 WezTerm 的响铃，都会显示在刘海里。点按通知，即可把对应的终端、窗格或标签页调到前台（[设置方法见下文](#代理与终端通知)）。
- **权限请求与提问。** Claude Code 请求运行或编辑时，可直接在刘海里选择允许、拒绝或始终允许；当 Claude Code 建议了规则，或者是不含通配符和连接符的简单 shell 命令（此时规则只允许这一条命令）时，会出现“始终允许”；两种情况下规则都必须仅由普通键盘字符（可打印 ASCII）组成且能放进卡片。卡片会显示工具、文件夹和每个字段；如果文本中有可能被当作英文字母或符号的字符，会用橙色的“异常字符”标签提醒。Codex 的命令、文件编辑（`apply_patch` 会列出涉及的文件）和 MCP 工具审批也一样处理，只是不再有“始终允许”，改为“在终端中回答”。OpenCode 的权限请求同样处理，Paseo 的工具审批也一样，只是把“在终端中回答”换成“在 Paseo 中回答”。GitHub Copilot、Antigravity（命令和文件写入）以及 Cursor（shell 命令和 MCP 调用）的审批也一样处理，Cursor 的按钮是“在 Cursor 中回答”。只要对要执行的内容有一丝疑问（例如在沙盒之外运行的 Cursor shell 命令），就不会显示卡片，由工具在自己的提示里询问。Gemini CLI、Hermes 和 Amp 只显示会话和通知，不处理审批。Claude Code 的提问也能回答：选一个或多个答案，有多个问题时逐个翻过去，或点“在终端中回答”交还给终端；无法如实显示答案的问题会留在终端里。先在终端里回应，卡片就会消失。请求的内容只保存在内存中（可在“设置 › 提醒”中关闭）。如果该代理的终端就在最前面，你已经在看它了，请求就留在终端里询问，不在刘海中显示（设置 › 提醒）。
- **通知标签。** 显示最近 30 条来自代理、终端和日历的通知，未读的带有角标；点按某一条就能回到它的来源。默认关闭（设置 › 刘海），且只保存在内存里。
- **眉毛表情。** 眉毛用表情告诉你代理的状态：有代理在等你时眉梢扬起，工作中时压低放平。代理结束一轮时眉毛会跳两下，刘海告诉你是哪个代理完成了（如果它的终端已在最前面则不提示；设置 › 提醒）。Claude 或 Codex 的额度快用完时眉毛耷拉下来，额度重置后又扬起。没有刘海的屏幕上，应用本身的眉毛会做表情；有刘海的屏幕上，代理数量旁会出现一个小眉毛，代理和额度的提醒图标也是眉毛。开启“减弱动态效果”时它保持不动。
- **工作中的代理。** 收起时的刘海上有一个项目，显示有多少个编程代理在等你（扬起的眉毛和黄色数字）；没有在等你的，则显示有多少个正在工作（压低放平的眉毛和绿色数字）。Claude Code、Codex、Gemini CLI、OpenCode、GitHub Copilot、Antigravity、Cursor、Hermes、Amp、omp、omo 和 pi 通过钩子、插件或扩展跟随（在“设置 › 提醒”中连接；Codex 下次启动时会询问是否信任这些钩子），gjc、herdr、Muxy 2 和 Paseo 则无需连接，用 `claude --bg` 启动的后台会话也会计入。当 Claude Code 结束一轮时仍有子代理或后台 shell 命令在运行，该会话最长两小时内仍算作工作中，并在代理标签里带上“后台 · N 个任务”标签。
- **代理标签。** 每个正在工作或在等你的编程代理会话占一行，包括 Claude Code、Codex、Gemini CLI、OpenCode、GitHub Copilot、Antigravity、Cursor、Hermes、Amp、omp、omo、pi、gjc、Paseo，以及在 herdr 和 Muxy 2 中运行的代理。状态既靠颜色也靠形状区分：在等你时是实心的橙色圆点，工作中是转动的绿色圆弧，空闲时是空心圆环。接着是名称（Claude Code 的 `/rename` 名称或其自带标题，Codex 的线程名）、文件夹、工具和模型、权限模式非默认时的标签、带令牌数的小型上下文量表，以及进入该状态后过去的时间。每一行都有“前往终端”（Paseo 的行是“在 Paseo 中打开”）和“消息”按钮；虚线按钮表示现在不能用，悬停提示会说明原因。在等你的会话会展开，并显示“在终端中回答”。底部一行汇总各状态的数量（“1 个等待中 · 3 个运行中 · 1 个空闲”）。键盘：↑↓ 选择，↵ 前往终端，⌘M 打开消息输入框；双击某一行也会前往它的终端。最近 3 小时内用过的已打开会话会以暗淡的“空闲”显示（收起的刘海不计入）。没有任何会话打开时，“最近”会列出最多 5 个过去一周内未打开的对话，点按或按 ↵ 即可在“设置 › 提醒”中选定的终端里恢复（`claude --resume`、`codex resume`，或各工具自己的参数）。只从这台 Mac 上工具自己的会话文件里读取文件夹、模型、令牌数、权限模式、会话名称和最近一条提示。 工作中或已结束一轮的会话下方会显示最近一步：读取或修改的文件、运行的命令、提出的问题。修改会显示 +N −M 和 **查看差异**，点击后在列表位置显示改动的行（← → 查看本轮其他修改，Esc 返回）。当标签里显示有工作中的会话时，每 2 秒检查一次会话文件。
- **给会话发消息，把文件拖给它。** 点按某一行的“消息”按钮（或按 ⌘M），底部一行会变成以该会话为“收件人”的输入框；按 Return 会把文字送进该会话的输入并回车，按 Esc 取消。把“架子”或访达里的文件拖到某一行上，它们的路径会被输入进去，但不会回车；从“架子”拖动时，把指针停在代理标签按钮上即可切换过去。在 Ghostty、Terminal、iTerm2、WezTerm、kitty、cmux、herdr、Muxy 2 和 Orca 的会话中可用（Terminal 只收消息，不接受文件）；Paseo 只能给不在工作的代理发消息（见下文“各终端支持什么”的表格）。可能有权限请求或提问尚未处理时、会话位于 tmux、zellij 或 screen 里时，以及无法确认会话所在的终端时，都不会发送任何内容。
- **每周回顾。** 每周第一次打开刘海时（周一及之后），会出现一张“上周，眉毛看到的一切”卡片，显示代理的工作时长（并与前一周对比）、各工具的会话数、修改的行数（+/−）和文件数、各工具的令牌数、工作最多的项目及其占比、最长的会话，以及最忙的一天（柱状条）。数据只在这台 Mac 上根据 Claude Code、Codex、omo、gjc、omp、pi 和 OpenCode 的会话文件统计，不会发送到任何地方；由程序通过 Agent SDK 启动的会话不计入。**保存图片**会把隐去项目名称的 1080×1920 PNG 写入“下载”文件夹。随时可以在 AI 用量标签的“上周”里重新打开。默认开启，可在设置 › 提醒 › AI 用量中关闭。

**🧩 随心定制**
- 所有标签都放在顶部栏的一行里，当前标签会在胶囊中显示名称。在有刘海的屏幕上，这一行位于摄像头左侧，放不下时可以滚动。主页、计时器、工具、系统和 AI 用量是带大号数字和细条的面板。设置带有侧边栏，“刘海”页里的标签列表是可以拖动排序的两列网格。
- 自己选择标签并拖动排序、顶部栏是否显示日期、收起的刘海显示什么，以及要哪些弹出提示。**关闭的功能就不会再运行。**
- 在 macOS 26 上，展开的刘海和其中的卡片使用 Liquid Glass，背后的内容会柔和地透出来。你可以调节玻璃的深浅，调到 100% 就是纯黑的刘海，也可以直接关闭玻璃效果。
- 在没有刘海的显示器上，收起的刘海是菜单栏里的一个小胶囊，也可以做成玻璃质感，上面是眉毛，一道白色的笔触。指针移到上面时眉毛会抬起。闲置一段时间后（3 到 60 秒，或者永不），眉毛会像闭上的眼睛一样落下并淡出，指针移到那里时又会回来；停留半秒就会展开，并贴在屏幕顶部。除非设为永不，在全屏应用中即使正在显示音乐、计时器或通话，它也会在一秒内淡出，不会挡住视频或幻灯片；HUD、通知和权限请求照常显示。在这样的屏幕上，HUD、通知、歌词和预览都显示为一行，图标紧挨着电平条、百分比或文字。空闲显示让胶囊两侧各按自己的值伸长，值紧挨着眉毛，眉毛始终在摄像头上方。
- 可以选择显示器、尺寸和悬停延迟，设置登录时打开，以及在合上盖子时隐藏刘海。设为自动时，收起的刘海会跟着指针移到另一台显示器；关闭这一项则停留在同一块屏幕上。打开调度中心（Mission Control）时会隐藏。
- 向下轻扫展开，向上轻扫收起，在主页左右轻扫切换曲目。
- 支持 English、한국어、日本語、简体中文、Español、Deutsch 和 Français，并跟随你的 Mac 设置。

## 常见问题

<details>
<summary><b>macOS 提示无法打开 Nunsseop。</b></summary>

从 0.37.0 起，应用经过 Apple 签名和公证，可以像其他应用一样打开。更早的版本还没有公证：请重新[下载最新的 DMG](https://github.com/namekun/Nunsseop/releases/latest/download/Nunsseop.dmg)，或用 Homebrew 更新（`brew update && brew upgrade --cask nunsseop`）。
</details>

<details>
<summary><b>在带灵动岛的 MacBook Pro 上能用吗？</b></summary>

应该可以，但我们还没有真机可以测试。灵动岛由系统绘制，所以眉毛会停在它旁边而不是盖在上面，把指针移上去后和平时一样打开。如果你有这台 Mac，请运行 `/Applications/Nunsseop.app/Contents/MacOS/Nunsseop --print-screen-info`，并把输出通过 [Issue](https://github.com/namekun/Nunsseop/issues) 发给我们，我们会据此调整。
</details>

<details>
<summary><b>播放音乐时什么都没有显示。</b></summary>

Nunsseop 显示的是 macOS 列为“正在播放”的内容，所以播放器必须出现在控制中心里。大多数应用和浏览器都可以。备用方案请参阅[“正在播放”的工作原理](#正在播放的工作原理)。
</details>

<details>
<summary><b>搜索能取代 Spotlight 吗？</b></summary>

可以。打开设置 → 通用，点按快捷键并按下 <kbd>⌘Space</kbd>。Nunsseop 会提示 Spotlight 正在使用它，并打开键盘快捷键，你在那里取消勾选*显示“聚焦”搜索*即可。即使搜索标签被隐藏，搜索也能打开。
</details>

<details>
<summary><b>标签太多了。</b></summary>

右键点按刘海 → 设置 → 刘海，关掉你不需要的。关闭的功能会完全停止运行。
</details>

<details>
<summary><b>我的 Mac 没有刘海。</b></summary>

在没有刘海的显示器上（比如合上盖子使用的外接显示器），收起的刘海是浮在菜单栏里的一个小胶囊，上面是眉毛，一道白色的笔触。指针移到上面时眉毛会抬起，展开后刘海会以常规尺寸贴在屏幕顶部。HUD、通知、歌词和预览会显示为一行，而不是环绕摄像头。闲置时，眉毛会像闭上的眼睛一样落下，胶囊随之淡出；你可以在设置里关闭这一行为或更改延迟。有多个显示器时，收起的刘海会在完全收起后移到指针所在的显示器，HUD、权限请求和预览也会显示在那里；在设置里选定一个显示器，它就会固定在该显示器上。
</details>

<details>
<summary><b>为什么 AI 用量显示的是旧的 Claude 用量上限？</b></summary>

默认情况下，Claude 的 5 小时和每周百分比来自其他工具写入的缓存：在终端里使用 Claude Code 时来自 [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) 的 HUD，或者来自 gjc。卡片上会显示它们上次更新的时间。想让用量上限保持最新，请在设置 › 服务 › AI 用量中连接 Claude Code 的状态栏：Claude Code 每次回答都会把用量上限交给它，而你自己的状态栏也照常工作。如果你在别处使用 Claude，请改为在 AI 标签或设置 › 服务中开启实时获取 Claude 用量上限。以最新的那个来源为准；如果它不含套餐和各模型的用量条，则沿用之前的。令牌总数始终是实时的。
</details>

<details>
<summary><b>更新后，音量键不再显示 Nunsseop 的 HUD 了。</b></summary>

0.8.3 之前的版本使用的签名方式，会让 macOS 在每次更新后忘记辅助功能权限。从 0.8.3 起，这个权限会被保留。如果你是从旧版本升级的，请先在系统设置 → 隐私与安全性 → 辅助功能中移除 Nunsseop，然后重新允许一次；无需重启即可生效。
</details>

## 代理与终端通知

Nunsseop 在 `127.0.0.1:47750` 上监听来自 Mac 上各种工具的通知。请求必须带有保存在 `~/Library/Application Support/Nunsseop/notify-token` 中的密钥令牌。

打开设置 → 提醒，点按 Claude Code、Codex、Gemini CLI、GitHub Copilot、Antigravity、Cursor、OpenCode、Hermes、Amp、omp、omo 或 pi 旁边的**连接**。这里只会列出你在这台 Mac 上用过的工具。Nunsseop 会修改该工具的设置文件（`~/.claude/settings.json`、`~/.codex/config.toml`、`~/.codex/hooks.json`、`~/.gemini/settings.json`），或在 `~/.config/opencode/plugins` 中添加一个插件，或在 `~/.omp/agent/extensions` 中添加一个小扩展（omo、pi 分别是 `~/.omo`、`~/.pi`），并以 `.nunsseop-backup` 扩展名保留原文件。 写入任何内容之前，会弹出面板展示该文件将如何变化（新增的行为绿色，删除的行为红色，没有变化的部分折叠起来），并说明保留的是哪份备份；**取消**则不会写入任何内容。如果该文件与其他工具共用（Claude Code、Codex、Gemini CLI、Antigravity 和 Cursor），你原有的钩子保持不变，**断开连接**时只会移除 Nunsseop 的。Codex 只允许一条 `notify` 命令，所以已有的那条会排在 Nunsseop 的之后继续运行。点按用于统计工作中代理的钩子会与其他工具的钩子并列写入 `~/.codex/hooks.json`；Codex 下次启动时会询问是否信任它们（选择“Review hooks”可只信任 Nunsseop 的钩子，“Trust all and continue”会信任所有工具的新钩子），在此之前不会运行；更新改变了钩子的文字后，它会再次询问。用于在刘海里回应审批的钩子也要同样信任；之前已连接过的话，Codex 会再询问一次，请在 /hooks 中查看。 **断开连接**即可撤销。之后启动的会话会把通知发送到刘海。gjc 无需连接：在工作中代理数或代理标签显示期间，会直接从它自己的文件里读取会话。

GitHub Copilot 会得到专属的钩子文件 `~/.copilot/hooks/nunsseop.json`；Antigravity（`agy` 命令行）会在 `~/.gemini/config/hooks.json` 中添加一项，Cursor 会在 `~/.cursor/hooks.json` 中添加几项，都与其他工具的钩子并列。Hermes 和 Amp 会得到 Nunsseop 的插件（`~/.hermes/plugins/nunsseop`、`~/.config/amp/plugins/nunsseop.ts`）。Hermes 只有在你于终端里运行一次 `hermes plugins enable nunsseop` 后才会加载插件；设置里会显示这条命令，以及 Hermes 中是否已启用。Amp 的插件 API 仍属实验性质，Amp 更新后可能会失效。连接后，Gemini CLI、GitHub Copilot、Antigravity、Cursor、Hermes 和 Amp 会把会话报告给代理数量和代理标签，并在一轮结束时发送通知。GitHub Copilot、Antigravity 和 Cursor 的审批，只有在“设置 › 提醒”中开启“在刘海中回应权限请求和提问”时才会显示在刘海里。

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

- **Muxy 2：** 在 Muxy 运行期间，用 `muxy activity list` 读取 Muxy 自己识别出的代理。它们会以通知显示（Muxy 位于前台时不显示），只有 Muxy 知道的会话则在工作或等待期间出现在代理标签里。过去使用通知文件和套接字的 Muxy 1 不再支持。
- **cmux：** 通过应用内的 cmux 命令读取它自己的通知，cmux 位于前台时不显示。
- **herdr：** 所有会话中完成任务或等待输入的代理，都从 herdr 的套接字读取。
- **Paseo：** 完成或失败的代理，读取自 Paseo 自己的记录文件，所以没有守护进程也会显示。审批卡片和它的事件需要这台 Mac 上无需密码即可运行的守护进程，Nunsseop 绝不会启动它。
- **tmux：** 任何窗口的响铃。Nunsseop 只会向正在运行的 tmux 服务器添加钩子，不会修改 `tmux.conf`。
- **WezTerm：** 响铃，通过你从设置 › 提醒中拷贝并粘贴到 `~/.wezterm.lua` 里的几行配置实现。

它们在设置 › 提醒下各有一个开关（WezTerm 是一个用来拷贝配置行的按钮），并且只有在安装了对应工具时才会显示。已经通过自己的钩子连接的工具不会重复显示。Orca 自己没有通知来源：它的会话只会通过上面连接的钩子和扩展（Claude Code、Codex、OpenCode、pi 等）出现，由它们发来 Orca 窗格的 ID。

任何脚本也都可以发送通知：

```sh
# notify-auth 里存的就是 Authorization 请求头，所以令牌不会出现在进程列表里。
curl -X POST http://127.0.0.1:47750/notify \
  -H @"$HOME/Library/Application Support/Nunsseop/notify-auth" \
  -d '{"title": "Build", "message": "Finished in 42 s"}'
```

### 各终端支持什么

某一行的“前往终端”“消息”按钮以及拖入文件，只在 Nunsseop 能确定该会话位于哪个终端时才可用：它会检查会话的进程确实在那个终端里运行。文字通过终端自己的输入 API 送入，绝不会模拟按键。消息或拖入文件做不到时，按钮会变成虚线，悬停提示会说明原因（中间隔着 tmux、zellij 或 screen；有请求在等待回答；同一文件夹里有多个 Ghostty 标签页；等等）；这时“前往终端”仍会把终端应用带到前台。

| 终端 | 前往其标签页或窗格 | 消息 | 拖入文件 | 从“最近”恢复 |
| --- | :---: | :---: | :---: | :---: |
| Ghostty | ✓¹ | ✓¹ | ✓¹ | ✓ |
| Terminal | ✓ | ✓ | — | ✓ |
| iTerm2 | ✓ | ✓ | ✓ | ✓ |
| WezTerm | ✓ | ✓ | ✓ | ✓ |
| kitty | ✓ | ✓ | ✓ | ✓ |
| cmux | ✓ | ✓ | ✓ | ✓ |
| herdr | ✓ | ✓ | ✓ | — |
| Muxy 2 | ✓ | ✓ | ✓ | ✓ |
| Orca | ✓ | ✓ | ✓ | ✓ |
| Paseo | ✓ | ✓ | — | ✓ |

¹ 仅限 Claude Code 会话。

- **Ghostty、Terminal 和 iTerm2** 通过 AppleScript 操作，所以 macOS 会分别询问一次是否允许 Nunsseop 控制它们（系统设置 › 隐私与安全性 › 自动化）。Ghostty 不会告诉 shell 它在哪个标签页，所以 Nunsseop 根据会话的文件夹和 Claude Code 给标签页设置的标题来选定标签页，前往标签页、发消息和拖入文件因此只对 Claude Code 会话有效；不够确定就什么也不发送。Terminal 只能接收会被执行的文字，所以接受消息，但不接受拖入的文件。
- **WezTerm 和 kitty** 通过命令行工具（`wezterm cli`、`kitty @`）操作。kitty 需要开启远程控制，并有一个它监听的套接字。
- **Muxy 2：** 要跳到会话的确切窗格、并在新标签页中恢复对话，需要加载一次 Nunsseop 的小型桥接扩展：在 Muxy 中打开 Settings › Extensions › Load Unpacked…，选择 `~/Library/Application Support/Nunsseop/muxy-bridge`（“设置 › 提醒”里的“在访达中显示扩展”会打开它），然后启用该扩展。不加载的话，点按只会选中会话所在的项目。没有钩子、只有 Muxy 自己知道的会话可以前往，但不能输入文字。
- **Orca：** 通过 `orca` 命令行操作；最近的对话会在 Orca 有窗口时，于包含它的工作树的新标签页中恢复。
- **Paseo：** 消息通过 `paseo send` 发送，只发给不在工作的代理（包括已完成和轮到你的；发给正在工作的会打断它）；点按会在 Paseo 中打开该代理（即表中第一列），已归档的代理可以从“最近”恢复。
- **恢复对话**使用“设置 › 提醒”里“恢复对话所用的终端”选定的终端，不行时由 Terminal 代劳。Ghostty、iTerm2 和 cmux 装了就会出现在选项里，没运行会先启动；WezTerm 要有它的命令行工具；kitty 仅当它的某个会话报告过的套接字仍然存在；Orca 仅当它正在运行且有窗口，并且文件夹是 Orca 认得的工作树（否则交给下一个终端）；Muxy 仅当它的桥接扩展在运行。Ghostty 和 iTerm2 通过自动化打开新标签页（Ghostty 没有权限就改开新窗口），cmux 打开的是新工作区而不是标签页。Paseo 的“最近”条目不受此设置影响，直接在 Paseo 中打开。

## 权限

Nunsseop 的大多数权限只在你第一次使用需要它的功能时才请求。例外是用来监视截图（默认是桌面，或你为截图设定的文件夹）和下载的文件夹，macOS 可能会在 Nunsseop 第一次启动时询问。

| 功能 | 权限 | 何时请求 |
| --- | --- | --- |
| 日历 | 日历 | 在主页标签点按*允许访问*时 |
| 提醒事项 | 提醒事项 | 在主页标签点按*允许提醒事项*时 |
| 镜子 | 相机 | 在镜子标签点按*允许相机*时 |
| 屏幕录制，以及拷贝其他应用窗口中的文字 | 屏幕录制 | 第一次开始录制或提取文本时 |
| 带声音的录制 | 麦克风 | 第一次在开启麦克风音频的情况下录制时 |
| 接管音量、亮度和键盘背光键 | 辅助功能 | 在设置中开启该选项时 |
| “音乐”、Spotify 和浏览器的备用正在播放方案 | 自动化 | 仅在 MediaRemote 辅助库不可用时 |
| 显示浏览器中的 Google Meet、Zoom 和 Teams 通话，以及 Meet 的静音与相机按钮 | 自动化（该浏览器） | 浏览器第一次使用麦克风时 |
| 把新截图加入“架子”，下载提醒 | 桌面和下载文件夹 | Nunsseop 第一次启动时，macOS 可能会询问（它会监视截图文件夹——默认是桌面——和下载文件夹） |
| 每个应用单独的音量 | 系统音频录制 | 第一次在“工具”标签里调低某个应用的音量时 |
| Zoom 和 FaceTime 通话中的静音按钮，Zoom 的相机按钮 | 辅助功能 | 不会自行请求；只要已在辅助功能中允许 Nunsseop，这些按钮就会出现（也可以通过上面的音量键选项来允许） |
| 向代理会话输入消息、前往会话所在的标签页、在新标签页中恢复对话（仅 iTerm2 和 Ghostty） | 自动化（Terminal、iTerm2、Ghostty） | 第一次在该应用中做其中任何一项时；对于 Ghostty，还包括代理标签第一次列出其中运行的会话时 |
| 登录时打开 | 登录项 | 在设置中开启时 |

## 隐私

Nunsseop 不会收集或发送个人数据。它只会在以下情况下联网：

- 每天向 `api.github.com` 检查一次是否有新版本（可以关闭）；在从 DMG 安装的应用中安装更新时，从 GitHub 获取最新版本的 `appcast.xml` 和 DMG；
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
