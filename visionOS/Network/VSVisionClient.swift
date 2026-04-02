import Foundation
import Network
import Observation
import Shared

@MainActor
@Observable
public final class VSVisionClient {
    public enum State: Equatable, Sendable {
        case idle
        case browsing
        case connecting(String)
        case connected(String)
        case disconnected
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var discoveredServices: [VSDiscoveredService] = []
    public private(set) var activeDisplays: [VSDisplayDescriptor] = []

    private let browser: VSBonjourBrowser
    private let statisticsStore: VSStatisticsStore
    private let queue = DispatchQueue(label: VSConstants.Network.tcpQueueLabel + ".vision-client")

    private var controlChannel: VSTCPControlChannel?
    private var udpChannel: VSUDPVideoChannel?
    private var reassembler = VSFrameReassembler.State()
    private let decoder = VSHEVCDecoder()

    public var onDiscoveredServices: (@Sendable ([VSDiscoveredService]) -> Void)?
    public var onConnectionStateChanged: (@Sendable (State) -> Void)?
    public var onDisplayList: (@Sendable ([VSDisplayDescriptor]) -> Void)?
    public var onDisplayAdded: (@Sendable (VSDisplayDescriptor) -> Void)?
    public var onDisplayRemoved: (@Sendable (UInt8) -> Void)?
    public var onPerformanceSnapshot: (@Sendable (VSPerformanceSnapshot) -> Void)?
    public var onFrameDecoded: (@Sendable (VSDecodedFrame) -> Void)?

    public init(
        browser: VSBonjourBrowser = VSBonjourBrowser(),
        statisticsStore: VSStatisticsStore = VSStatisticsStore()
    ) {
        self.browser = browser
        self.statisticsStore = statisticsStore
        decoder.onFrame = { [weak self] frame in
            self?.onFrameDecoded?(frame)
        }
        wireBrowser()
    }

    public func startBrowsing() {
        updateState(.browsing)
        browser.start()
    }

    public func stopBrowsing() {
        browser.stop()
        discoveredServices = []
        onDiscoveredServices?([])
        if case .browsing = state {
            updateState(.idle)
        }
    }

    public func connect(to service: VSDiscoveredService) {
        updateState(.connecting(service.name))

        let controlConnection = NWConnection(to: service.endpoint, using: .tcp)
        let controlChannel = VSTCPControlChannel(connection: controlConnection, queue: queue)
        controlChannel.onStateChange = { [weak self] newState in
            Task { @MainActor in
                self?.handleControlState(newState, serviceName: service.name)
            }
        }
        controlChannel.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handleControlMessage(message)
            }
        }
        controlChannel.start()
        self.controlChannel = controlChannel

        let videoConnection = NWConnection(to: service.endpoint, using: .udp)
        let udpChannel = VSUDPVideoChannel(connection: videoConnection, queue: queue)
        udpChannel.onStateChange = { [weak self] newState in
            Task { @MainActor in
                self?.handleUDPState(newState)
            }
        }
        udpChannel.onPacket = { [weak self] packet in
            Task { @MainActor in
                self?.handleFramePacket(packet)
            }
        }
        udpChannel.start()
        self.udpChannel = udpChannel
    }

    public func disconnect() {
        controlChannel?.cancel()
        udpChannel?.cancel()
        controlChannel = nil
        udpChannel = nil
        activeDisplays = []
        reassembler = VSFrameReassembler.State()
        updateState(.disconnected)
    }

    public func send(_ message: VSControlMessage) {
        controlChannel?.send(message)
    }

    private func wireBrowser() {
        browser.onStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .idle:
                    if case .browsing = self.state {
                        self.updateState(.idle)
                    }
                case .browsing:
                    self.updateState(.browsing)
                case .failed(let message):
                    self.updateState(.failed(message))
                }
            }
        }

        browser.onServicesChanged = { [weak self] services in
            Task { @MainActor in
                self?.discoveredServices = services
                self?.onDiscoveredServices?(services)
            }
        }
    }

    private func handleControlState(_ connectionState: VSConnectionState, serviceName: String) {
        switch connectionState {
        case .ready:
            updateState(.connected(serviceName))
        case .failed(let message):
            updateState(.failed(message))
        case .cancelled:
            updateState(.disconnected)
        case .waiting, .preparing, .setup:
            break
        }
    }

    private func handleUDPState(_ connectionState: VSConnectionState) {
        if case .failed(let message) = connectionState {
            updateState(.failed(message))
        }
    }

    private func handleControlMessage(_ message: VSControlMessage) {
        switch message {
        case .displayList(let list):
            activeDisplays = list.displays
            onDisplayList?(list.displays)
            for display in list.displays {
                onDisplayAdded?(display)
            }
        case .displayAdded(let descriptor):
            activeDisplays.removeAll { $0.id == descriptor.id }
            activeDisplays.append(descriptor)
            activeDisplays.sort { $0.id < $1.id }
            onDisplayAdded?(descriptor)
        case .displayRemoved(let removal):
            activeDisplays.removeAll { $0.id == removal.displayID }
            statisticsStore.remove(displayID: removal.displayID)
            onDisplayRemoved?(removal.displayID)
        case .performancePong(let pong):
            let roundTripMs = max((Date().timeIntervalSince1970 - pong.echoedSentAt) * 1_000, 0)
            let displayID = activeDisplays.first?.id ?? 1
            let snapshot = VSPerformanceSnapshot(
                displayID: displayID,
                fps: statisticsStore.snapshots[displayID]?.fps ?? 0,
                bitrateMbps: statisticsStore.snapshots[displayID]?.bitrateMbps ?? 0,
                roundTripLatencyMs: roundTripMs,
                droppedFrames: UInt32(statisticsStore.snapshots[displayID]?.droppedFrames ?? 0)
            )
            statisticsStore.update(
                VSStreamStatistics(
                    displayID: snapshot.displayID,
                    fps: snapshot.fps,
                    bitrateMbps: snapshot.bitrateMbps,
                    droppedFrames: Int(snapshot.droppedFrames),
                    roundTripLatencyMs: snapshot.roundTripLatencyMs
                )
            )
            onPerformanceSnapshot?(snapshot)
        case .pairAccept, .pairReject, .inputMouseMove, .inputMouseButton, .inputScroll, .inputKey, .requestKeyframe, .performancePing:
            break
        }
    }

    private func handleFramePacket(_ packet: VSFramePacket) {
        if let frame = reassembler.insert(packet) {
            decoder.decode(frame)
        }
    }

    private func updateState(_ newState: State) {
        state = newState
        onConnectionStateChanged?(newState)
    }
}
