// AppState.swift
// MixBar
//
// Owns the engine, the list of running apps, and per-app volume state.
// Volumes persist in UserDefaults and are re-applied when apps launch.
//
// This file is part of MixBar. GPLv2. See LICENSE.

import AppKit
import Combine
import Foundation
import MixBarEngine

struct RunningApp: Identifiable, Equatable {
    let id: pid_t
    let bundleID: String?
    let name: String
    let icon: NSImage?

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.id == rhs.id && lhs.bundleID == rhs.bundleID
    }
}

struct OutputDevice: Identifiable, Hashable {
    let id: UInt32
    let uid: String
    let name: String
}

@MainActor
final class AppState: ObservableObject {
    static let unityVolume = 50

    @Published private(set) var engineRunning = false
    @Published private(set) var engineError: String?
    @Published private(set) var apps: [RunningApp] = []
    @Published private(set) var outputDevices: [OutputDevice] = []
    @Published var selectedOutputID: UInt32 = 0

    /// Slider values keyed by bundle ID (or "pid:<pid>" for apps without one).
    @Published private(set) var volumes: [String: Int] = [:]
    /// Pre-mute volumes for muted apps.
    @Published private(set) var mutedPreviousVolumes: [String: Int] = [:]

    private var engine: MixBarEngine?
    private let defaults = UserDefaults.standard
    private var observers: [NSObjectProtocol] = []

    private static let volumesKey = "appVolumes"
    private static let mutedKey = "mutedApps"
    private static let outputUIDKey = "preferredOutputUID"

    init() {
        volumes = (defaults.dictionary(forKey: Self.volumesKey) as? [String: Int]) ?? [:]
        mutedPreviousVolumes = (defaults.dictionary(forKey: Self.mutedKey) as? [String: Int]) ?? [:]
    }

    // MARK: Engine lifecycle

    func start() {
        guard engine == nil else { return }

        do {
            let engine = try MixBarEngine.start(
                withPreferredOutputUID: defaults.string(forKey: Self.outputUIDKey))
            self.engine = engine
            engineRunning = true
            engineError = nil
        } catch {
            engineError = error.localizedDescription
            engineRunning = false
            return
        }

        refreshOutputDevices()
        refreshApps()
        applyAllVolumes()
        observeWorkspace()

        // If an older instance of MixBar was quitting while we started, its
        // shutdown may have restored the real device as the default after we
        // took over. Reassert a few seconds in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.engine?.reassertDefaultDevice()
        }
    }

    func shutdown() {
        engine?.stopAndRestoreDefaultDevice()
        engine = nil
        engineRunning = false
    }

    // MARK: Apps

    func refreshApps() {
        let workspace = NSWorkspace.shared
        let myPID = ProcessInfo.processInfo.processIdentifier

        apps = workspace.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != myPID }
            .map {
                RunningApp(id: $0.processIdentifier,
                           bundleID: $0.bundleIdentifier,
                           name: $0.localizedName ?? $0.bundleIdentifier ?? "pid \($0.processIdentifier)",
                           icon: $0.icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let launch = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                self?.refreshApps()
                self?.applyVolumeForLaunchedApp(note)
            }
        }
        let quit = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                      object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshApps()
            }
        }
        observers = [launch, quit]
    }

    private func applyVolumeForLaunchedApp(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              let saved = volumes[bundleID] else {
            return
        }
        let effective = mutedPreviousVolumes[bundleID] != nil ? 0 : saved
        engine?.setVolume(effective, forPID: app.processIdentifier, bundleID: bundleID)
    }

    // MARK: Volumes

    func volumeKey(for app: RunningApp) -> String {
        app.bundleID ?? "pid:\(app.id)"
    }

    func volume(for app: RunningApp) -> Int {
        volumes[volumeKey(for: app)] ?? Self.unityVolume
    }

    func isMuted(_ app: RunningApp) -> Bool {
        mutedPreviousVolumes[volumeKey(for: app)] != nil
    }

    func setVolume(_ volume: Int, for app: RunningApp) {
        let key = volumeKey(for: app)
        volumes[key] = volume
        defaults.set(volumes, forKey: Self.volumesKey)

        // Changing the slider unmutes.
        if mutedPreviousVolumes[key] != nil {
            mutedPreviousVolumes[key] = nil
            defaults.set(mutedPreviousVolumes, forKey: Self.mutedKey)
        }

        engine?.setVolume(volume, forPID: app.id, bundleID: app.bundleID)
    }

    func toggleMute(for app: RunningApp) {
        let key = volumeKey(for: app)
        if let previous = mutedPreviousVolumes[key] {
            mutedPreviousVolumes[key] = nil
            engine?.setVolume(previous, forPID: app.id, bundleID: app.bundleID)
        } else {
            mutedPreviousVolumes[key] = volume(for: app)
            engine?.setVolume(0, forPID: app.id, bundleID: app.bundleID)
        }
        defaults.set(mutedPreviousVolumes, forKey: Self.mutedKey)
    }

    private func applyAllVolumes() {
        for app in apps {
            let key = volumeKey(for: app)
            guard let saved = volumes[key] else { continue }
            let effective = mutedPreviousVolumes[key] != nil ? 0 : saved
            engine?.setVolume(effective, forPID: app.id, bundleID: app.bundleID)
        }
    }

    // MARK: Output devices

    func refreshOutputDevices() {
        guard let engine else { return }
        outputDevices = engine.outputDevices().map {
            OutputDevice(id: $0.audioObjectID, uid: $0.uid, name: $0.name)
        }
        selectedOutputID = engine.outputDeviceID
    }

    func selectOutputDevice(_ device: OutputDevice) {
        guard let engine else { return }
        do {
            try engine.setOutputDeviceByID(device.id)
            selectedOutputID = device.id
            defaults.set(device.uid, forKey: Self.outputUIDKey)
        } catch {
            engineError = "Couldn't switch output: \(error.localizedDescription)"
            refreshOutputDevices()
        }
    }
}
