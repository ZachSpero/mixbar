// mixbarctl: command-line control and smoke-test tool for MixBar.
//
// Usage:
//   mixbarctl devices                      List output devices
//   mixbarctl volumes                      Show per-app volumes from the driver
//   mixbarctl set <bundleID|pid> <0-100>   Set an app's volume
//   mixbarctl run [output-uid]             Run the engine (playthrough) until killed
//
// This file is part of MixBar. GPLv2. See LICENSE.

import Foundation
import MixBarEngine

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fail("usage: mixbarctl <devices|volumes|set|run> ...")
}

switch args[1] {
case "devices", "volumes", "set":
    // These commands talk to the driver without starting playthrough or
    // changing the default device, so they can run alongside the MixBar app.
    let engine: MixBarEngine
    do {
        engine = try MixBarEngine.inspector()
    } catch {
        fail("MixBar driver not reachable: \(error.localizedDescription)")
    }

    switch args[1] {
    case "devices":
        for d in engine.outputDevices() {
            print("\(d.audioObjectID)\t\(d.uid)\t\(d.name)")
        }
    case "volumes":
        for v in engine.appVolumes() {
            print("pid=\(v.pid)\tvol=\(v.relativeVolume)\tpan=\(v.panPosition)\tbundle=\(v.bundleID ?? "-")")
        }
    case "set":
        guard args.count == 4, let volume = Int(args[3]) else {
            fail("usage: mixbarctl set <bundleID|pid> <0-100>")
        }
        let target = args[2]
        let ok: Bool
        if let pid = Int32(target) {
            ok = engine.setVolume(volume, forPID: pid, bundleID: nil)
        } else {
            ok = engine.setVolume(volume, forPID: -1, bundleID: target)
        }
        if ok {
            print("ok")
        } else {
            fail("failed to set volume")
        }
    default:
        break
    }

case "run":
    let preferredUID = args.count >= 3 ? args[2] : nil
    let engine: MixBarEngine
    do {
        engine = try MixBarEngine.start(withPreferredOutputUID: preferredUID)
    } catch {
        fail("Couldn't start engine: \(error.localizedDescription)")
    }
    print("MixBar engine running. Output device: \(engine.outputDeviceUID). Ctrl-C to stop.")

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    let shutdown = {
        print("Restoring default output device...")
        engine.stopAndRestoreDefaultDevice()
        exit(0)
    }
    sigintSource.setEventHandler(handler: shutdown)
    sigtermSource.setEventHandler(handler: shutdown)
    sigintSource.resume()
    sigtermSource.resume()

    RunLoop.main.run()

default:
    fail("unknown command: \(args[1])")
}
