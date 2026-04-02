import AppKit
import Shared
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            permissionsSection
            settingsSection
            displaysSection
            statsSection

            if let error = model.serverErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            HStack {
                Button("Refresh") {
                    Task { await model.refreshDisplays() }
                }
                .buttonStyle(.bordered)

                Button(model.isServerRunning ? "Stop Server" : "Start Server") {
                    model.toggleServer()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .task {
            await model.start()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(VSConstants.productName)
                .font(.headline)
            Text(model.connectionStateDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 6) {
                permissionRow("Screen Recording", granted: model.permissions.status.screenRecordingGranted)
                permissionRow("Accessibility", granted: model.permissions.status.accessibilityGranted)
                permissionRow("Local Network", granted: model.permissions.status.localNetworkReady)

                if !model.permissions.status.accessibilityGranted {
                    Button("Request Accessibility") {
                        model.permissions.requestAccessibilityPermission()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var settingsSection: some View {
        GroupBox("Settings") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Backend", selection: Binding(
                    get: { model.settings.backendPreference },
                    set: { model.settings.updateBackendPreference($0) }
                )) {
                    ForEach(MacSettingsStore.DisplayBackendPreference.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

                Picker("Resolution", selection: Binding(
                    get: { model.settings.selectedVideoConfig.resolution },
                    set: { model.settings.updateResolution($0) }
                )) {
                    ForEach(VSVideoConfig.resolutionPresets) { preset in
                        Text(preset.label).tag(preset)
                    }
                }

                Picker("Bitrate", selection: Binding(
                    get: { model.settings.selectedVideoConfig.bitrate },
                    set: { model.settings.updateBitrate($0) }
                )) {
                    ForEach(VSVideoConfig.bitratePresets) { preset in
                        Text(preset.label).tag(preset)
                    }
                }

                Stepper(
                    "Displays: \(model.settings.desiredDisplayCount)",
                    value: Binding(
                        get: { model.settings.desiredDisplayCount },
                        set: { model.settings.desiredDisplayCount = $0 }
                    ),
                    in: 1 ... VSConstants.maxDisplayCount
                )
            }
        }
    }

    private var displaysSection: some View {
        GroupBox("Displays") {
            VStack(alignment: .leading, spacing: 8) {
                if model.displays.isEmpty {
                    Text("No displays active.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.displays) { display in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(display.name)
                                Text("\(display.width)×\(display.height) @ \(display.refreshRate.formatted(.number.precision(.fractionLength(0)))) Hz")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(display.isVirtual ? "Virtual" : "Physical")
                                .font(.caption)
                        }
                    }
                }

                HStack {
                    Button("Add Display") {
                        Task { await model.addDisplay() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canAddDisplay)

                    Button("Remove Display") {
                        guard let last = model.displays.last else { return }
                        Task { await model.removeDisplay(last) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.displays.isEmpty)
                }
            }
        }
    }

    private var statsSection: some View {
        GroupBox("Performance") {
            if model.statistics.snapshots.isEmpty {
                Text("Waiting for stream statistics…")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(
                        Array(model.statistics.snapshots.values).sorted(by: { $0.displayID < $1.displayID }),
                        id: \.displayID
                    ) { snapshot in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Display \(snapshot.displayID)")
                                .font(.subheadline.weight(.medium))
                            Text(
                                "FPS \(snapshot.fps.formatted(.number.precision(.fractionLength(1)))) · " +
                                "\(snapshot.bitrateMbps.formatted(.number.precision(.fractionLength(1)))) Mbps · " +
                                "RTT \(snapshot.roundTripLatencyMs.formatted(.number.precision(.fractionLength(1)))) ms"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func permissionRow(_ label: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(label)
        }
    }
}
