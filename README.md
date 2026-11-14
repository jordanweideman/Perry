# Perry

A tiny macOS desktop pet for [Claude Code](https://claude.com/claude-code). Perry, a sausage dog,
walks along the top of your Dock while Claude Code is working. When Claude finishes its turn, he
walks over to the VS Code icon and barks.

Everything runs on your Mac. There's no cloud, no account and no telemetry, and the default setup
needs no permission prompts.

## Requirements

- macOS 14 or later
- A Swift 5.9+ toolchain. The Xcode Command Line Tools are enough (`xcode-select --install`); you
  don't need full Xcode.
- `python3`, which installs the Claude Code hooks (it ships with the Command Line Tools)
- Claude Code, in a terminal or in VS Code

## Quick start

Download the repo (on GitHub, **Code → Download ZIP** and unzip it, or `git clone` it), then open
Terminal in that folder:

```bash
cd ~/Downloads/Perry   # wherever you put it
./perry install      # builds dist/Perry.app, starts it at login, adds the Claude Code hooks
./perry start        # pretend Claude started: Perry appears and wanders the Dock
./perry complete     # pretend Claude finished: he walks to the VS Code icon and barks
```

After that he works on his own: send Claude Code a prompt and he shows up.

**Calibrate the VS Code spot once.** Perry walks to a fixed x-position, set by `vsCodeIconX` in
[Sources/PerryCore/Config.swift](Sources/PerryCore/Config.swift). The default (`1106`) fits one
particular screen and Dock layout, so yours will almost certainly need its own value. Take a
screenshot, note the pixel x of the centre of the VS Code Dock icon, halve it on a Retina display,
put that number in `Config.swift`, and run `./perry build && ./perry run`. Set it to `nil` and he
uses the centre of the VS Code window instead. See [How he finds the VS Code icon](#how-he-finds-the-vs-code-icon).

## How it works

- `dist/Perry.app` is a normal Mac app with no Dock icon and no menu bar. It stays invisible until
  something pokes it.
- It listens on `127.0.0.1:7717`, which is loopback only, so nothing off your Mac can reach it. Routes:
  `POST /start`, `/complete`, `/end`, `/hide`, `/quit`, and `GET /ping`.
- Five Claude Code hooks in `~/.claude/settings.json` `curl` that port. If Perry isn't running,
  each hook gives up in under a second and still exits 0, so Claude Code is never slowed down or blocked.

```
you submit a prompt  →  UserPromptSubmit hook  →  /start     →  Perry appears, wanders the Dock
Claude uses a tool   →  PostToolUse hook       →  /start     →  (heartbeat: keeps him working)
Claude needs you     →  Notification hook      →  /complete  →  walks to VS Code, barks
Claude finishes      →  Stop hook              →  /complete  →  walks to VS Code, barks, then sleeps
session closes       →  SessionEnd hook        →  /end       →  hides once no session is open
```

He barks whenever any session finishes. After that he goes back to wandering if another session is
still working. If none is, he curls up and sleeps above the VS Code icon. He disappears once every
Claude Code session has closed.

### Easter eggs

While Claude is working, Perry very occasionally breaks off from his usual wandering to do something
silly: zoomies (a fast dash), chasing his tail, digging a hole and vanishing (he pops back up
somewhere else along the Dock a little later), or trotting around with a toy in his mouth. On average
one happens every 15–30 minutes of active work (`Config.eggCooldownRange`). They never start
mid-bark or while he's asleep, and a turn finishing always cuts one short, so the bark is never
delayed. They're purely cosmetic and have no settings.

### Privacy

The hooks pipe Claude Code's hook JSON to Perry on `127.0.0.1`. Depending on the event, that JSON
can include your prompt, the working directory and the transcript path. Perry reads only
`session_id` from it, keeps no logs and writes nothing to disk. Any process on your Mac can poke
the port too, but all it can do is make Perry move.

## How he finds the VS Code icon

By default he walks to a fixed spot, `vsCodeIconX` in `Config.swift`, measured as shown in
[Quick start](#quick-start). The Dock is centred on screen, so pinning or unpinning an app shifts
every icon by about half an icon width. If he ends up visibly off, measure again.

**Optional, exact alternative:** `./perry ax` asks macOS for the *Accessibility* permission. With it,
Perry can ask the Dock directly where the icon is, so he's always right. That permission is broad,
though: it's the one macOS gives apps that read other apps' windows and simulate clicks. That's why
Perry doesn't ask for it by default. Rebuilding Perry changes its ad-hoc code signature, which can
make macOS switch the permission off again. If that happens, run `./perry ax` and turn Perry back on.

## Commands

```bash
./perry build        # swift build + assemble dist/Perry.app (needs only Command Line Tools)
./perry run          # launch (hidden)            ./perry quit
./perry start        # pretend Claude started     ./perry complete   # pretend Claude finished
./perry hide         # clear all sessions and hide
./perry ping         # {"state":"working","working":1,"open":2,...}
./perry debug        # run in the foreground with PERRY_DEBUG=1 logging
./perry pause        # stop Perry for now         ./perry resume     # start him again
./perry ax           # optional: grant Accessibility so he finds the icon exactly
./perry hooks install|remove
./perry install      # start at login (LaunchAgent) + hooks
./perry uninstall    # remove LaunchAgent + hooks, quit Perry
```

Logic checks (state machine, animator, session tracking, HTTP parsing) run without Xcode:

```bash
swift run PerryCheck
```

## Turning Perry off, or removing him

None of these steps can affect Claude Code, VS Code or anything else on your Mac. Run them from
inside your clone of this repo.

### What Perry puts on your Mac

| What | Where | What it's for |
|---|---|---|
| This repo | wherever you cloned it | The app, its code, and the sprite frames |
| A LaunchAgent | `~/Library/LaunchAgents/com.jordanweideman.perry.plist` | Starts Perry when you log in (`./perry install` only) |
| Five hook entries | `~/.claude/settings.json` | Tells Claude Code to poke Perry when it starts and finishes |
| A backup of that file | `~/.claude/settings.json.bak` | Saved automatically before the hooks are added or removed |
| An Accessibility entry | System Settings → Privacy & Security → Accessibility | Only if you ran `./perry ax` and said yes |

That's the complete list. He doesn't install anything into Applications, add a Login Item, or write
preferences, caches or data anywhere else. The hook installer changes only entries tagged
`perry-hook` and leaves the rest of your settings alone.

### Option 1: pause him for a bit

```bash
./perry pause        # stops now and stays stopped, even across restarts
./perry resume       # bring him back
```

> `./perry quit` doesn't work for this. The LaunchAgent keeps Perry running, so macOS restarts him
> about half a second later. Use `pause`.

### Option 2: keep him installed but stop him appearing

```bash
./perry hooks remove     # Perry keeps running in the background, but nothing tells him to appear
./perry hooks install    # undo
```

### Option 3: uninstall him but keep the repo

```bash
./perry uninstall
```

This stops Perry, deletes the LaunchAgent, removes the hooks from `~/.claude/settings.json` and
removes his Accessibility entry. Run `./perry install` to reinstall any time.

### Option 4: delete him completely

```bash
./perry uninstall
cd .. && rm -rf Perry
rm -f ~/.claude/settings.json.bak    # optional: a copy of your Claude settings from before the last hook change
```

### Checking what's currently on

```bash
./perry ping                                  # is Perry running? what's he doing?
grep -c perry-hook ~/.claude/settings.json    # 5 = hooks on, 0 = hooks off
ls ~/Library/LaunchAgents/com.jordanweideman.perry.plist   # exists = starts at login
```

If `./perry ping` says "Perry is not running", he's either paused or not installed. Both are
normal and harmless.

## Making your own character

Frames live in `Sprites/<character>/<role>/<role>_NN.png`, and `./perry build` copies them into the
app. To use a new character, add a `Sprites/<name>/` folder, set `character = "<name>"` in
`Sources/PerryCore/Config.swift`, and run `./perry build && ./perry run`. The five core roles cover
ordinary behaviour. A character can skip any or all of the five easter-egg roles: if a folder is
missing, Perry stands idle for as long as that egg would have lasted instead of showing anything
broken. Without a `wake` folder, he goes straight from sleeping to walking.

| Role | Frames | FPS | Used when |
|---|---|---|---|
| `idle` | any, ≥1 | 4 | paused between wanders |
| `walk` | any, ≥1 | 8 | moving |
| `alert` | any, ≥1 | 5 | arrived at the VS Code icon (~5s): the bark. `Config.holds` lets frames linger (look… bark bark… howl…) |
| `sleep` | any, ≥1 | 3 | after the alert, when no session is working |
| `wake` | optional | 4 | played once when a new session starts while asleep (the stretch) |
| `zoomies` | any, ≥1 | 12 | easter egg: a fast dash (~3s) |
| `chasetail` | any, ≥1 | 6 | easter egg: spins in place (~2.5s) |
| `dig` | any, ≥1 | 4 | easter egg: plays once, then he vanishes for 5–15s |
| `popup` | any, ≥1 | 4 | easter egg: plays once when he reappears, before walking resumes |
| `carry` | any, ≥1 | 8 | easter egg: trots around with a toy (~6s) |

- Use transparent PNGs, with every frame of a character the **same size**. He's drawn 60 pt tall
  on screen and as wide as the frame's aspect ratio makes him, so any canvas shape works.
- Perry faces **right**. The app mirrors him to walk left.
- Put his feet on the bottom edge of the canvas. That edge sits on the Dock.
- The frame count comes from the folder. File names just need to sort (`_01`, `_02`, …).
- To iterate without rebuilding, run `PERRY_SPRITES=Sprites/dog ./perry debug`.

**From a sprite sheet** (one image with all the poses on a transparent background):

```bash
python3 Tools/slice_sheet.py detect sheet.png preview.png      # numbers every pose it finds
python3 Tools/slice_sheet.py export sheet.png Sprites/dog \
    sleep=9 wake=13-16 idle=16 alert=17-20                     # pick which numbers play which role
python3 Tools/slice_sheet.py export sheet.png Sprites/dog --anchor=right walk=1,2,3,2
    # walk cycles: pin the nose (--anchor=right) so a wagging tail can't shift the body; repeat a
    # number to ping-pong; leave out frames whose eyes/head don't match the others
python3 Tools/add_zzz.py Sprites/dog/sleep/sleep_01.png Sprites/dog/sleep   # still frame + a little rising Zzz
```

The slicer puts every frame on one shared canvas with the feet on the bottom edge. The sprite tools
need [Pillow](https://pypi.org/project/pillow/) (`pip3 install pillow`). Nothing else does.

## Tuning

Every setting is in `Sources/PerryCore/Config.swift`: walk speed, pause range, bark duration, sprite
size, ground offset (`groundOffset`, plus `dockHiddenGround` for when the Dock is hidden), the port,
and the easter-egg timings. If you change `port`, also change `PORT` in `perry` and the URL in
`Tools/hooks.py`, then run `./perry hooks install`.

## Project layout

```
Sources/PerryCore/   pure logic: state machine (Brain), animator, session tracking, HTTP parsing, Config
Sources/Perry/       the AppKit app: overlay window, sprite view, Dock/screen geometry, loopback server
Sources/PerryCheck/  assertion-based checks for PerryCore (swift run PerryCheck)
Sprites/dog/         PNG frames, bundled into the app at build time
Tools/               hook installer + sprite tools (Python)
build.sh             swift build + hand-assembled, ad-hoc-signed .app (no Xcode)
perry                the control script
```
