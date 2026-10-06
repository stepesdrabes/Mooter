<p align="center">
  <img src=".github/assets/icon.png" width="128" alt="Mooter's icon, a cute cow">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/logo-dark.png">
    <img src=".github/assets/logo-light.png" width="240" alt="Mooter">
  </picture>
</p>

<p align="center">
  <b>Per-app volume for your Mac.</b><br>
  The little mixer macOS forgot to ship. 🐮
</p>

---

Mooter lives in your menu bar and gives every app that plays sound its own volume slider and mute button. Turn the call down without touching the music. Mute the tab that won't stop autoplaying.

- **One slider per app.** Browser tabs, Electron helpers and WebKit processes count as the app they belong to.
- **It remembers.** Levels stick, and come back the moment an app makes sound again.
- **It follows your output.** Switch to headphones or AirPods and every level comes along.
- **It stays out of the way.** Native SwiftUI with Liquid Glass, no dependencies, under 600 lines of Swift, and 0% CPU while closed. Apps left at 100% aren't touched at all.

## Install

Grab the DMG from [Releases](https://github.com/stepesdrabes/Mooter/releases/latest) and drag Mooter into Applications. It's ad-hoc signed rather than notarized, so clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/Mooter.app
```

On first launch, macOS asks to let Mooter record system audio. That's how it reaches other apps' sound; nothing is ever recorded or saved.

Or build it yourself:

```sh
make run      # build build/Mooter.app and launch it
make install  # or put it in /Applications
```

Requires **macOS 26 (Tahoe)**.

## How it works

Mooter uses Core Audio [process taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps). Turn an app down and Mooter taps its audio with *muted when tapped*, so macOS silences the original, then plays the copy back on your output device at the volume you picked.

## License

[MIT](LICENSE)

<p align="center">
  <img src="https://media.giphy.com/media/Q3J5xe18ZEOVZqWA8x/giphy.gif" width="220" alt="A pixelated cow dancing to music">
</p>
