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
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance only. A second instance would grab the wrong
        // output device (the default is already MixBar by then) and stomp
        // the first instance's state. Quit before starting the engine so
        // shutdown doesn't touch the default device.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.zachspero.mixbar.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

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

    // Double-clicking MixBar.app while it's already running lands here.
    // Open the mixer window so the launch visibly does something.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        showMixerWindow()
        return false
    }

    private var mixerWindow: NSWindow?

    func showMixerWindow() {
        if mixerWindow == nil {
            let hosting = NSHostingController(
                rootView: MixerView(compact: false).environmentObject(state))
            let window = NSWindow(contentViewController: hosting)
            window.title = "MixBar Mixer"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            mixerWindow = window
        }
        mixerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var sigtermSource: DispatchSourceSignal?
}
