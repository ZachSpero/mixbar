// AudioApps.swift
// MixBar
//
// Decides which running apps belong in the mixer. Two signals:
//   1. Live audio activity from CoreAudio's process API (an app actually
//      playing or capturing sound right now) - works by behavior, no names.
//   2. A generous allowlist of known audio-app families so media, browser,
//      communication, DJ, and production apps appear even while idle.
// Apps the user has already set a volume for are kept by AppState.
//
// This file is part of MixBar. GPLv2. See LICENSE.

import CoreAudio
import Foundation

enum AudioApps {

    /// Bundle IDs of processes currently doing audio IO (output or input).
    /// Includes helper bundle IDs (e.g. com.google.Chrome.helper); callers
    /// should prefix-match against an app's bundle ID. Empty if the API is
    /// unavailable or returns nothing.
    static func activeBundleIDs() -> Set<String> {
        var result = Set<String>()
        for obj in processObjects() {
            let running = boolProp(obj, kAudioProcessPropertyIsRunning)
            let out = boolProp(obj, kAudioProcessPropertyIsRunningOutput)
            let input = boolProp(obj, kAudioProcessPropertyIsRunningInput)
            guard running || out || input else { continue }
            let bundle = stringProp(obj, kAudioProcessPropertyBundleID)
            if !bundle.isEmpty {
                result.insert(bundle)
            }
        }
        return result
    }

    /// True if the app is the kind of app that plays or captures audio:
    /// music/media players, browsers, communication apps, DJ software, and
    /// DAWs/production tools. Matched generously by bundle ID and name so a
    /// missed app still shows the moment it actually plays (via activeBundleIDs).
    static func isLikelyAudioApp(bundleID: String?, name: String) -> Bool {
        let haystack = ((bundleID ?? "") + " " + name).lowercased()
        return keywords.contains { haystack.contains($0) }
    }

    // Substrings matched against "<bundleID> <name>", lowercased. Kept broad
    // on purpose: false positives (an app shows that rarely plays sound) are
    // harmless; the live-activity signal covers anything missing here.
    private static let keywords: [String] = [
        // Browsers
        "safari", "chrome", "chromium", "firefox", "mozilla", "edge", "edgemac",
        "arc", "thebrowser", "brave", "opera", "vivaldi", "duckduckgo", "zen",
        // Music / media players
        "spotify", "music", "itunes", "vlc", "iina", "podcast", "audible",
        "soundcloud", "tidal", "deezer", "pandora", "plex", "infuse", "elmedia",
        "swinsian", "doppler", "sonos", "roon", "twitch", "youtube", "netflix",
        // Communication / calls
        "zoom", "teams", "slack", "discord", "skype", "webex", "facetime",
        "whatsapp", "telegram", "signal", "meet", "around", "gather",
        // DJ software
        "dj", "serato", "rekordbox", "pioneer", "traktor", "djay", "mixvibes",
        "virtualdj", "engine", "mixxx",
        // Production / DAWs / audio tools
        "ableton", "logic", "garageband", "cubase", "nuendo", "studio one",
        "studioone", "fl studio", "image-line", "flstudio", "bitwig", "protools",
        "pro tools", "reaper", "cockos", "renoise", "reason", "audacity",
        "native-instruments", "native instruments", "komplete", "kontakt",
        "maschine", "reaktor", "battery", "massive", "serum", "vital", "kontrol",
        "audio", "sound", "mixer", "synth", "sampler", "daw", "splice", "loopback",
        "melodics", "youlean", "loudness", "spotify",
    ]

    // MARK: CoreAudio process API

    private static func processObjects() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
            size > 0 else {
            return []
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func boolProp(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &sz, &v) == noErr else { return false }
        return v != 0
    }

    private static func stringProp(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var v: CFString = "" as CFString
        var sz = UInt32(MemoryLayout<CFString>.size)
        let st = withUnsafeMutablePointer(to: &v) {
            AudioObjectGetPropertyData(obj, &addr, 0, nil, &sz, $0)
        }
        return st == noErr ? (v as String) : ""
    }
}
