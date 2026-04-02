import Foundation
import Observation
import Shared
import SwiftUI

@MainActor
@Observable
public final class VisionAppModel {
    public enum ConnectionState: Equatable {
        case idle
        case browsing
        case connecting(String)
        case connected(String)
        case reconnecting(String)
        case failed(String)

        public var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        public var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .browsing:
                return "Browsing for Macs"
            case .connecting(let name):
                return "Connecting to \(name)"
            case .connected(let name):
                return "Connected to \(name)"
            case .reconnecting(let name):
                return "Reconnecting to \(name)"
            case .failed(let message):
                return "Failed: \(message)"
            }
        }

        public var tint: Color {
            switch self {
            case .connected:
                return .green
            case .failed:
                return .red
            case .connecting, .reconnecting:
                return .orange
            case .idle, .browsing:
                return .secondary
            }
        }
    }

    public private(set) var discoveredServices: [VSDiscoveredService] = []
    public private(set) var connectionStatus: ConnectionState = .idle
    public var showPerformanceOverlay = true

    public let statisticsStore: VSStatisticsStore
    public let pairedHostStore: VSPairedHostStore
    public let reconnectCoordinator = VSVisionReconnectCoordinator()
    public let windowManager = VSWindowManager()
    public let displayStore = VSDisplayStore()

    private let client: VSVisionClient
    private var openWindowAction: OpenWindowAction?
    private var dismissWindowAction: DismissWindowAction?

    public init(
        client: VSVisionClient = VSVisionClient(),
        pairedHostStore: VSPairedHostStore = VSPairedHostStore(),
        statisticsStore: VSStatisticsStore = VSStatisticsStore()
    ) {
        self.client = client
        self.pairedHostStore = pairedHostStore
        self.statisticsStore = statisticsStore
        bindClient()
    }

    public var activeDisplays: [VSDisplayDescriptor] {
        displayStore.activeDisplays
    }

    public var isConnected: Bool {
        connectionStatus.isConnected
    }

    public var connectionSummary: String {
        connectionStatus.description
    }

    public func startBrowsing() {
        connectionStatus = .browsing
        client.startBrowsing()
    }

    public func stopBrowsing() {
        client.stopBrowsing()
        if case .browsing = connectionStatus {
            connectionStatus = .idle
        }
    }

    public func connect(to service: VSDiscoveredService) {
        connectionStatus = .connecting(service.name)
        pairedHostStore.remember(service: service)
        client.connect(to: service)
    }

    public func autoReconnectIfPossible() {
        guard let lastHost = pairedHostStore.lastPairedHost else { return }
        guard let service = discoveredServices.first(where: { $0.name == lastHost.name }) else { return }
        connectionStatus = .reconnecting(service.name)
        client.connect(to: service)
    }

    public func disconnect() {
        client.disconnect()
        displayStore.apply(displayList: [])
        statisticsStore.reset()
        windowManager.reset()
        connectionStatus = .idle
    }

    public func currentFrame(displayID: UInt8) -> VSDecodedFrame? {
        displayStore.frame(for: displayID)
    }

    public func handleInputTarget(displayID: UInt8, normalizedX: Double, normalizedY: Double) {
        windowManager.focusedDisplayID = displayID
        client.send(.inputMouseMove(.init(displayID: displayID, x: normalizedX, y: normalizedY)))
    }

    public func send(_ message: VSControlMessage) {
        client.send(message)
    }

    public func sendKey(
        displayID: UInt8,
        keyCode: UInt16,
        characters: String? = nil,
        isKeyDown: Bool,
        modifiers: VSKeyModifierFlags = []
    ) {
        client.send(.inputKey(.init(
            displayID: displayID,
            keyCode: keyCode,
            characters: characters,
            isKeyDown: isKeyDown,
            modifiers: modifiers
        )))
    }

    public func toggleOverlay(for displayID: UInt8) {
        windowManager.toggleOverlay(for: displayID)
    }

    private func bindClient() {
        client.onDiscoveredServices = { [weak self] services in
            Task { @MainActor in
                self?.discoveredServices = services
            }
        }

        client.onConnectionStateChanged = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .idle, .disconnected:
                    self?.connectionStatus = .idle
                case .browsing:
                    self?.connectionStatus = .browsing
                case .connecting(let name):
                    self?.connectionStatus = .connecting(name)
                case .connected(let name):
                    self?.connectionStatus = .connected(name)
                case .failed(let message):
                    self?.connectionStatus = .failed(message)
                }
            }
        }

        client.onDisplayList = { [weak self] displays in
            Task { @MainActor in
                self?.displayStore.apply(displayList: displays)
                for display in displays {
                    self?.openWindow(for: display.id)
                }
            }
        }

        client.onDisplayAdded = { [weak self] descriptor in
            Task { @MainActor in
                self?.displayStore.upsert(display: descriptor)
                self?.openWindow(for: descriptor.id)
            }
        }

        client.onDisplayRemoved = { [weak self] displayID in
            Task { @MainActor in
                self?.displayStore.remove(displayID: displayID)
                self?.statisticsStore.remove(displayID: displayID)
                self?.windowManager.releaseWindow(for: displayID)
            }
        }

        client.onFrameDecoded = { [weak self] frame in
            Task { @MainActor in
                self?.displayStore.set(frame: frame)
                _ = self?.windowManager.displayLayer(for: frame.displayID)
            }
        }

        client.onPerformanceSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                self?.statisticsStore.update(
                    VSStreamStatistics(
                        displayID: snapshot.displayID,
                        fps: snapshot.fps,
                        bitrateMbps: snapshot.bitrateMbps,
                        droppedFrames: Int(snapshot.droppedFrames),
                        roundTripLatencyMs: snapshot.roundTripLatencyMs
                    )
                )
            }
        }
    }

    public func configureWindowActions(openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        self.openWindowAction = openWindow
        self.dismissWindowAction = dismissWindow
    }

    private func openWindow(for displayID: UInt8) {
        let sceneID = windowManager.sceneID(for: displayID)
        openWindowAction?(id: sceneID)
    }

    private func closeWindow(for displayID: UInt8) {
        let sceneID = windowManager.sceneID(for: displayID)
        dismissWindowAction?(id: sceneID)
        windowManager.releaseWindow(for: displayID)
    }
}
