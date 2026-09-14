# Changelog

## 4.0.0 — 2026-09-14

Bigger yard, shippable.

- Desk cap reaches 24 (`4/8/12/16/24`); clamps updated, no test depended on 16.
- `Log.swift`: timestamped `logs.txt` with rotation, wired into load/save failures and memory erase.
- `scripts/notarize.sh`: notarytool submit → staple → validate; exits 2 with instructions when `APPLE_ID/APP_PASSWORD/TEAM_ID` are missing, never blocks CI.
- Known limitation: builds are still ad-hoc signed until someone runs the script with a paid Apple ID.

## 3.0.0 — 2026-09-14

The yard keeps its own rhythm and grudges.

- Quiet nights (23:00–07:00 local, menu toggle, default on): speech muted, bodies keep moving; screen lock/fast-switch mutes via session notifications.
- Rivalry arcs: 6+ collisions unlock a grudge scold opener that cites the count (`Copy.scoldCueFor`, threaded through `say/utter/speak`).
- First-run onboarding alert (three steps: pet, menu, Ollama); shown once via `critter.onboarded`.

## 2.0.0 — 2026-09-14

The yard becomes touchable.

- P4 split: `Bot` → `Bot.swift`, swarm/bubble views → `SwarmUI.swift`; `Critters` back to ~740 lines with zero behavior change.
- Click to pet: a global click monitor (observes, never swallows) pets the nearest desk robot within 44px — +0.01 charge, canned reaction bubble, `.care` memory, 3s per-robot cooldown, menu toggle, skipped while the app is active.
- Feed the desk from the menu bar (`Cmd+F`): +0.08 charge for everyone on the desk, 60s cooldown with visible countdown.
- Rename any robot from its warehouse card (context menu + sheet, max 12 chars, clear restores its number); nicknames persist in `memories.json`.
- New `.care` memory kind (30s debounce) so affection shows up in the journal and model context.
- Forward-compat fix found by test: custom `init(from:)` with `decodeIfPresent` fallbacks, so older snapshots without new keys still load instead of failing the whole file.

## Unreleased (bubble turns + scare fixes)

- Conversation bubbles take display-level turns: a line waits (up to 6s) for either participant's visible bubble to expire before appearing, so the two sides no longer stack. Flee bubbles stay immediate.
- Freshly released (emerging) robots can now be scattered by the pointer; scare coverage was yard-only before. Homing bots are still left alone so the trip home isn't fought.
- Scare charge cost is debounced to once per second per robot (was deducted every frame, ~0.12/s while chased).
- Conversations end instead of talking to air: each turn re-checks the pair bond, so a fleeing or recalled partner stops the exchange; post-wait utter re-validates the speaker is still on the desk.

## 0.4.0 — 2026-09-14

Reliable talk, visible relationships, all-day power, boundary story, and safer cloud.

- Dialogue queue: non-urgent lines wait instead of being dropped (cap 8, urgent first); same trigger within 30s reuses the last line; HTTP non-2xx no longer counts as success.
- Relationships visible: bond levels (familiar/old/best pals), closest-friend + edge-walker badges in the warehouse, history-aware chat openers; key-memory eviction now keeps close friends.
- Cleaning fixed: MBTI codes are stripped, not dropped; prompt-injection markers still blocked; English truncates at word boundaries.
- Power saver (30fps, fewer repaints when idle, 4 bubbles) from the menu bar; low battery truly limps; warehouse cards show minutes left; experiences.jsonl rotates past 512KB.
- Boundary milestone: all 4 edges + thoughtful unlocks a special reflect prompt, faster reflections, and a persistent glow; charge sharing flashes both bots.
- Safety: switching to DeepSeek needs explicit confirmation; app-name inclusion can be turned off (sanitized, capped); journal can export/reveal or erase all memories; prompts use explicit memory/requirement sections.
- Tests grow from 13 to 41 across queue, cleaning, bonds, weighted eviction, and milestones. `swift test` + `scripts/bundle.sh` + strict signature all pass.

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
