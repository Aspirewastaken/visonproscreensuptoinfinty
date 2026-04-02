import Foundation
import Network

public enum VSConnectionState: Equatable {
    case setup
    case waiting(String)
    case preparing
    case ready
    case failed(String)
    case cancelled
}

public typealias VSControlMessageHandler = @Sendable (VSControlMessage) -> Void

public final class VSTCPControlChannel {
    public typealias MessageHandler = VSControlMessageHandler
    public typealias StateHandler = @Sendable (VSConnectionState) -> Void

    private let connection: NWConnection
    private let queue: DispatchQueue

    public var onStateChange: StateHandler?
    public var onMessage: MessageHandler?

    public init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?(Self.map(state))
        }

        connection.start(queue: queue)
        receiveNextFrameLength()
    }

    public func cancel() {
        connection.cancel()
    }

    public func send(_ message: VSControlMessage) {
        do {
            let framed = try VSProtocol.encodeControlMessage(message)
            connection.send(content: framed, completion: .contentProcessed { _ in })
        } catch {
            onStateChange?(.failed("Failed to encode message: \(error.localizedDescription)"))
        }
    }

    private func receiveNextFrameLength() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.onStateChange?(.failed(error.localizedDescription))
                return
            }

            if isComplete {
                self.onStateChange?(.cancelled)
                return
            }

            guard
                let data,
                data.count == 4
            else {
                self.receiveNextFrameLength()
                return
            }

            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.receivePayload(length: Int(length))
        }
    }

    private func receivePayload(length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.onStateChange?(.failed(error.localizedDescription))
                return
            }

            if isComplete {
                self.onStateChange?(.cancelled)
                return
            }

            guard let data else {
                self.receiveNextFrameLength()
                return
            }

            do {
                let message = try VSProtocol.decodeControlMessage(data)
                self.onMessage?(message)
            } catch {
                self.onStateChange?(.failed("Failed to decode message: \(error.localizedDescription)"))
            }

            self.receiveNextFrameLength()
        }
    }

    private static func map(_ state: NWConnection.State) -> VSConnectionState {
        switch state {
        case .setup:
            return .setup
        case .waiting(let error):
            return .waiting(error.localizedDescription)
        case .preparing:
            return .preparing
        case .ready:
            return .ready
        case .failed(let error):
            return .failed(error.localizedDescription)
        case .cancelled:
            return .cancelled
        @unknown default:
            return .failed("Unknown connection state")
        }
    }
}

public final class VSUDPVideoChannel {
    public typealias StateHandler = @Sendable (VSConnectionState) -> Void
    public typealias PacketHandler = @Sendable (VSFramePacket) -> Void

    private let connection: NWConnection
    private let queue: DispatchQueue

    public var onStateChange: StateHandler?
    public var onPacket: PacketHandler?

    public init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?(Self.map(state))
        }

        connection.start(queue: queue)
        receiveMessage()
    }

    public func cancel() {
        connection.cancel()
    }

    public func send(_ packet: VSFramePacket) {
        do {
            let encoded = try packet.encode()
            connection.send(content: encoded, completion: .contentProcessed { _ in })
        } catch {
            onStateChange?(.failed("Failed to encode frame packet: \(error.localizedDescription)"))
        }
    }

    private func receiveMessage() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.onStateChange?(.failed(error.localizedDescription))
                return
            }

            if let data {
                do {
                    let packet = try VSFramePacket.decode(data)
                    self.onPacket?(packet)
                } catch {
                    self.onStateChange?(.failed("Failed to decode frame packet: \(error.localizedDescription)"))
                    return
                }
            }

            self.receiveMessage()
        }
    }

    private static func map(_ state: NWConnection.State) -> VSConnectionState {
        switch state {
        case .setup:
            return .setup
        case .waiting(let error):
            return .waiting(error.localizedDescription)
        case .preparing:
            return .preparing
        case .ready:
            return .ready
        case .failed(let error):
            return .failed(error.localizedDescription)
        case .cancelled:
            return .cancelled
        @unknown default:
            return .failed("Unknown connection state")
        }
    }
}
