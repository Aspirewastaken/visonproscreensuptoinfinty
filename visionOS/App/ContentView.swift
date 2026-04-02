import Shared
import SwiftUI

public struct ContentView: View {
    @Environment(VisionAppModel.self) private var appModel

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(VSConstants.productName)
                        .font(.largeTitle.bold())
                    Text("Discover your Mac companion and stream up to four displays into independent windows.")
                        .foregroundStyle(.secondary)
                }

                connectionBanner

                if appModel.discoveredServices.isEmpty {
                    ContentUnavailableView(
                        "No Macs Found",
                        systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                        description: Text("Make sure the macOS companion is running on the same Wi‑Fi network and Local Network permission has been granted.")
                    )
                } else {
                    VSDiscoveryView(services: appModel.discoveredServices) { service in
                        appModel.connect(to: service)
                    }
                }

                HStack {
                    Button("Refresh") {
                        appModel.startBrowsing()
                    }

                    Button("Disconnect", role: .destructive) {
                        appModel.disconnect()
                    }
                    .disabled(!appModel.isConnected)
                }
            }
            .padding(24)
            .navigationTitle("Mac Discovery")
        }
        .task {
            appModel.startBrowsing()
            appModel.autoReconnectIfPossible()
        }
    }

    private var connectionBanner: some View {
        HStack {
            Image(systemName: appModel.isConnected ? "dot.radiowaves.left.and.right" : "wifi.slash")
                .foregroundStyle(appModel.isConnected ? .green : .secondary)
            Text(appModel.connectionSummary)
                .foregroundStyle(appModel.connectionStatus.tint)
        }
    }
}
