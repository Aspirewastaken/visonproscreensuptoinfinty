import Foundation
import Network
import Shared

@MainActor
public final class VSMacSession {
    public let id: UUID
    public private(set) var state: VSConnectionState = .setup
    public private(set) var pairedClientName: String?
    public private(set) var pairAcceptedAt: Date?

    private let controlChannel: VSTCPControlChannel
    private let inputInjector: VSInputInjector
    private let streamRouter: VSMacStreamRouter
    private let displaysProvider: () -> [VSDisplayDescriptor]
    private let stateHandler: (VSConnectionState) -> Void

    public init(
        id: UUID = UUID(),
        controlConnection: NWConnection,
        inputInjector: VSInputInjector,
        streamRouter: VSMacStreamRouter,
        displaysProvider: @escaping () -> [VSDisplayDescriptor],
        queue: DispatchQueue = DispatchQueue(label: VSConstants.Network.tcpQueueLabel + ".session"),
        stateHandler: @escaping (VSConnectionState) -> Void = { _ in }
    ) {
        self.id = id
        self.inputInjector = inputInjector
        self.streamRouter = streamRouter
        self.displaysProvider = displaysProvider
        self.stateHandler = stateHandler
        controlChannel = VSTCPControlChannel(connection: controlConnection, queue: queue)
        bindCallbacks()
    }

    public func start() {
        controlChannel.start()
        updateState(.setup)
    }

    public func stop() {
        controlChannel.cancel()
        updateState(.cancelled)
    }

    public func attachVideoConnection(_ connection: NWConnection, queue: DispatchQueue) {
        let channel = VSUDPVideoChannel(connection: connection, queue: queue)
        channel.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.updateState(state)
            }
        }
        channel.start()
        Task {
            await streamRouter.attachSession(channel)
        }
    }

    public func updateDisplays(_ displays: [VSDisplayDescriptor]) {
        controlChannel.send(.displayList(.init(displays: displays)))
        Task {
            await streamRouter.updateDisplayList(displays)
        }
    }

    private func bindCallbacks() {
        controlChannel.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.updateState(state)
            }
        }

        controlChannel.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handle(message)
            }
        }
    }

    private func handle(_ message: VSControlMessage) {
        switch message {
        case .pairRequest(let request):
            pairedClientName = request.macName
            pairAcceptedAt = .now
            controlChannel.send(.pairAccept(.init(
                sessionID: id,
                acceptedAt: pairAcceptedAt ?? .now,
                capabilities: [
                    "hevc",
                    "udp-video",
                    "input-forwarding",
                    "display-fallback",
                ]
            )))
            updateDisplays(displaysProvider())
            updateState(.ready)
        case .requestKeyframe(let request):
            Task {
                await streamRouter.requestKeyframe(displayID: request.displayID)
            }
        case .performancePing(let ping):
            controlChannel.send(.performancePong(.init(
                identifier: ping.identifier,
                echoedSentAt: ping.sentAt,
                receivedAt: Date().timeIntervalSince1970
            )))
        case .inputMouseMove(let move):
            try? inputInjector.injectMouseMove(move)
        case .inputMouseButton(let button):
            try? inputInjector.injectMouseButton(button)
        case .inputScroll(let scroll):
            try? inputInjector.injectScroll(scroll)
        case .inputKey(let key):
            try? inputInjector.injectKey(key)
        case .displayAdded, .displayList, .displayRemoved, .pairAccept, .pairReject, .performancePong:
            break
        }
    }

    private func updateState(_ newState: VSConnectionState) {
        state = newState
        stateHandler(newState)
    }
}
