# MixBar

Per-app volume control for macOS. A menu-bar mixer that gives every running
app its own volume slider and mute button, like the Windows volume mixer.

macOS has no public API for per-app volume, so MixBar ships a virtual audio
device (a Core Audio HAL driver, forked from the excellent
[Background Music](https://github.com/kyleneideck/BackgroundMusic)). MixBar
becomes your output device, the driver applies per-app gain to each app's
audio stream, and MixBar plays the mixed result through your real speakers
or headphones.

## What you get

- A menu-bar popover listing your running apps, each with a volume slider
  and mute button
- A full mixer window (Open Mixer) with the same controls and more room
- An output device picker (speakers, headphones, USB interfaces)
- Volumes persist across app launches and restarts
- `mixbarctl`, a CLI for scripting volumes (`mixbarctl set com.spotify.client 30`)

## Install

There are no prebuilt binaries. You build it from source on your own machine,
which takes one command and a few minutes. You need:

- macOS 13 or later (tested on macOS 15 Sequoia, Apple Silicon and Intel)
- Xcode Command Line Tools (`xcode-select --install`). Full Xcode is NOT
  required.

```sh
git clone https://github.com/ZachSpero/mixbar.git
cd mixbar
./install.sh
```

The script builds the driver and app, asks for your password to install the
driver into `/Library/Audio/Plug-Ins/HAL`, restarts the audio system (your
audio blips for about a second), installs MixBar.app into /Applications, and
launches it. Look for the sliders icon in your menu bar.

On first launch macOS asks for microphone access. Click Allow. MixBar does
not touch your actual microphone; it reads the system audio stream from its
own virtual device, which macOS classifies as audio capture. Without that
permission macOS hands MixBar silence and you'll hear nothing.

Have Claude Code or another coding agent on your machine? Point it at this
repo and say "install this". `CLAUDE.md` tells it everything it needs.

## Uninstall

```sh
./uninstall.sh
```

Quits the app (restoring your previous output device), removes the app and
driver, and restarts the audio system.

## How it works

```
Spotify  Chrome  Zoom ...           (apps play audio normally)
   |        |      |
   v        v      v
MixBar virtual device               (driver tracks each app by PID and
   |                                 applies that app's gain to its samples)
   v
MixBar.app playthrough engine       (reads the mixed stream and writes it
   |                                 to the device you picked)
   v
Your speakers / headphones
```

- `driver/` is the HAL AudioServerPlugIn (C++), forked from Background
  Music's BGMDriver and renamed so the two can coexist.
- `Sources/MixBarEngine/` wraps Background Music's playthrough and
  app-volume classes in a small Objective-C facade.
- `Sources/MixBar/` is the SwiftUI menu-bar app.
- `Sources/mixbarctl/` is the CLI.

Everything builds with plain `make` and `swift build`. No Xcode project.

## Notes and limitations

- Sliders run 0 to 200. 100 is the app's normal volume (the slider snaps
  gently to it), and above 100 boosts the app beyond its normal level.
- `mixbarctl` uses the driver's raw scale, 0 to 100 with 50 as normal.
- Some apps play audio from helper processes (Safari tabs, for example).
  Known helpers are mapped, but an obscure multiprocess app may not respond
  to its slider.
- If MixBar isn't running, audio sent to the MixBar device goes nowhere.
  Quit MixBar from the menu and it restores your previous output device.
- If your sound ever looks stuck on "MixBar" with the app not running, pick
  your speakers in System Settings > Sound > Output.

## License

GPLv2, because the driver and engine are derived from
[Background Music](https://github.com/kyleneideck/BackgroundMusic)
(GPLv2). See LICENSE. PublicUtility files are Apple sample code under their
own license (LICENSE-Apple-Sample-Code).
