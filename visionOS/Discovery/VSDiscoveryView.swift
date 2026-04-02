// VSDiscoveryView.swift
// visionproscreensuptoinfinity
//
// Bonjour service discovery UI for finding Mac companions.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(visionOS)
import SwiftUI
import Network

/// View that discovers and lists available Mac companion apps on the network.
struct VSDiscoveryView: View {

    @EnvironmentObject var connectionManager: VSConnectionManager
    @StateObject private var browser = VSBonjourBrowser()

    @AppStorage("lastConnectedMacID") private var lastConnectedMacID: String = ""

    var body: some View {
        VStack(spacing: 16) {
            // Search status
            HStack {
                if browser.state == .browsing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching for Macs...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundColor(.orange)
                    Text("Not searching")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button {
                    if browser.state == .browsing {
                        browser.stopBrowsing()
                    } else {
                        browser.startBrowsing()
                    }
                } label: {
                    Image(systemName: browser.state == .browsing ? "stop.circle" : "arrow.clockwise.circle")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Discovered services
            if browser.discoveredServices.isEmpty {
                emptyState
            } else {
                serviceList
            }
        }
        .onAppear {
            browser.startBrowsing()
        }
        .onDisappear {
            browser.stopBrowsing()
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No Macs Found")
                .font(.headline)

            Text("Make sure the VisionScreen Mac app is running\nand both devices are on the same Wi-Fi network.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                browser.stopBrowsing()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    browser.startBrowsing()
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding(20)
    }

    // MARK: - Service List

    @ViewBuilder
    private var serviceList: some View {
        VStack(spacing: 8) {
            ForEach(browser.discoveredServices) { service in
                serviceRow(service: service)
            }
        }
    }

    @ViewBuilder
    private func serviceRow(service: VSBonjourBrowser.DiscoveredService) -> some View {
        HStack {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.headline)

                if service.id == lastConnectedMacID {
                    Text("Previously connected")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Button("Connect") {
                lastConnectedMacID = service.id
                connectionManager.connect(to: service)
            }
            .buttonStyle(.borderedProminent)
            .disabled(connectionManager.connectionState == .connecting)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}
#endif
