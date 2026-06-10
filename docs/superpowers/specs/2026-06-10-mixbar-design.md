# MixBar Design Spec (2026-06-10)

## Purpose

A macOS app that gives true per-app volume control, like the Windows volume
mixer. Each running app that plays audio gets its own volume slider and mute
button. Built for Zach's Mac first, published on GitHub so anyone can clone it
and have their own Claude build and install it locally.

## Why a virtual audio driver

macOS has no public per-app volume API. The only proven approach (SoundSource,
Background Music) is a virtual output device: a Core Audio HAL
AudioServerPlugIn that becomes the default output. Apps play into it, the
driver tracks each client by PID and applies per-client gain, and a playthrough
engine forwards the mixed audio to the real output device.

## Architecture

Three units:

1. **MixBar.driver** (C++, GPLv2). Fork of Background Music's BGMDriver,
   renamed and re-bundled. Loaded by coreaudiod from
   /Library/Audio/Plug-Ins/HAL. Presents a virtual output device. Tracks
   clients per PID, applies per-app relative volume and pan set through Core
   Audio custom properties (kAudioDeviceCustomPropertyAppVolumes). Loops
   played audio back on its input stream so the app can read it.

2. **MixBarEngine** (C++/ObjC++ wrapped for Swift). Reuses Background Music's
   app-side audio classes (playthrough, device manager, PublicUtility). Owns:
   setting the virtual device as default output, playthrough from the virtual
   device to the chosen real output device, reading the list of audio clients,
   and writing per-app volume/mute to the driver via custom properties.
   Restores the previous default output device on quit.

3. **MixBar.app** (Swift/SwiftUI). MenuBarExtra popover with a live list of
   apps that have played audio, each with a slider (0 to 100, default 50 =
   unity gain) and a mute toggle, plus an output device picker. A full mixer
   window offers the same controls with more room. No Dock icon (LSUIElement),
   menu bar only.

Communication driver <-> app is entirely through Core Audio property calls on
the virtual device. No XPC helper in v1 (BGM uses XPC only to coordinate its
optional UI sounds device; we drop that).

Mute is implemented as volume 0 with the previous value remembered in the app
(the driver's app-volumes property accepts relative volume per PID).

## Build system (no Xcode required)

Only Command Line Tools are assumed. This is a hard requirement so other
people's Claudes can build it.

- Driver: Makefile invoking clang++, producing MixBar.driver bundle, ad-hoc
  codesigned.
- Engine + app: Swift Package Manager. The engine is a C++/ObjC++ SPM target
  with a small ObjC facade header exposed to Swift. swift build produces the
  executable; a script assembles MixBar.app bundle (Info.plist, icon),
  ad-hoc codesigned.
- install.sh: builds both, copies the driver into /Library/Audio/Plug-Ins/HAL
  (sudo), restarts coreaudiod, copies MixBar.app to /Applications, launches it.
- uninstall.sh reverses everything and restores the default output device.

## Distribution model

Public GitHub repo (github.com/ZachSpero/mixbar), GPLv2 (derived from
Background Music). No notarization or paid developer account: every user
builds from source and ad-hoc signs on their own machine. README plus
CLAUDE.md document the one-command flow: clone, ./install.sh.

## Error handling

- Driver fails to load: install.sh verifies the virtual device appears after
  restarting coreaudiod and prints diagnostics if not.
- coreaudiod restart interrupts audio for about a second: documented.
- App quits or crashes: uninstall/quit path restores previous default output
  so the user is never stuck with silent audio. The app also offers a
  "restore default device" action.
- Output device disappears (headphones unplugged): engine falls back to the
  system's new default real device.

## Testing

- Driver: build, install, assert device with MixBar UID exists via
  AudioObjectGetPropertyData (small CLI check tool in repo).
- Engine: CLI smoke test that sets an app volume property and reads it back.
- End to end on this Mac: play audio from two apps, lower one slider,
  confirm only that app gets quieter while audio still reaches the speakers.

## Out of scope for v1

EQ, per-app output routing, recording, presets, notarized binaries,
App Store. Architecture leaves room for a settings window later.
