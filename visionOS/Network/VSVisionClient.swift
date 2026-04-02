// VSVisionClient.swift
// visionproscreensuptoinfinity
//
// Main visionOS-side connection manager. Handles pairing, display
// management, frame reception, decoding, and input forwarding.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(visionOS)
import Foundation
import Network
import Combine

/// Central connection manager for the visionOS app.
///
/// Manages the full lifecycle of a connection to a Mac companion:
/// 1. Connect via discovered Bonjour service
/// 2. Pair and negotiate displays
/// 3. Receive and decode HEVC video streams
/// 4. Forward input events back to Mac
/// 5. Handle disconnects and auto-reconnect
@MainActor
final class VSConnectionManager: ObservableObject {

    // MARK: - Types

    enum ConnectionState: String {
        case disconnected
        case connecting
        case connected
    }

    // MARK: - Published State

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var connectedMacName: String = ""
    @Published private(set) var availableDisplays: [VSDisplayInfo] = []
    @Published var displayStats: [UInt8: VSDisplayStats] = [:]
    @Published var showPerformanceOverlay: Bool = false

    // MARK: - Components

    let inputForwarder = VSInputForwarder()

    // MARK: - Private State

    private var controlConnection: VSControlConnection?
    private var videoTransport: VSVideoTransport?
    private var frameReassembler = VSFrameReassembler()
    private var decoders: [UInt8: VSHEVCDecoder] = [:]
    private var frameCallbacks: [UInt8: (CVPixelBuffer) -> Void] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTimer: Timer?
    private var lastHeartbeatReceived: Date = Date()
    private var reconnectAttempts: Int = 0
    private var lastConnectedService: VSBonjourBrowser.DiscoveredService?

    // Stats tracking
    private var frameCounters: [UInt8: UInt64] = [:]
    private var lastStatsTime: [UInt8: Date] = [:]
    private var droppedPacketCounters: [UInt8: Int] = [:]
    private var lastSequenceNumbers: [UInt8: UInt32] = [:]

    // MARK: - Connection

