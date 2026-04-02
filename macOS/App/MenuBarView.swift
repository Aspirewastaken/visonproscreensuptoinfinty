// MenuBarView.swift
// visionproscreensuptoinfinity
//
// SwiftUI view for the macOS menu bar dropdown.
// Shows server status, connected clients, active displays, and controls.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(macOS)
import SwiftUI

/// The dropdown menu content for the macOS menu bar app.
struct MenuBarView: View {
    @ObservedObject var server: VSMacServer

    @State private var selectedResolution: VSResolution = .r1080p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Status Section
            statusSection

            Divider()

            // MARK: - Displays Section
            displaysSection

            Divider()

            // MARK: - Controls Section
            controlsSection

            Divider()

            // MARK: - Settings Section
            settingsSection

            Divider()

            // MARK: - Footer
            footerSection
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)

        if server.connectedClients > 0 {
            HStack {
                Image(systemName: "vision.pro")
                Text("\(server.connectedClients) client\(server.connectedClients == 1 ? "" : "s") connected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }

    private var statusColor: Color {
        switch server.state {
        case .running: return .green
        case .starting: return .yellow
        case .error: return .red
        case .stopped: return .gray
        }
    }

    private var statusText: String {
        switch server.state {
        case .running: return "Running — \(server.macName)"
        case .starting: return "Starting..."
        case .error: return "Error"
        case .stopped: return "Stopped"
        }
    }

    // MARK: - Displays

    @ViewBuilder
    private var displaysSection: some View {
        if server.displayPipelines.isEmpty {
            HStack {
                Image(systemName: "display")
                Text("No active displays")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            ForEach(Array(server.displayPipelines.values).sorted(by: { $0.id < $1.id }), id: \.id) { pipeline in
                displayRow(pipeline: pipeline)
            }
        }
    }

    @ViewBuilder
    private func displayRow(pipeline: VSMacServer.DisplayPipeline) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "display")
                Text("Display \(pipeline.id)")
                    .font(.subheadline)
                Spacer()
                Text("\(pipeline.config.width)×\(pipeline.config.height)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("\(String(format: "%.0f", pipeline.fps)) fps")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(pipeline.config.bitrate / 1_000_000) Mbps")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsSection: some View {
        if server.displayManager.activeDisplays.count < VSConstants.maxDisplays {
            Button {
                addDisplay()
            } label: {
                Label("Add Virtual Display", systemImage: "plus.display")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }

        if !server.displayManager.activeDisplays.isEmpty {
            Button {
                removeLastDisplay()
            } label: {
                Label("Remove Last Display", systemImage: "minus.display")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }

        if server.state == .stopped {
            Button {
                server.start()
            } label: {
                Label("Start Server", systemImage: "play.fill")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        } else if server.state == .running {
            Button {
                server.stop()
            } label: {
                Label("Stop Server", systemImage: "stop.fill")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Settings

    @ViewBuilder
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New Display Resolution")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            Picker("Resolution", selection: $selectedResolution) {
                ForEach(VSResolution.allResolutions, id: \.self) { res in
                    Text(res.label).tag(res)
                }
            }
            .pickerStyle(.inline)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 4)

        if !VSInputInjector.isAccessibilityGranted {
            Button {
                VSInputInjector.requestAccessibilityPermission()
            } label: {
                Label("Grant Accessibility Access", systemImage: "lock.shield")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerSection: some View {
        HStack {
            Text("visionproscreensuptoinfinity v1.0")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit", systemImage: "power")
        }
        .keyboardShortcut("q")
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func addDisplay() {
        let nextID = UInt8((server.displayManager.activeDisplays.keys.max() ?? 0) + 1)
        let config = VSVideoConfig(
            width: selectedResolution.width,
            height: selectedResolution.height,
            fps: VSConstants.defaultFPS,
            bitrate: VSConstants.defaultBitrate,
            keyframeInterval: VSConstants.defaultKeyframeInterval
        )
        do {
            try server.displayManager.createDisplay(id: nextID, config: config)
        } catch {
            print("[MenuBarView] Failed to add display: \(error)")
        }
    }

    private func removeLastDisplay() {
        guard let lastID = server.displayManager.activeDisplays.keys.max() else { return }
        try? server.displayManager.removeDisplay(id: lastID)
    }
}
#endif
