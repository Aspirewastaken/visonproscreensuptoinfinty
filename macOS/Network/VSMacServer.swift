// VSMacServer.swift
// visionproscreensuptoinfinity
//
// Main server coordinating all macOS-side functionality:
// Bonjour advertising, display management, capture, encoding,
// and streaming to connected visionOS clients.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(macOS)
import Foundation
import Network
import Combine

/// Orchestrates the entire macOS companion pipeline:
///
/// 1. Advertises via Bonjour
/// 2. Accepts TCP control connections from Vision Pro clients
/// 3. Creates virtual displays on demand
/// 4. Captures each display via ScreenCaptureKit
/// 5. Encodes captured frames with HEVC hardware encoder
/// 6. Packetizes and sends encoded frames over UDP
/// 7. Receives input events from clients and injects them
final class VSMacServer: ObservableObject {

    // MARK: - Types

    /// Per-display streaming pipeline.
    struct DisplayPipeline {
        let id: UInt8
        let config: VSVideoConfig
        let capture: VSScreenCapture
        let encoder: VSHEVCEncoder
        var sequenceNumber: UInt32 = 0
        var frameCount: UInt64 = 0
        var lastStatsTime: Date = Date()
        var fps: Double = 0
    }

    enum ServerState: String {
        case stopped
        case starting
        case running
        case error
    }

    // MARK: - Published State

    @Published private(set) var state: ServerState = .stopped
    @Published private(set) var connectedClients: Int = 0
    @Published private(set) var displayPipelines: [UInt8: DisplayPipeline] = [:]
    @Published private(set) var macName: String = ""

    // MARK: - Components

    let advertiser = VSBonjourAdvertiser()
    let displayManager = VSVirtualDisplayManager()
    let inputInjector = VSInputInjector()

    // MARK: - Private State

    private var clientConnections: [ObjectIdentifier: ClientSession] = [:]
    private var videoTransports: [UInt8: VSVideoTransport] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let serverQueue = DispatchQueue(label: "com.visionproscreens.server", qos: .userInitiated)

    /// Tracks a connected client session.
    private struct ClientSession {
        let controlConnection: VSControlConnection
        var subscribedDisplays: Set<UInt8> = []
        var clientEndpoint: NWEndpoint?
    }

    // MARK: - Initialization

    init() {
        macName = Host.current().localizedName ?? "Mac"
    }

    // MARK: - Server Lifecycle