    /// Connect to a discovered Mac service.
    func connect(to service: VSBonjourBrowser.DiscoveredService) {
        guard connectionState == .disconnected else { return }

        connectionState = .connecting
        lastConnectedService = service

        let connection = VSControlConnection()
        self.controlConnection = connection

        // Wire up input forwarder
        inputForwarder.controlConnection = connection

        // Set up message handler
        connection.onMessage = { [weak self] envelope in
            self?.handleControlMessage(envelope)
        }

        connection.onDisconnect = { [weak self] error in
            Task { @MainActor in
                self?.handleDisconnect(error: error)
            }
        }

        // Connect to the service endpoint
        connection.connect(to: service.endpoint)

        // Monitor connection state
        connection.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .connected:
                    self.sendPairRequest()
                case .failed(let reason):
                    print("[VSConnectionManager] Connection failed: \(reason)")
                    self.connectionState = .disconnected
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    /// Disconnect from the Mac server.
    func disconnect() {
        // Send disconnect message
        controlConnection?.send(type: .disconnect, message: VSDisconnect(reason: nil))

        cleanup()
        connectionState = .disconnected
        reconnectAttempts = 0
    }

    // MARK: - Display Management

    /// Request a new virtual display from the Mac server.
    func requestDisplay(id: UInt8, config: VSVideoConfig) {
        let message = VSDisplayAdd(
            displayID: id,
            width: config.width,
            height: config.height,
            name: "VisionScreen \(id)"
        )
        controlConnection?.send(type: .displayAdd, message: message)
    }

    /// Request removal of a virtual display.
    func removeDisplay(id: UInt8) {
        let message = VSDisplayRemove(displayID: id)
        controlConnection?.send(type: .displayRemove, message: message)
    }

    // MARK: - Frame Reception

    /// Start receiving decoded frames for a specific display.
    ///
    /// - Parameters:
    ///   - displayID: The display to receive frames for.
    ///   - callback: Called on each decoded frame with the CVPixelBuffer.
    func startReceivingFrames(for displayID: UInt8, callback: @escaping (CVPixelBuffer) -> Void) {
        frameCallbacks[displayID] = callback

        // Create decoder if needed
        if decoders[displayID] == nil {
            let decoder = VSHEVCDecoder()
            decoder.onDecodedFrame = { [weak self] pixelBuffer in
                DispatchQueue.main.async {
                    self?.frameCallbacks[displayID]?(pixelBuffer)
                    self?.updateStats(displayID: displayID)
                }
            }
            decoders[displayID] = decoder
        }
    }

    /// Stop receiving frames for a specific display.
    func stopReceivingFrames(for displayID: UInt8) {
        frameCallbacks.removeValue(forKey: displayID)
        decoders[displayID]?.teardown()
        decoders.removeValue(forKey: displayID)
    }

    // MARK: - Control Message Handling

    private func handleControlMessage(_ envelope: VSMessageEnvelope) {
        switch envelope.type {
        case .pairAccept:
            handlePairAccept(envelope: envelope)

        case .pairReject:
            handlePairReject(envelope: envelope)

        case .displayList:
            handleDisplayList(envelope: envelope)

        case .heartbeat:
            lastHeartbeatReceived = Date()

        case .error:
            if let error = try? envelope.decode(as: VSError.self) {
                print("[VSConnectionManager] Server error: \(error.message)")
            }

        case .disconnect:
            handleDisconnect(error: nil)

        default:
            print("[VSConnectionManager] Unhandled message type: \(envelope.type)")
        }
    }

    private func handlePairAccept(envelope: VSMessageEnvelope) {
        do {
            let accept = try envelope.decode(as: VSPairAccept.self)
            connectedMacName = accept.macName
            availableDisplays = accept.displays
            connectionState = .connected
            reconnectAttempts = 0

            // Start video transport
            startVideoReceiver()

            // Start heartbeat
            startHeartbeat()

            print("[VSConnectionManager] ✅ Paired with '\(accept.macName)', \(accept.displays.count) displays")

        } catch {
            print("[VSConnectionManager] Failed to decode pair accept: \(error)")
        }
    }

    private func handlePairReject(envelope: VSMessageEnvelope) {
        if let reject = try? envelope.decode(as: VSPairReject.self) {
            print("[VSConnectionManager] Pairing rejected: \(reject.reason)")
        }
        connectionState = .disconnected
    }

    private func handleDisplayList(envelope: VSMessageEnvelope) {
        do {
            let list = try envelope.decode(as: VSDisplayList.self)
            availableDisplays = list.displays
        } catch {
            print("[VSConnectionManager] Failed to decode display list: \(error)")
        }
    }

    // MARK: - Pairing

    private func sendPairRequest() {
        let request = VSPairRequest(
            deviceName: "Apple Vision Pro",
            protocolVersion: VSPairRequest.currentProtocolVersion
        )
        controlConnection?.send(type: .pairRequest, message: request)
    }

    // MARK: - Video Transport

    private func startVideoReceiver() {
        let transport = VSVideoTransport()
        self.videoTransport = transport

        // Set up frame reassembler
        frameReassembler.onFrameComplete = { [weak self] displayID, seqNum, frameData, isKeyframe in
            self?.handleCompleteFrame(displayID: displayID, sequenceNumber: seqNum, data: frameData, isKeyframe: isKeyframe)
        }

        // Route incoming packets to reassembler
        transport.onPacketReceived = { [weak self] packet in
            self?.trackPacketStats(packet: packet)
            self?.frameReassembler.receive(packet: packet)
        }

        // Start listening for UDP video packets
        // Each display gets its own port: base port + display ID
        let basePort = NWEndpoint.Port(rawValue: VSConstants.videoPort)!
        transport.startListening(port: basePort)
    }

    private func handleCompleteFrame(displayID: UInt8, sequenceNumber: UInt32, data: Data, isKeyframe: Bool) {
        guard let decoder = decoders[displayID] else { return }
        decoder.decode(data: data, isKeyframe: isKeyframe)
    }

    // MARK: - Stats Tracking

    private func trackPacketStats(packet: VSFramePacket) {
        let displayID = packet.header.displayID
        let seqNum = packet.header.sequenceNumber

        // Track dropped packets
        if let lastSeq = lastSequenceNumbers[displayID] {
            if seqNum > lastSeq + 1 {
                let dropped = Int(seqNum - lastSeq - 1)
                droppedPacketCounters[displayID, default: 0] += dropped

                // Request keyframe if too many drops
                if droppedPacketCounters[displayID, default: 0] >= VSConstants.keyframeRequestThreshold {
                    requestKeyframe(displayID: displayID)
                    droppedPacketCounters[displayID] = 0
                }
            }
        }
        lastSequenceNumbers[displayID] = seqNum
    }

    private func updateStats(displayID: UInt8) {
        frameCounters[displayID, default: 0] += 1

        let now = Date()
        let elapsed = now.timeIntervalSince(lastStatsTime[displayID] ?? now)

        if elapsed >= 1.0 {
            let fps = Double(frameCounters[displayID, default: 0]) / elapsed
            let config = availableDisplays.first(where: { $0.id == displayID })?.config ?? .hd1080

            displayStats[displayID] = VSDisplayStats(
                displayID: displayID,
                fps: fps,
                bitrate: config.bitrate,
                latencyMs: 0,  // TODO: measure actual round-trip latency
                droppedFrames: droppedPacketCounters[displayID, default: 0],
                totalFrames: frameCounters[displayID, default: 0]
            )

            frameCounters[displayID] = 0
            lastStatsTime[displayID] = now
        }
    }

    private func requestKeyframe(displayID: UInt8) {
        let message = VSRequestKeyframe(displayID: displayID)
        controlConnection?.send(type: .requestKeyframe, message: message)
        print("[VSConnectionManager] Requested keyframe for display \(displayID)")
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: VSConstants.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendHeartbeat()
            }
        }
    }

    private func sendHeartbeat() {
        controlConnection?.send(type: .heartbeat, message: VSHeartbeat())

        // Check for connection timeout
        let elapsed = Date().timeIntervalSince(lastHeartbeatReceived)
        if elapsed > VSConstants.connectionTimeout {
            print("[VSConnectionManager] Connection timed out")
            handleDisconnect(error: nil)
        }
    }

    // MARK: - Disconnect & Reconnect

    private func handleDisconnect(error: Error?) {
        print("[VSConnectionManager] Disconnected\(error.map { ": \($0)" } ?? "")")

        cleanup()

        // Attempt auto-reconnect
        if reconnectAttempts < VSConstants.maxReconnectAttempts,
           let service = lastConnectedService {
            reconnectAttempts += 1
            let delay = VSConstants.reconnectBaseDelay * pow(2.0, Double(reconnectAttempts - 1))
            print("[VSConnectionManager] Reconnecting in \(delay)s (attempt \(reconnectAttempts)/\(VSConstants.maxReconnectAttempts))")

            connectionState = .connecting

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.connectionState == .connecting else { return }
                self.connectionState = .disconnected
                self.connect(to: service)
            }
        } else {
            connectionState = .disconnected
        }
    }

    private func cleanup() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        controlConnection?.disconnect()
        controlConnection = nil
        videoTransport?.stop()
        videoTransport = nil
        frameReassembler.reset()

        for (_, decoder) in decoders {
            decoder.teardown()
        }
        decoders.removeAll()
        frameCallbacks.removeAll()
        cancellables.removeAll()

        frameCounters.removeAll()
        lastStatsTime.removeAll()
        droppedPacketCounters.removeAll()
        lastSequenceNumbers.removeAll()
    }
}
#endif
