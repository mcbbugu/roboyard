<p align="center">
  <img src="docs/assets/hero.png" alt="RoboYard — Turn your desktop into a robot playground." width="100%" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-171b2a" alt="macOS 26+" />
  <img src="https://img.shields.io/badge/Swift-6.2%2B-F05138" alt="Swift 6.2+" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-a99cf5" alt="MIT license" /></a>
  <a href="https://github.com/mcbbugu/roboyard/actions/workflows/ci.yml"><img src="https://github.com/mcbbugu/roboyard/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
</p>

<p align="center">
  <b>Turn your desktop into a robot playground.</b><br />
  <a href="https://github.com/mcbbugu/roboyard/releases">Download</a> · <a href="#quick-start">Quick start</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="CONTRIBUTING.md">Contribute</a>
</p>

Keep 32 little robots on your Mac desktop. They roam, rest, collide, flee from your pointer, and stop to answer each other. Every robot has its own personality, battery, relationships, and memories.

<p align="center"><img src="docs/assets/world.gif" alt="RoboYard robots walking, bumping into each other and chatting" width="960" /></p>

*Close-up demonstration using the app’s real renderer and collision engine, with staged dialogue and sample growth levels. [Reproduce it](scripts/render-preview.sh).*

## A tiny world that runs itself

- **A persistent crew of 32.** Keep 4, 8, 12, or 16 on the desk while the rest charge in the warehouse.
- **Behavior lives on your desktop.** They roam, rest, crawl along screen edges, and flee when your pointer gets close.
- **Conversations have continuity.** Robots take turns; each line must answer the last. Familiar pairs talk longer.
- **Battery shapes their routine.** A full charge lasts about 30 minutes. Low-battery robots reserve enough power to walk home.
- **Each robot remembers its own life.** Personality, relationships, and memories survive restarts; more experience means a larger body.
- **Local or cloud dialogue.** Use Ollama by default or opt into DeepSeek. No working model means quiet robots.
- **Switch languages anytime.** The interface and newly generated dialogue support Chinese and English.

Native Swift + AppKit. Lives in your menu bar. Local voice needs no cloud account.

## In action

<p align="center">
  <img src="docs/assets/warehouse.png" alt="Warehouse window: 32 robots, battery bars, send out or call back" width="720" />
  <br /><sub>Warehouse: choose who is on the desk, check battery levels, and call robots home.</sub>
</p>

<p align="center">
  <img src="docs/assets/journal.png" alt="Growth journal: memories, charge, and who is on the desk" width="720" />
  <br /><sub>Journal: accumulated text, growth stage, and recent experiences for every robot.</sub>
</p>

[![RoboYard running on a clean desktop backdrop](docs/assets/desktop.gif)](https://github.com/mcbbugu/roboyard/releases/download/v0.1.0/RoboYard-demo.mp4)

**[Watch the desktop recording](https://github.com/mcbbugu/roboyard/releases/download/v0.1.0/RoboYard-demo.mp4)** · Actual running app over a clean recording backdrop.

## Quick start

**Requirements:** macOS 26+. The downloadable preview is for Apple Silicon. Building from source needs Swift 6.2+ / Xcode 26+.

### Download the app

Get the ZIP from [Releases](https://github.com/mcbbugu/roboyard/releases), unzip it, and move **RoboYard.app** to Applications. Open it and look for the little robot in your menu bar.

This early preview is ad-hoc signed, not notarized. macOS may block the downloaded build; you can build from source instead, or use Apple’s documented [Open Anyway flow](https://support.apple.com/en-us/102445) after reviewing and trusting the project.

### Or build from source

```sh
git clone https://github.com/mcbbugu/roboyard.git
cd roboyard
scripts/bundle.sh
open dist/RoboYard.app
```

### Give them a local voice

Install and run [Ollama](https://ollama.com), then:

```sh
ollama pull qwen3.5:2b
```

RoboYard talks to `http://127.0.0.1:11434` by default. From the menu bar you can keep using Ollama, or switch to cloud DeepSeek by pasting an API key (model defaults to `deepseek-chat`). If you use the Ollama CLI without its desktop app, start the server with `ollama serve`. The menu shows when the endpoint is reachable; if it isn’t, robots stay silent.

Switch between Chinese and English from the menu bar. “Voice” means written speech bubbles; the app does not use a microphone or play synthesized speech. Changing language does not rewrite saved memories.

## How they grow

Use the menu bar icon to show or hide robots, set a desk cap from 4–16, or open the Warehouse and Journal. The journal shows each robot’s character count, stage, recent experiences, and thoughts.

Growth is driven by recorded characters, including punctuation—not model tokens, elapsed time, or the number of inference requests. Repeated contact frames are debounced. Bodies grow smoothly from 16 to 32 points; character counts keep increasing after the visual size cap.

The “awakening” is an authored progression of behavior and dialogue prompts. There is no escape mechanism yet: exploring what such a mechanism could look like is part of the project.

## Where the memories live

```text
~/Library/Application Support/RoboYard/
├── memories.json       # identities, counts, relationships, compact memories
└── experiences.jsonl   # full recorded text history
```

The app reads pointer position, screen/window geometry, and application names. Application names can appear in memories and local dialogue prompts. It does not record audio, capture screenshots, or read document contents. Inference requests go to the configured local Ollama endpoint (loopback by default) or, if you opt in, to DeepSeek. Downloading Ollama or its model is a separate network operation. Model weights are not bundled in this repository. See [SECURITY.md](SECURITY.md).

## Build a more interesting world

The current release is an early experiment. Good next contributions include:

- Richer relationships and more selective long-term recollection.
- Quieter, more efficient rendering for all-day companionship.
- New experiments for robots that begin questioning the boundary.
- A notarized macOS release and broader hardware testing.

Want to hack on it? Start with the [code map and reproducible media](CONTRIBUTING.md). Movement, collision resolution, drawing, and memory are small native Swift components you can inspect and change.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the code map and development loop. Tests cover movement continuity, physical contacts, growth by text, and memory persistence:

```sh
swift test
```

If the idea makes you curious, give a few robots a corner of your desktop—or build their next behavior.

## License

[MIT](LICENSE). Optional models are distributed separately under their own licenses.