    /// Start the server: begin Bonjour advertising and accept connections.
    func start() {
        guard state != .running else { return }

        state = .starting

        // Request accessibility permissions early
        if !VSInputInjector.isAccessibilityGranted {
            VSInputInjector.requestAccessibilityPermission()
        }

        // Set up Bonjour advertiser
        advertiser.onNewConnection = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        advertiser.startAdvertising(name: macName)

        // Monitor advertiser state
        advertiser.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] advState in
                switch advState {
                case .ready:
                    self?.state = .running
                case .failed:
                    self?.state = .error
                default:
                    break
                }
            }
            .store(in: &cancellables)

        print("[VSMacServer] ✅ Server starting as '\(macName)'")
    }

    /// Stop the server and clean up all resources.
    func stop() {
        // Stop all display pipelines
        for (id, _) in displayPipelines {
            stopDisplayPipeline(id: id)
        }

        // Disconnect all clients
        for (_, session) in clientConnections {
            session.controlConnection.disconnect()
        }
        clientConnections.removeAll()

        // Stop advertising
        advertiser.stopAdvertising()

        // Remove all virtual displays
        displayManager.removeAllDisplays()

        // Stop video transports
        for (_, transport) in videoTransports {
            transport.stop()
        }
        videoTransports.removeAll()

        state = .stopped
        connectedClients = 0

        print("[VSMacServer] Server stopped")
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let controlConnection = VSControlConnection(connection: nwConnection)
        let sessionID = ObjectIdentifier(controlConnection)

        var session = ClientSession(controlConnection: controlConnection)
        session.clientEndpoint = nwConnection.endpoint

        controlConnection.onMessage = { [weak self] envelope in
            self?.handleControlMessage(envelope, sessionID: sessionID)
        }

        controlConnection.onDisconnect = { [weak self] error in
            self?.handleClientDisconnect(sessionID: sessionID, error: error)
        }

        controlConnection.start()

        clientConnections[sessionID] = session

        DispatchQueue.main.async {
            self.connectedClients = self.clientConnections.count
        }

        print("[VSMacServer] New client connected from \(nwConnection.endpoint)")
    }

    private func handleClientDisconnect(sessionID: ObjectIdentifier, error: Error?) {
        guard let session = clientConnections.removeValue(forKey: sessionID) else { return }

        // Stop streaming for any displays this client was subscribed to
        for displayID in session.subscribedDisplays {
            stopDisplayPipeline(id: displayID)
            try? displayManager.removeDisplay(id: displayID)
        }

        DispatchQueue.main.async {
            self.connectedClients = self.clientConnections.count
        }

        print("[VSMacServer] Client disconnected\(error.map { ": \($0)" } ?? "")")
    }

    // MARK: - Control Message Handling

    private func handleControlMessage(_ envelope: VSMessageEnvelope, sessionID: ObjectIdentifier) {
        guard let session = clientConnections[sessionID] else { return }

        switch envelope.type {
        case .pairRequest:
            handlePairRequest(envelope: envelope, session: session, sessionID: sessionID)

        case .displayAdd:
            handleDisplayAdd(envelope: envelope, session: session, sessionID: sessionID)

        case .displayRemove:
            handleDisplayRemove(envelope: envelope, session: session, sessionID: sessionID)

        case .inputMouse:
            handleInputMouse(envelope: envelope)

        case .inputKey:
            handleInputKey(envelope: envelope)

        case .inputScroll:
            handleInputScroll(envelope: envelope)

        case .requestKeyframe:
            handleKeyframeRequest(envelope: envelope)

        case .heartbeat:
            // Echo heartbeat back for latency measurement
            session.controlConnection.send(
                type: .heartbeat,
                message: VSHeartbeat()
            )

        case .disconnect:
            handleClientDisconnect(sessionID: sessionID, error: nil)

        default:
            print("[VSMacServer] Unhandled message type: \(envelope.type)")
        }
    }

    // MARK: - Pair Request

    private func handlePairRequest(envelope: VSMessageEnvelope, session: ClientSession, sessionID: ObjectIdentifier) {
        do {
            let request = try envelope.decode(as: VSPairRequest.self)
            print("[VSMacServer] Pair request from '\(request.deviceName)' (protocol v\(request.protocolVersion))")

            // Accept the pairing
            let response = VSPairAccept(
                macName: macName,
                displays: displayManager.getDisplayInfoList(),
                protocolVersion: VSPairRequest.currentProtocolVersion
            )

            session.controlConnection.send(type: .pairAccept, message: response)

        } catch {
            print("[VSMacServer] Failed to decode pair request: \(error)")
            session.controlConnection.send(
                type: .pairReject,
                message: VSPairReject(reason: "Invalid pair request")
            )
        }
    }

    // MARK: - Display Management

    private func handleDisplayAdd(envelope: VSMessageEnvelope, session: ClientSession, sessionID: ObjectIdentifier) {
        do {
            let request = try envelope.decode(as: VSDisplayAdd.self)
            let config = VSVideoConfig(
                width: request.width,
                height: request.height,
                fps: VSConstants.defaultFPS,
                bitrate: VSConstants.defaultBitrate,
                keyframeInterval: VSConstants.defaultKeyframeInterval
            )

            print("[VSMacServer] Adding display \(request.displayID): \(request.width)×\(request.height)")

            // Create virtual display
            let systemDisplayID = try displayManager.createDisplay(id: request.displayID, config: config)

            // Subscribe this client to the display
            clientConnections[sessionID]?.subscribedDisplays.insert(request.displayID)

            // Start the capture → encode → stream pipeline
            startDisplayPipeline(id: request.displayID, config: config, systemDisplayID: systemDisplayID, session: session)

            // Send updated display list
            let displayList = VSDisplayList(displays: displayManager.getDisplayInfoList())
            session.controlConnection.send(type: .displayList, message: displayList)

        } catch {
            print("[VSMacServer] Failed to add display: \(error)")
            session.controlConnection.send(
                type: .error,
                message: VSError(message: error.localizedDescription, code: nil)
            )
        }
    }

    private func handleDisplayRemove(envelope: VSMessageEnvelope, session: ClientSession, sessionID: ObjectIdentifier) {
        do {
            let request = try envelope.decode(as: VSDisplayRemove.self)
            print("[VSMacServer] Removing display \(request.displayID)")

            stopDisplayPipeline(id: request.displayID)
            try displayManager.removeDisplay(id: request.displayID)

            clientConnections[sessionID]?.subscribedDisplays.remove(request.displayID)

            // Send updated display list
            let displayList = VSDisplayList(displays: displayManager.getDisplayInfoList())
            session.controlConnection.send(type: .displayList, message: displayList)

        } catch {
            print("[VSMacServer] Failed to remove display: \(error)")
        }
    }

    // MARK: - Streaming Pipeline

    private func startDisplayPipeline(id: UInt8, config: VSVideoConfig, systemDisplayID: CGDirectDisplayID, session: ClientSession) {
        let capture = VSScreenCapture()
        let encoder = VSHEVCEncoder()

        // Configure encoder
        do {
            try encoder.configure(config: config)
        } catch {
            print("[VSMacServer] ❌ Failed to configure encoder for display \(id): \(error)")
            return
        }

        // Set up video transport for this display
        let transport = VSVideoTransport()

        // Determine client endpoint for UDP video sending
        if let endpoint = session.clientEndpoint {
            switch endpoint {
            case .hostPort(let host, _):
                let videoPort = NWEndpoint.Port(rawValue: VSConstants.videoPort + UInt16(id))!
                transport.connectForSending(to: host, port: videoPort)
            default:
                // Try to extract host from service endpoint
                print("[VSMacServer] ⚠️ Cannot determine client host for UDP video")
            }
        }

        videoTransports[id] = transport

        // Wire up pipeline: capture → encoder → packetize → send
        var pipeline = DisplayPipeline(
            id: id,
            config: config,
            capture: capture,
            encoder: encoder
        )

        // Capture → Encoder
        capture.onFrame = { [weak encoder] sampleBuffer in
            encoder?.encode(sampleBuffer: sampleBuffer)
        }

        // Encoder → Packetize → Send
        encoder.onEncodedFrame = { [weak self, weak transport] data, isKeyframe in
            guard let self = self, let transport = transport else { return }

            var currentPipeline = self.displayPipelines[id] ?? pipeline
            currentPipeline.sequenceNumber += 1
            currentPipeline.frameCount += 1

            // Update FPS stats every second
            let now = Date()
            let elapsed = now.timeIntervalSince(currentPipeline.lastStatsTime)
            if elapsed >= 1.0 {
                currentPipeline.fps = Double(currentPipeline.frameCount) / elapsed
                currentPipeline.frameCount = 0
                currentPipeline.lastStatsTime = now
            }

            self.displayPipelines[id] = currentPipeline

            // Packetize the encoded frame
            let packets = VSFramePacket.packetize(
                frameData: data,
                sequenceNumber: currentPipeline.sequenceNumber,
                displayID: id,
                isKeyframe: isKeyframe
            )

            // Send all packets
            transport.send(packets: packets)
        }

        displayPipelines[id] = pipeline

        // Start capture (async)
        Task {
            do {
                try await capture.startCapture(displayID: systemDisplayID, config: config)
                print("[VSMacServer] ✅ Pipeline started for display \(id)")
            } catch {
                print("[VSMacServer] ❌ Failed to start capture for display \(id): \(error)")
            }
        }
    }

    private func stopDisplayPipeline(id: UInt8) {
        guard let pipeline = displayPipelines.removeValue(forKey: id) else { return }

        Task {
            await pipeline.capture.stopCapture()
        }
        pipeline.encoder.teardown()
        videoTransports[id]?.stop()
        videoTransports.removeValue(forKey: id)

        print("[VSMacServer] Pipeline stopped for display \(id)")
    }

    // MARK: - Input Handling

    private func handleInputMouse(envelope: VSMessageEnvelope) {
        do {
            let input = try envelope.decode(as: VSInputMouse.self)
            guard let systemDisplayID = displayManager.getSystemDisplayID(for: input.displayID) else {
                return
            }
            inputInjector.handleMouseInput(input, displayID: systemDisplayID)
        } catch {
            print("[VSMacServer] Failed to decode mouse input: \(error)")
        }
    }

    private func handleInputKey(envelope: VSMessageEnvelope) {
        do {
            let input = try envelope.decode(as: VSInputKey.self)
            inputInjector.handleKeyInput(input)
        } catch {
            print("[VSMacServer] Failed to decode key input: \(error)")
        }
    }

    private func handleInputScroll(envelope: VSMessageEnvelope) {
        do {
            let input = try envelope.decode(as: VSInputScroll.self)
            inputInjector.handleScrollInput(input)
        } catch {
            print("[VSMacServer] Failed to decode scroll input: \(error)")
        }
    }

    private func handleKeyframeRequest(envelope: VSMessageEnvelope) {
        do {
            let request = try envelope.decode(as: VSRequestKeyframe.self)
            displayPipelines[request.displayID]?.encoder.forceKeyframe()
            print("[VSMacServer] Keyframe requested for display \(request.displayID)")
        } catch {
            print("[VSMacServer] Failed to decode keyframe request: \(error)")
        }
    }

    deinit {
        stop()
    }
}
#endif
