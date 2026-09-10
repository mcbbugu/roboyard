# Contributing

RoboYard is an early experiment in desktop artificial life. Small, concrete contributions are welcome.

## Run locally

You need macOS 26+ and Swift 6.2+ (Xcode 26+). Ollama is optional; the robots have built-in fallback dialogue.

```sh
swift test
scripts/bundle.sh
open dist/RoboYard.app
```

Before opening a pull request, run `swift test` and `scripts/bundle.sh`. Describe the visible behavior your change creates, and include a short clip for movement or drawing changes.

## Design principles

- **Words drive growth.** Count recorded characters, not idle time or API calls.
- **Bodies occupy space.** Growth must change collision volume. Test crowds, walls, and fleeing.
- **Identity persists.** Hiding robots or changing their count must not erase their memories.
- **Local by default.** Avoid introducing a cloud dependency for basic behavior.
- **A small presence.** Keep the desktop usable and avoid grabbing focus.

The app currently speaks Chinese. Localization, more expressive interaction, better memory retrieval, and efficient rendering are good places to help. Open an issue before large changes to the rules of the world.

Never commit personal transcripts, memory archives, API keys, or screenshots containing private information. Use synthetic fixtures in tests and demos.

## Code map

| File | Responsibility |
| --- | --- |
| `Critters.swift` | Robot behavior, overlays, and interaction loop |
| `BotPhysics.swift` | Contact resolution and movement substeps |
| `RobotMemory.swift` | Character counts, growth, retrieval, and local persistence |
| `CritterTalk.swift` | Optional Ollama dialogue |
| `RobotMark.swift` | Native vector rendering |
| `RobotJournalView.swift` | Growth journal |

The Swift module and persistence directory retain the original internal name `AlwaysListen` so existing installations keep their memories. The public app name is RoboYard.

## Reproduce the visuals

`scripts/render-preview.sh` generates the close-up GIF, hero, and icon from the native renderer and collision engine. Its dialogue and growth levels are staged samples.

`scripts/JournalPreview.swift` renders the actual journal against an isolated sample store. `CaptureBackdrop.swift` draws only the recording background; the robots in the desktop clip come from the running app. `PrepareRecording.swift` uses AVFoundation and ImageIO to export MP4, GIF, and a review contact sheet without third-party media dependencies.

Compile these Swift entry points with `swiftc -parse-as-library`. JournalPreview also needs the RobotMemory, MBTI, CritterTalk, RobotMark, and RobotJournalView source files. The capture helper takes no arguments; PrepareRecording takes an input movie and output directory, and JournalPreview takes an output directory. Review all frames before publishing any screen recording.

## CI setup

The ready-to-use workflow is in `docs/development/ci.yml`. Move it to `.github/workflows/ci.yml` using a GitHub credential with workflow permission to enable automated builds. The initial release was tested locally.
