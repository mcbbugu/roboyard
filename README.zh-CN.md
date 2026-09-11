<p align="center"><img src="docs/assets/hero.png" alt="RoboYard：把桌面变成机器人的游乐场" width="100%" /></p>

<p align="center"><b>把桌面变成机器人的游乐场。</b><br />
<a href="https://github.com/mcbbugu/roboyard/releases">下载</a> · <a href="#开始养几只">开始使用</a> · <a href="README.md">English</a> · <a href="CONTRIBUTING.md">参与开发</a></p>

在 Mac 上养一群小机器人。看它们四处爬行、碰撞、停下来聊天；把鼠标凑过去，它们还会逃跑。打开仓库轮换谁在桌上，打开成长记录看看它们记住了什么。

<p align="center"><img src="docs/assets/world.gif" alt="机器人走动、碰撞、聊天的近景演示" width="960" /></p>

*近景演示使用应用真实的绘图和碰撞代码，台词与成长阶段为预设样本。[一键生成](scripts/render-preview.sh)。*

## 可以怎么玩

- **放一群出来**：仓库编制 32 只，桌上同时最多 4–16 只。
- **逗逗它们**：把鼠标靠近，看它们逃跑；平时会闲逛、休息、沿着屏幕边缘爬行。
- **围观社交现场**：相遇会聊天。熟了聊得更久，每一句要接对方刚说的。
- **送回去充电**：没电的爬向菜单栏图标，进仓库消失，充满再爬出来。
- **认识每一只**：每只都有自己的性格、经历、对话和关系，重启后仍然记得。
- **慢慢养大**：记录下来的经历推动体型成长；打开成长记录，查看累计字数和最近的见闻。
- **接上本地或云端**：默认 Ollama，也可以填 DeepSeek Key。没模型就沉默。

原生 Swift / AppKit 菜单栏应用。本地对话不需要云端账号。

## 实际运行画面

<p align="center">
  <img src="docs/assets/warehouse.png" alt="仓库窗口：32 只机器人、电量条、派上桌或叫回来" width="720" />
</p>

<p align="center">
  <img src="docs/assets/journal.png" alt="成长记录：记忆、电量、谁在桌上" width="720" />
</p>

[![RoboYard 在干净桌面背景上的实机画面](docs/assets/desktop.gif)](https://github.com/mcbbugu/roboyard/releases/download/v0.1.0/RoboYard-demo.mp4)

**[观看桌面录屏](https://github.com/mcbbugu/roboyard/releases/download/v0.1.0/RoboYard-demo.mp4)** · 真实运行的应用，使用专门准备的录屏背景。

## 开始养几只

需要 **macOS 26 或更新版本**。预编译版本面向 Apple Silicon；源码编译需要 **Swift 6.2+ / Xcode 26+**。

### 下载

从 [Releases](https://github.com/mcbbugu/roboyard/releases) 下载 ZIP，解压后把 **RoboYard.app** 放进「应用程序」，打开后寻找菜单栏里的小机器人。

当前是早期预览版，采用临时签名，尚未完成 Apple 公证。若 macOS 拦截下载的应用，可以自行从源码编译；确认信任项目后，也可按照 [Apple 官方说明](https://support.apple.com/zh-cn/102445)使用「仍要打开」。

### 从源码运行

```sh
git clone https://github.com/mcbbugu/roboyard.git
cd roboyard
scripts/bundle.sh
open dist/RoboYard.app
```

### 让它们用本地模型说话

安装并启动 [Ollama](https://ollama.com)，然后运行：

```sh
ollama pull qwen3.5:2b
```

应用默认连接 `http://127.0.0.1:11434`。菜单栏可选本地 Ollama，或填 DeepSeek API Key 走云端（默认 `deepseek-chat`）。若使用纯命令行版 Ollama，需要先运行 `ollama serve`。菜单会显示是否连上；没连上就保持沉默。

目前界面和台词是中文。「说话」指文字气泡，没有麦克风录音，也没有语音播放。

## 看看它们记住了什么

点击菜单栏图标，可以显示/隐藏机器人、选择 4–32 只的数量，或打开「成长记录…」。记录里能看到每只机器人的累计字数、阶段、最近的经历与想法。把鼠标靠近它们，看看会发生什么。

成长统计的是字符数（含标点），不是模型 token、运行时长或请求次数。连续接触的重复帧会合并。体型从 16 点平滑增长到 32 点；达到显示上限后，文字仍然继续积累。

「觉醒」目前由成长阶段、行为倾向和对话提示共同实现。接下来值得探索的是：当它们已经开始怀疑边界，能够做出怎样的尝试？

## 记忆放在哪里

```text
~/Library/Application Support/RoboYard/
├── memories.json       # 身份、字数、关系与精简记忆
└── experiences.jsonl   # 原始文本经历
```

应用读取鼠标位置、屏幕/窗口几何信息和应用名称。应用名称可能进入记忆与模型提示；不会录音、截图或读取文档内容。推理请求默认发往本机 Ollama；若你改选云端 DeepSeek，提示会出境。Ollama 与模型下载是独立的网络操作，模型权重不包含在本仓库中。详见 [SECURITY.md](SECURITY.md)。

## 一起把这个世界做得更有意思

目前还是早期实验，欢迎贡献：

- 英文及多语言界面、台词。
- 更丰富的关系、更有选择性的长期回忆。
- 更适合全天陪伴的低功耗绘制。
- 成熟机器人探索边界的新行为。
- Apple 公证与更多硬件上的验证。

开发说明与代码地图见 [CONTRIBUTING.md](CONTRIBUTING.md)。测试覆盖移动连续性、物理接触、文字成长和记忆持久化：

```sh
swift test
```

给它们留一点桌面空间，也欢迎动手改造它们的下一种行为。

## 许可证

[MIT](LICENSE)。可选模型遵循各自的许可证。
