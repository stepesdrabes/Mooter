# AGENTS.md

Mooter is a macOS 26 menu bar app that sets each app's volume separately. SwiftUI plus Core Audio process taps, Apple frameworks only.

## Rules

- Commits follow Conventional Commits with a scope, e.g. `feat(mixer): remember levels per app`, `fix(audio): …`, `docs: …`. The body explains why.
- No `Co-Authored-By` or any other co-author trailer in commit messages.
- Comments only where they help: the why, or a trap. No narration of what the code plainly does.
- Keep it small. No package dependencies, and a new file needs a reason to exist.

## Build & run

- `make dev`: `swift run`, the fast loop. The audio permission is then attributed to your terminal.
- `make run`: release build, assemble and ad-hoc sign `build/Mooter.app`, then launch it.
- `make install`: the same, into `/Applications`.
- `make clean`: remove `.build/` and `build/`.

It's a SwiftPM executable with no `.xcodeproj`. The `Makefile` assembles the `.app` from the binary, `Support/Info.plist` and `Support/AppIcon.icns`.

## Layout

```
Sources/Mooter/
  main.swift             Entry point: an accessory NSApplication, the Mixer and the MenuBar
  MenuBar.swift          NSStatusItem + NSPopover, and the template cow icon
  MixerView.swift        The popover's SwiftUI content
  Mixer.swift            @Observable model: finds audio apps, stores levels, owns the taps
  VolumeTap.swift        One app's process tap, private aggregate device and render block
  AudioPermission.swift  The System Audio Recording permission, via private TCC calls
Support/                 Info.plist and AppIcon.icns
.github/                 CI, the tag-driven release workflow, and README assets
```

## How it works

1. `Mixer.refresh()` lists Core Audio process objects and groups them under the app *responsible* for each pid, so browser renderers and Electron helpers belong to their app.
2. An app at 100% and unmuted is left alone. Anything else gets a `VolumeTap`: a private `CATapDescription` with `.mutedWhenTapped` (macOS silences the app while the tap is read), and a private aggregate device with the default output as main sub-device and the tap in its tap list. Its IOProc copies the tap's stereo stream to the output at the chosen gain.
3. Two system property listeners, the process list and the default output device, call `refresh()`, which rebuilds a tap when an app's processes or the output change. Levels persist in `UserDefaults`, keyed by bundle ID; only non-default ones are stored.

## Conventions & gotchas

- **Swift 6 with `defaultIsolation(MainActor)`.** Everything is main-actor unless marked otherwise. `VolumeTap` and `AudioPermission` are `nonisolated` because Core Audio and TCC call back on their own threads, and a main-actor closure run on another thread traps at runtime.
- **The render block is real-time code.** No allocations, locks, logging or Swift concurrency in it. Gain is shared through a raw `Float` pointer and ramped across each buffer so slider moves don't click.
- **The tap is the last input buffer** of the aggregate device. Inputs of the output device itself, on interfaces that have them, come first.
- **Build the new tap before dropping the old one**, or a swap leaks a burst at full volume.
- **Not `MenuBarExtra`.** Its `.window` style keeps the content alive and rendering while closed, which cost ~40% CPU with the animated "playing" waveform. `MenuBar` drops the hosting controller in `popoverDidClose`, and the 1 s `isPlaying` poll lives in the view's `.task`, so nothing runs while it's closed.
- **Popover quirks.** A `.transient` popover closes the instant it opens unless the app is active, so call `NSApp.activate()` first. It also misses clicks in other apps, hence the global mouse monitor. `NSEvent.eventNumber` throws on non-mouse events, so check the type before reading it.
- **Ad-hoc signing changes the code hash on every build.** macOS may ask for the audio permission again after a rebuild: System Settings › Privacy & Security › Screen & System Audio Recording.
- **Two private APIs**, both looked up with `dlsym` and degrading gracefully: `responsibility_get_pid_responsible_for_pid` (helper → app) and `TCCAccessPreflight` / `TCCAccessRequest`.

## Verifying changes

`make run`, play something, and move its slider. Mute should silence it instantly, and 100% should drop the tap. While the popover is closed, `ps -o time= -p $(pgrep -x Mooter)` should barely move.

## Releasing

Push a `vX.Y.Z` tag. The Release workflow stamps the version into `Info.plist`, builds, packages a DMG and writes the notes with git-cliff from the conventional commits.
