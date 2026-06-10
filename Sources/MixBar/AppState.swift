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
    /// Displayed volume scale: 0 to 200, where 100 is the app's normal
    /// volume. The driver uses 0 to 100 with 50 as unity, so displayed
    /// values are halved on the way in.
    static let unityVolume = 100
    static let maxVolume = 200

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
    private var activityTimer: Timer?

    private static let volumesKey = "appVolumes"
    private static let mutedKey = "mutedApps"
    private static let outputUIDKey = "preferredOutputUID"
    private static let displayScaleKey = "volumesAreDisplayScale"
    private static let extraAudioAppsKey = "extraAudioApps"
    private static let volumeAliasesKey = "appVolumeAliases"

    // Local customization (set via `defaults write com.zachspero.mixbar.app ...`),
    // not shipped in the repo:
    //   extraAudioApps: [String]        extra bundle-id/name substrings to show
    //   appVolumeAliases: [String:[String]]  apply an app's volume to extra
    //       bundle IDs too - needed for multiprocess/Electron apps whose audio
    //       plays from a helper process (e.g. <bundle>.helper).
    private let extraAudioApps: [String]
    private let volumeAliases: [String: [String]]

    init() {
        volumes = (defaults.dictionary(forKey: Self.volumesKey) as? [String: Int]) ?? [:]
        mutedPreviousVolumes = (defaults.dictionary(forKey: Self.mutedKey) as? [String: Int]) ?? [:]
        extraAudioApps = ((defaults.array(forKey: Self.extraAudioAppsKey) as? [String]) ?? [])
            .map { $0.lowercased() }
        volumeAliases = (defaults.dictionary(forKey: Self.volumeAliasesKey) as? [String: [String]]) ?? [:]

        // Migrate values saved when the UI used the driver's 0-100 scale
        // (50 = unity) to the displayed 0-200 scale (100 = unity).
        if !defaults.bool(forKey: Self.displayScaleKey) {
            volumes = volumes.mapValues { min($0 * 2, Self.maxVolume) }
            mutedPreviousVolumes = mutedPreviousVolumes.mapValues { min($0 * 2, Self.maxVolume) }
            defaults.set(volumes, forKey: Self.volumesKey)
            defaults.set(mutedPreviousVolumes, forKey: Self.mutedKey)
            defaults.set(true, forKey: Self.displayScaleKey)
        }
    }

    /// Displayed 0-200 to the driver's 0-100.
    private func driverVolume(_ displayed: Int) -> Int {
        max(0, min(100, Int((Double(displayed) / 2.0).rounded())))
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

        // Apps appear in the mixer when they start playing audio, so refresh
        // the list on a light timer while we're running.
        activityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshApps() }
        }

        // Remember the device the engine actually picked so the next launch
        // (when the default device is already MixBar) restores it instead of
        // falling back to an arbitrary device.
        let uid = engine?.outputDeviceUID ?? ""
        if !uid.isEmpty {
            defaults.set(uid, forKey: Self.outputUIDKey)
        }

        // If an older instance of MixBar was quitting while we started, its
        // shutdown may have restored the real device as the default after we
        // took over. Reassert a few seconds in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.engine?.reassertDefaultDevice()
        }
    }

    func shutdown() {
        activityTimer?.invalidate()
        activityTimer = nil
        engine?.stopAndRestoreDefaultDevice()
        engine = nil
        engineRunning = false
    }

    // MARK: Apps

    func refreshApps() {
        let workspace = NSWorkspace.shared
        let myPID = ProcessInfo.processInfo.processIdentifier
        let activeBundleIDs = AudioApps.activeBundleIDs()

        apps = workspace.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != myPID }
            .map {
                RunningApp(id: $0.processIdentifier,
                           bundleID: $0.bundleIdentifier,
                           name: $0.localizedName ?? $0.bundleIdentifier ?? "pid \($0.processIdentifier)",
                           icon: $0.icon)
            }
            .filter { shouldShow($0, activeBundleIDs: activeBundleIDs) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // An app belongs in the mixer if it's making sound right now, is a known
    // audio app (so it can be pre-set while idle), or the user has already
    // given it a volume. Everything else (Excel, Finder, note apps, IDEs) is
    // hidden so the mixer only lists things that actually play audio.
    private func shouldShow(_ app: RunningApp, activeBundleIDs: Set<String>) -> Bool {
        if volumes[volumeKey(for: app)] != nil {
            return true
        }
        if AudioApps.isLikelyAudioApp(bundleID: app.bundleID, name: app.name) {
            return true
        }
        if !extraAudioApps.isEmpty {
            let hay = ((app.bundleID ?? "") + " " + app.name).lowercased()
            if extraAudioApps.contains(where: { hay.contains($0) }) {
                return true
            }
        }
        if let bundleID = app.bundleID, isAudioActive(bundleID: bundleID, in: activeBundleIDs) {
            return true
        }
        return false
    }

    // Active bundle IDs include helper processes (com.google.Chrome.helper),
    // so match the app's bundle ID as an exact or parent match.
    private func isAudioActive(bundleID: String, in active: Set<String>) -> Bool {
        if active.contains(bundleID) {
            return true
        }
        let prefix = bundleID + "."
        return active.contains { $0.hasPrefix(prefix) }
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
        pushVolume(effective, pid: app.processIdentifier, bundleID: bundleID)
    }

    // MARK: Volumes

    // Apply a displayed (0-200) volume to the engine for an app, plus any
    // configured alias bundle IDs (for multiprocess apps whose audio plays
    // from a helper process). Aliases are matched by bundle ID only (pid -1).
    private func pushVolume(_ displayVolume: Int, pid: pid_t, bundleID: String?) {
        let dv = driverVolume(displayVolume)
        engine?.setVolume(dv, forPID: pid, bundleID: bundleID)
        if let bundleID, let aliases = volumeAliases[bundleID] {
            for alias in aliases {
                engine?.setVolume(dv, forPID: -1, bundleID: alias)
            }
        }
    }

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

        pushVolume(volume, pid: app.id, bundleID: app.bundleID)
    }

    func toggleMute(for app: RunningApp) {
        let key = volumeKey(for: app)
        if let previous = mutedPreviousVolumes[key] {
            mutedPreviousVolumes[key] = nil
            pushVolume(previous, pid: app.id, bundleID: app.bundleID)
        } else {
            mutedPreviousVolumes[key] = volume(for: app)
            pushVolume(0, pid: app.id, bundleID: app.bundleID)
        }
        defaults.set(mutedPreviousVolumes, forKey: Self.mutedKey)
    }

    private func applyAllVolumes() {
        for app in apps {
            let key = volumeKey(for: app)
            guard let saved = volumes[key] else { continue }
            let effective = mutedPreviousVolumes[key] != nil ? 0 : saved
            pushVolume(effective, pid: app.id, bundleID: app.bundleID)
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
