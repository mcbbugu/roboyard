# Changelog

## 0.3.0 — 2026-09-11

A 32-robot yard, a warehouse, and conversations that actually take turns.

- Fixed roster of 32 identities. Menu-bar warehouse window sends robots out and calls them back; low battery walks to the icon and vanishes while charging.
- Friends talk for more rounds. Each line waits for the previous one and has to answer it.
- Dropped the teleology overlay that made bodies and meetings feel stuck.
- Sitting, standing, and chatting plant their feet instead of sliding.
- Robots stay silent when the model is down; Ollama or DeepSeek from the menu. Urgent speech waits instead of being dropped.
- Window owner lookup uses Cocoa origin, front-to-back windows, and the same app name as linger speech.

## 0.1.0 — 2026-09-10

The first public preview of RoboYard: a desktop world where words become mass.

- Native macOS menu bar app with 4–32 roaming robots.
- Character-count growth with newborn, curious, thoughtful, and awakened stages.
- Physical collisions, size-dependent mass, and continuous edge movement.
- Persistent individual memories and relationships, with a growth journal.
- Optional local Qwen 3.5 2B dialogue through Ollama. Without a model, robots stay silent.
- Thirteen tests covering movement, contacts, text growth, and memory persistence.

The interface and dialogue are currently Chinese. The downloadable Apple Silicon build is an early preview, ad-hoc signed and not notarized. Other hardware configurations have not been verified.
