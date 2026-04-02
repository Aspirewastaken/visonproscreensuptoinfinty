// VSConnection.swift
// visionproscreensuptoinfinity
//
// NWConnection wrappers for TCP control channel and UDP video transport.
// Handles length-prefixed JSON framing for control messages and
// raw UDP packet send/receive for video frames.
// MIT License - Copyright (c) 2024 Aspirewastaken

import Foundation
import Network
import Combine

// MARK: - TCP Control Connection

/// Wraps an NWConnection for the TCP control channel.
///
/// Messages are length-prefixed: 4-byte UInt32 (little-endian) length prefix
/// followed by JSON payload bytes. This allows clean message framing over TCP.
final class VSControlConnection: ObservableObject {

    /// Connection state.
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state: State = .disconnected

    /// Called when a decoded control message is received.
    var onMessage: ((VSMessageEnvelope) -> Void)?

    /// Called when the connection is lost or fails.
    var onDisconnect: ((Error?) -> Void)?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.visionproscreens.control", qos: .userInitiated)
    private var isReceiving = false

    init() {}

    /// Initialize with an existing NWConnection (e.g., from NWListener).
    init(connection: NWConnection) {
        self.connection = connection
    }

    // MARK: - Connection Lifecycle

    /// Connect to a remote endpoint.
    func connect(to endpoint: NWEndpoint) {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveInterval = 5

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        connection = NWConnection(to: endpoint, using: params)
        startConnection()
    }

    /// Start managing an already-created connection (e.g., from listener).
    func start() {
        startConnection()
    }

    /// Disconnect and tear down.
    func disconnect() {
        isReceiving = false
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async {
            self.state = .disconnected
        }
    }

    // MARK: - Sending

    /// Send a typed control message.
    func send<T: Encodable>(type: VSMessageType, message: T) {
        do {
            let envelope = try VSMessageEnvelope(type: type, message: message)
            let jsonData = try envelope.serialize()
            sendLengthPrefixed(data: jsonData)
        } catch {
            print("[VSControlConnection] Failed to encode message: \(error)")
        }
    }

