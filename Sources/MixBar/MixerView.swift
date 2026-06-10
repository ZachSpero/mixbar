// MixerView.swift
// MixBar
//
// The mixer UI, shared by the menu-bar popover and the full window.
//
// This file is part of MixBar. GPLv2. See LICENSE.

import SwiftUI

struct MixerView: View {
    @EnvironmentObject var state: AppState
    /// Compact for the popover, full for the window.
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let error = state.engineError {
                errorView(error)
            } else {
                appList
            }

            Divider()
            footer
        }
        .frame(width: compact ? 320 : 440)
    }

    private var header: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
            Text("MixBar")
                .font(.headline)
            Spacer()
            Picker("Output", selection: outputSelection) {
                ForEach(state.outputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: compact ? 140 : 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var outputSelection: Binding<UInt32> {
        Binding(
            get: { state.selectedOutputID },
            set: { newID in
                if let device = state.outputDevices.first(where: { $0.id == newID }) {
                    state.selectOutputDevice(device)
                }
            }
        )
    }

    private var appList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(state.apps) { app in
                    AppVolumeRow(app: app, compact: compact)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: compact ? 360 : 520)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
            Text("Run install.sh from the MixBar repo to install the audio driver, then relaunch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                state.refreshApps()
                state.refreshOutputDevices()
            }
            Spacer()
            if compact {
                OpenMixerWindowButton()
            }
            Button("Quit MixBar") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct OpenMixerWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Mixer") {
            openWindow(id: "mixer")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct AppVolumeRow: View {
    @EnvironmentObject var state: AppState
    let app: RunningApp
    var compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app")
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)

                Slider(
                    value: Binding(
                        get: { Double(state.volume(for: app)) },
                        set: { state.setVolume(Int($0.rounded()), for: app) }
                    ),
                    in: 0...100
                )
                .controlSize(.mini)
                .disabled(state.isMuted(app))
                .opacity(state.isMuted(app) ? 0.4 : 1)
            }

            Button {
                state.toggleMute(for: app)
            } label: {
                Image(systemName: state.isMuted(app)
                      ? "speaker.slash.fill"
                      : speakerSymbol(for: state.volume(for: app)))
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(state.isMuted(app) ? "Unmute" : "Mute")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func speakerSymbol(for volume: Int) -> String {
        switch volume {
        case 0: return "speaker"
        case ..<34: return "speaker.wave.1"
        case ..<67: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }
}
