// ContentView.swift
// visionproscreensuptoinfinity
//
// Main landing view for the visionOS app.
// Shows discovery when disconnected, connected status and
// display management when connected.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(visionOS)
import SwiftUI

/// Main content view that switches between discovery and connected states.
struct ContentView: View {

    @EnvironmentObject var connectionManager: VSConnectionManager
    @EnvironmentObject var windowManager: VSWindowManager
    @Environment(\.openWindow) private var openWindow

    @State private var showPerformanceOverlay = false

    var body: some View {
        NavigationStack {
            Group {
                switch connectionManager.connectionState {
                case .disconnected:
                    disconnectedView

                case .connecting:
                    connectingView

                case .connected:
                    connectedView
                }
            }
            .navigationTitle("VisionScreen ∞")
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    // MARK: - Disconnected

    @ViewBuilder
    private var disconnectedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "display.2")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Stream Mac Displays")
                .font(.largeTitle)
                .bold()

            Text("Discover your Mac on the local network\nand stream virtual displays to Vision Pro.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, 40)

            VSDiscoveryView()
                .environmentObject(connectionManager)
        }
        .padding(32)
    }

    // MARK: - Connecting

    @ViewBuilder
    private var connectingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting...")
                .font(.title2)
                .foregroundColor(.secondary)

            Button("Cancel") {
                connectionManager.disconnect()
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
    }

    // MARK: - Connected

    @ViewBuilder
    private var connectedView: some View {
        VStack(spacing: 20) {
            // Connection info
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)

                VStack(alignment: .leading) {
                    Text("Connected to \(connectionManager.connectedMacName)")
                        .font(.title3)
                        .bold()

                    Text("\(connectionManager.availableDisplays.count) display\(connectionManager.availableDisplays.count == 1 ? "" : "s") available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    connectionManager.disconnect()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Display list
            if connectionManager.availableDisplays.isEmpty {
                addDisplayPrompt
            } else {
                displayList
            }

            // Add display button
            if connectionManager.availableDisplays.count < VSConstants.maxDisplays {
                addDisplayButton
            }

            // Settings
            settingsSection

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Display List

    @ViewBuilder
    private var displayList: some View {
        VStack(spacing: 12) {
            ForEach(connectionManager.availableDisplays) { display in
                displayCard(display: display)
            }
        }
    }

    @ViewBuilder
    private func displayCard(display: VSDisplayInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(display.name)
                    .font(.headline)

                Text("\(display.config.width)×\(display.config.height) @ \(display.config.fps)fps")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let stats = connectionManager.displayStats[display.id] {
                    HStack(spacing: 8) {
                        Label("\(String(format: "%.0f", stats.fps)) fps", systemImage: "speedometer")
                        Label("\(String(format: "%.1f", stats.latencyMs)) ms", systemImage: "clock")
                        Label("\(stats.bitrate / 1_000_000) Mbps", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            if windowManager.activeWindows.contains(display.id) {
                Label("Open", systemImage: "display")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Button("Open Display") {
                    openWindow(id: "display", value: display.id)
                    windowManager.markWindowOpened(id: display.id)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Add Display

    @ViewBuilder
    private var addDisplayPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.display")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No displays yet")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Add a virtual display to start streaming")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
    }

    @ViewBuilder
    private var addDisplayButton: some View {
        Button {
            let nextID = UInt8((connectionManager.availableDisplays.map(\.id).max() ?? 0) + 1)
            connectionManager.requestDisplay(
                id: nextID,
                config: .hd1080
            )
        } label: {
            Label("Add Virtual Display", systemImage: "plus.display")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Settings

    @ViewBuilder
    private var settingsSection: some View {
        Toggle(isOn: $showPerformanceOverlay) {
            Label("Performance Overlay", systemImage: "chart.bar")
        }
        .toggleStyle(.switch)
        .onChange(of: showPerformanceOverlay) { newValue in
            connectionManager.showPerformanceOverlay = newValue
        }
    }
}
#endif