    /// Send raw data with length prefix.
    private func sendLengthPrefixed(data: Data) {
        guard let connection = connection else { return }

        // Create length prefix (4 bytes, little-endian UInt32)
        var length = UInt32(data.count).littleEndian
        var packet = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        packet.append(data)

        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("[VSControlConnection] Send error: \(error)")
            }
        })
    }

    // MARK: - Receiving

    /// Start the receive loop for incoming messages.
    func startReceiving() {
        guard !isReceiving else { return }
        isReceiving = true
        receiveNextMessage()
    }

    private func receiveNextMessage() {
        guard isReceiving, let connection = connection else { return }

        // First, receive the 4-byte length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.handleReceiveError(error)
                return
            }

            if isComplete {
                self.handleDisconnect()
                return
            }

            guard let lengthData = data, lengthData.count == 4 else {
                if self.isReceiving {
                    self.receiveNextMessage()
                }
                return
            }

            // Parse message length
            let messageLength = lengthData.withUnsafeBytes { ptr -> UInt32 in
                return UInt32(littleEndian: ptr.load(as: UInt32.self))
            }

            guard messageLength > 0, messageLength < 10_000_000 else {
                print("[VSControlConnection] Invalid message length: \(messageLength)")
                if self.isReceiving {
                    self.receiveNextMessage()
                }
                return
            }

            // Receive the message payload
            self.receivePayload(length: Int(messageLength))
        }
    }

    private func receivePayload(length: Int) {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.handleReceiveError(error)
                return
            }

            if let data = data {
                self.processReceivedData(data)
            }

            if isComplete {
                self.handleDisconnect()
                return
            }

            if self.isReceiving {
                self.receiveNextMessage()
            }
        }
    }

    private func processReceivedData(_ data: Data) {
        do {
            let envelope = try VSMessageEnvelope.deserialize(from: data)
            DispatchQueue.main.async {
                self.onMessage?(envelope)
            }
        } catch {
            print("[VSControlConnection] Failed to decode message: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func startConnection() {
        guard let connection = connection else { return }

        DispatchQueue.main.async {
            self.state = .connecting
        }

        connection.stateUpdateHandler = { [weak self] connectionState in
            DispatchQueue.main.async {
                switch connectionState {
                case .ready:
                    self?.state = .connected
                    self?.startReceiving()
                case .failed(let error):
                    self?.state = .failed(error.localizedDescription)
                    self?.onDisconnect?(error)
                case .cancelled:
                    self?.state = .disconnected
                case .waiting(let error):
                    print("[VSControlConnection] Waiting: \(error)")
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
    }

    private func handleReceiveError(_ error: NWError) {
        print("[VSControlConnection] Receive error: \(error)")
        DispatchQueue.main.async {
            self.state = .failed(error.localizedDescription)
            self.onDisconnect?(error)
        }
    }

    private func handleDisconnect() {
        DispatchQueue.main.async {
            self.state = .disconnected
            self.onDisconnect?(nil)
        }
    }
}

// MARK: - UDP Video Transport

/// Wraps NWConnection for UDP video frame transport.
///
/// Sends and receives `VSFramePacket` instances as raw UDP datagrams.
/// Uses connected UDP (NWConnection) rather than NWListener for
/// point-to-point video streaming with lower overhead.
final class VSVideoTransport {

    /// Called when a video packet is received.
    var onPacketReceived: ((VSFramePacket) -> Void)?

    private var connection: NWConnection?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.visionproscreens.video", qos: .userInteractive)
    private var isReceiving = false

    // MARK: - Sender (macOS side)

    /// Create a UDP connection to send video frames to a specific endpoint.
    func connectForSending(to host: NWEndpoint.Host, port: NWEndpoint.Port) {
        let params = NWParameters.udp
        params.requiredInterfaceType = .wifi
        // Allow large datagrams for video data
        params.allowLocalEndpointReuse = true

        connection = NWConnection(host: host, port: port, using: params)

        connection?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[VSVideoTransport] UDP sender ready")
            case .failed(let error):
                print("[VSVideoTransport] UDP sender failed: \(error)")
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    /// Send a single video packet over UDP.
    func send(packet: VSFramePacket) {
        guard let connection = connection else { return }

        let data = packet.serialize()
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[VSVideoTransport] Send error: \(error)")
            }
        })
    }

    /// Send multiple packets (e.g., a packetized frame).
    func send(packets: [VSFramePacket]) {
        for packet in packets {
            send(packet: packet)
        }
    }

    // MARK: - Receiver (visionOS side)

    /// Start listening for incoming UDP video packets on a specific port.
    func startListening(port: NWEndpoint.Port) {
        do {
            let params = NWParameters.udp
            params.requiredInterfaceType = .wifi
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: port)
        } catch {
            print("[VSVideoTransport] Failed to create UDP listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[VSVideoTransport] UDP listener ready on port \(port)")
            case .failed(let error):
                print("[VSVideoTransport] UDP listener failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingUDPConnection(connection)
        }

        listener?.start(queue: queue)
        isReceiving = true
    }

    private func handleIncomingUDPConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case .failed(let error):
                print("[VSVideoTransport] Incoming UDP connection failed: \(error)")
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveUDPPacket(on: connection)
    }

    private func receiveUDPPacket(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                if let packet = VSFramePacket.deserialize(from: data) {
                    self.onPacketReceived?(packet)
                }
            }

            if let error = error {
                print("[VSVideoTransport] UDP receive error: \(error)")
                return
            }

            // Continue receiving
            if self.isReceiving {
                self.receiveUDPPacket(on: connection)
            }
        }
    }

    // MARK: - Cleanup

    /// Stop all transport activity.
    func stop() {
        isReceiving = false
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
    }
}
