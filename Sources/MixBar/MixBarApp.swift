// MixBarApp.swift
// MixBar
//
// App entry point: menu-bar popover plus an optional full mixer window.
//
// This file is part of MixBar. GPLv2. See LICENSE.

import AppKit
import SwiftUI

@main
struct MixBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("MixBar", systemImage: "slider.horizontal.3") {
            MixerView(compact: true)
                .environmentObject(appDelegate.state)
        }
        .menuBarExtraStyle(.window)

        Window("MixBar Mixer", id: "mixer") {
            MixerView(compact: false)
                .environmentObject(appDelegate.state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.start()

        // Restore the default output device if we get killed politely.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        sigtermSource = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }

    private var sigtermSource: DispatchSourceSignal?
}
