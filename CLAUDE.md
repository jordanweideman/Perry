# CLAUDE.md

Perry is a macOS desktop pet that reacts to Claude Code hooks. It's a SwiftPM package plus a hand-assembled
`.app`. See [README.md](README.md) for user-facing behaviour.

## Commands

```bash
./perry build          # swift build -c release + assemble dist/Perry.app (build.sh)
swift run PerryCheck   # logic checks. Run after any PerryCore change; exits non-zero on failure
./perry debug          # foreground run with PERRY_DEBUG=1 logging to stderr
./perry ping           # current state as JSON
PERRY_SPRITES=Sprites/dog ./perry debug   # load frames from disk, no rebuild needed
```

## Toolchain constraints

- Builds with the Xcode **Command Line Tools only**. There's no `XCTest` or Swift `Testing` module and
  no `xcodebuild`, so `swift test` won't work. Tests are plain assertions in the `PerryCheck` executable.
  Add new checks there.
- Keep `// swift-tools-version:5.9`. That keeps Swift 5 language mode and avoids strict-concurrency
  noise from AppKit.
- No third-party dependencies, in Swift or Python. Pillow is the only exception, and only the
  sprite tools in `Tools/` use it.
- `build.sh` ad-hoc signs the app (`codesign -s -`). Each rebuild changes the signature, which can
  revoke a granted Accessibility permission.

## Architecture

- `Sources/PerryCore/` holds the pure logic, with no AppKit and no timers, so `PerryCheck` can test it.
  - `Brain.swift`: state machine (`hidden`, `working`, `alert`, `alertIdle`, `waking`, plus the
    easter-egg states) and movement. The HTTP routes call `start`/`complete`/`end`/`hide`, and the
    60 Hz timer calls `tick(dt:env:)`.
  - `SessionTracker.swift`: session ids with last-seen times. `Brain` keeps two trackers: `working`
    (mid-turn) and `open` (session not yet ended).
  - `Animator.swift`: frame timing, with per-frame holds and one-shot roles.
  - `HTTPRequest.swift`: minimal HTTP parsing. It pulls `session_id` out of the hook JSON body.
  - `Config.swift`: every tunable. Change values here, not inline.
- `Sources/Perry/` is the AppKit shell: transparent click-through overlay window, sprite view, Dock
  and screen geometry, the optional Accessibility Dock lookup, and the `127.0.0.1:7717` listener.
- `Tools/hooks.py` adds or removes hook entries in `~/.claude/settings.json`. It only touches entries
  whose command contains `perry-hook`, and writes a `.bak` first.

Keep new behaviour logic in `PerryCore` with a check in `PerryCheck`. `Sources/Perry/` should stay
a thin layer that feeds `Env` to `Brain` and draws the result.

## Live-testing gotcha

When Claude Code is the one testing, its own hooks are installed: `UserPromptSubmit`/`PostToolUse`
send `/start` and `Stop` sends `/complete`. So the testing session is always in Perry's `working`
set while tools run. A test expecting "nothing working, so he sleeps" will see him wander instead.
That's expected, not a bug.

To test the state machine live, do it in **one** Bash call: first `POST /hide` (clears all
sessions), then fake sessions with `curl -s -X POST -d '{"session_id":"T"}' http://127.0.0.1:7717/start`
and so on. No hooks fire mid-call.

## Conventions

- Characters live in `Sprites/<character>/<role>/<role>_NN.png`, face right, with feet on the bottom
  edge and the same canvas size for every frame. Easter-egg roles are optional per character.
- If you change the port, update `Config.port`, `PORT` in `perry`, and the URL in `Tools/hooks.py` together.
