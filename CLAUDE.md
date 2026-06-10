# MixBar: notes for coding agents

MixBar is a per-app volume mixer for macOS: a virtual Core Audio HAL driver
(forked from Background Music) plus a SwiftUI menu-bar app that does
playthrough and per-app gain.

## Installing for a user

Run `./install.sh`. It builds everything with Command Line Tools only (no
Xcode), installs the driver with sudo, restarts coreaudiod, installs
/Applications/MixBar.app, and launches it. Verify success with:

- `system_profiler SPAudioDataType | grep MixBar` shows the MixBar device
- After launch, the default output device is "MixBar"
- `.build/debug/mixbarctl status` (after `swift build`) reports device state

If the driver fails to load, check `log show --last 5m --predicate
'process == "coreaudiod"'` for plugin errors.

## Layout

- `driver/` C++ HAL plugin (fork of BGMDriver). Built by `driver/Makefile`
  into `build/MixBar.driver`. Renamed device UIDs live in
  `Sources/MixBarEngine/vendor/shared/BGM_Types.h` (single source of truth
  for both driver and app; the Makefile includes it from there).
- `Sources/MixBarEngine/` ObjC++ facade (`MixBarEngine.h/.mm`) over vendored
  Background Music classes (`vendor/`): BGMBackgroundMusicDevice (app
  volumes), BGMPlayThrough (virtual device to real device), and Apple's
  PublicUtility helpers.
- `Sources/MixBar/` SwiftUI app: AppState (engine + NSWorkspace app list +
  UserDefaults persistence), MixerView (popover and window UI).
- `Sources/mixbarctl/` CLI: devices/volumes/set/status/run.
- `scripts/bundle-app.sh` wraps the SPM release binary into MixBar.app.

## Invariants and gotchas

- C++ standard is gnu++14. Apple's PublicUtility code uses APIs removed in
  C++17 (std::binary_function, bind1st). Do not bump it.
- Device UIDs ("MixBarDevice" etc.) must match between the installed driver
  and the app, or the app won't find the device. If you change BGM_Types.h,
  reinstall the driver AND rebuild the app.
- BGMBackgroundMusicDevice::SetAppVolume takes OWNERSHIP of the bundle ID
  CFString (it wraps it in a releasing CACFString). The facade passes a +1
  retained copy. Don't "fix" that to a plain __bridge cast; it crashes.
- The driver reports app volumes only for clients it has seen. An empty
  `mixbarctl volumes` just means nothing has played through the device yet.
- The app must keep running for audio to flow (it hosts the playthrough
  IOProcs). Quitting restores the previous default output device
  (AppDelegate.applicationWillTerminate -> stopAndRestoreDefaultDevice).
- Relaunch race: an older quitting instance can restore the speakers as
  default AFTER a new instance set MixBar as default. The engine reasserts
  3 seconds after startup (reassertDefaultDevice).
- Two volume scales exist. The driver and mixbarctl use 0-100 with 50 =
  unity gain. The app UI displays 0-200 with 100 = unity (sticky snap zone
  of plus or minus 5 around 100) and halves values before calling the
  engine (AppState.driverVolume). Saved volumes are display scale; the
  "volumesAreDisplayScale" UserDefaults flag marks migrated data.
- `sudo launchctl kickstart -k system/com.apple.audio.coreaudiod` is blocked
  by SIP on Sequoia. Use `sudo killall coreaudiod`.
- NEVER call the HAL while holding the engine's stateLock. The HAL blocks
  requests until our property listener callbacks return, and the callbacks
  take stateLock, so holding it across a HAL call deadlocks the app (64
  blocked dispatch threads, main thread hangs, AppleEvents time out with
  -1712). Copy state under the lock, release it, then call the HAL. See
  stopAndRestoreDefaultDevice / reassertDefaultDevice.
- The kAudioDevicePropertyDeviceIsRunningSomewhere handler must READ the
  property and only Start() playthrough when it's true. Calling Start +
  StopIfIdle unconditionally creates an infinite feedback loop: our own
  playthrough starting and stopping fires the same notification. Mirror
  BGMAudioDeviceManager's handlers exactly.
- The driver identifies this app by bundle ID (kBGMAppBundleID), which is
  how StopIfIdle can tell "no clients other than us". mixbarctl and bare
  binaries (no bundle) are treated as regular clients, so playthrough never
  idles while they run IO. Launch the real bundle when testing idle logic.
- The app enforces single instance (a second launch quits itself before
  starting the engine). Double-clicking the app while it runs opens the
  mixer window via applicationShouldHandleReopen.

## Testing changes

1. `make -C driver && swift build` must both pass.
2. Driver changes: `./install.sh` (skips coreaudiod restart if the driver
   binary is unchanged).
3. App-only changes: `./scripts/bundle-app.sh && open build/MixBar.app`.
4. End-to-end: with the app running, `afplay -t 5 /System/Library/Sounds/Submarine.aiff &`
   then `.build/debug/mixbarctl status` should show
   `deviceIsRunningSomewhere: true` and your real output device running=true.
   `mixbarctl set <pid-or-bundle-id> 20` then `mixbarctl volumes` should show
   the entry.
