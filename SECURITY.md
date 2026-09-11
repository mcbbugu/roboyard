# Security Policy

RoboYard is a local macOS menu bar app. Please report vulnerabilities privately.

## Report a vulnerability / 如何报告

Email the maintainer listed on [GitHub](https://github.com/mcbbugu/roboyard), or open a **private** GitHub security advisory. Do not file a public issue for exploitable bugs.

## What the app can see / 应用会接触什么

- Pointer location and screen geometry, used so robots can flee and stay on-screen.
- On-screen window owner names (application names), used as optional local dialogue context and place memories.
- A local Ollama HTTP endpoint (default `http://127.0.0.1:11434`) when you enable generated speech.
- Optionally a DeepSeek cloud API key. If you choose cloud dialogue, robot prompts (including application names in context) leave this Mac.

It does **not** record audio, capture screenshots, or read document contents. Model weights are not bundled. Memories stay on this Mac unless you point dialogue at a cloud provider.

Memory files live only on this Mac:

```text
~/Library/Application Support/RoboYard/
├── memories.json
└── experiences.jsonl
```

Do not commit those files, or screen recordings that show private desktop windows.

## Guidance

- Prefer a loopback Ollama address. A remote or cloud endpoint will receive robot prompts that may include application names from your desktop.
- Ad-hoc signed preview builds are not notarized; build from source when you do not want to use Open Anyway.
