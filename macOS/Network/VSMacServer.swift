import Foundation
import Network
import Shared

@MainActor
public final class VSMacServer {
    public var onConnectionStateChanged: (@Sendable (VSConnectionState) -> Void)?
    public var onClientDescriptionChanged: (@Sendable (String) -> Void)?
    public var onStatisticsUpdated: (@Sendable (VSPerformanceSnapshot) -> Void)?

    public private(set) var currentSession: VSMacSession?

    private let advertiser: VSBonjourAdvertiser
    private let videoListener: NWListener
    private let streamRouter: VSMacStreamRouter
    private let inputInjector: VSInputInjector
    private let tcpQueue = DispatchQueue(label: VSConstants.Network.tcpQueueLabel + ".server")
    private let udpQueue = DispatchQueue(label: VSConstants.Network.udpQueueLabel + ".server")

    private var displaysProvider: (() -> [VSDisplayDescriptor])?
    private var performanceHandler: ((VSPerformanceSnapshot) -> Void)?
    private var displays: [VSDisplayDescriptor] = []
    private var queuedUDPConnection: NWConnection?

    public init(
        advertiser: VSBonjourAdvertiser = VSBonjourAdvertiser(serviceName: Host.current().localizedName ?? VSConstants.productName),
        registry _: VSDisplayRegistry? = nil,
        inputInjector: VSInputInjector
    ) {
        self.advertiser = advertiser
        streamRouter = VSMacStreamRouter()
        self.inputInjector = inputInjector
        videoListener = try! NWListener(
            using: .udp,
            on: NWEndpoint.Port(rawValue: VSConstants.Network.defaultVideoPort)!
        )
    }

    public func start(
        displaysProvider: @escaping () -> [VSDisplayDescriptor],
        performanceHandler: @escaping (VSPerformanceSnapshot) -> Void
    ) throws {
        self.displaysProvider = displaysProvider
        self.performanceHandler = performanceHandler
        displays = displaysProvider()

        advertiser.onStateChange = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.onConnectionStateChanged?(.ready)
                case .failed(let message):
                    self?.onConnectionStateChanged?(.failed(message))
                case .idle:
                    self?.onConnectionStateChanged?(.setup)
                }
            }
        }

        advertiser.onConnection = { [weak self] connection in
            guard let self else { return }
            Task { @MainActor in
                self.attachControlConnection(connection)
            }
        }

        videoListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { @MainActor in
                self.queuedUDPConnection = connection
                await self.streamRouter.attachSession(
                    VSUDPVideoChannel(connection: connection, queue: self.udpQueue)
                )
            }
        }
        videoListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                if case .failed(let error) = state {
                    self.onConnectionStateChanged?(.failed(error.localizedDescription))
                }
            }
        }
        videoListener.start(queue: udpQueue)

        try advertiser.start(onPort: NWEndpoint.Port(rawValue: VSConstants.Network.controlPort)!)
    }

    public func stop() {
        currentSession?.disconnect()
        currentSession = nil
        advertiser.stop()
        videoListener.cancel()
        Task { await streamRouter.detachSession() }
        onConnectionStateChanged?(.cancelled)
    }

    public func updateDisplay(_ descriptor: VSDisplayDescriptor) throws {
        displays.removeAll { $0.id == descriptor.id }
        displays.append(descriptor)
        displays.sort { $0.id < $1.id }
        currentSession?.push(displayList: displays)
    }

    public func send(frame: VSEncodedFrame, using config: VSVideoConfig) {
        streamRouter.enqueue(frame: frame, maxPayloadSize: config.payloadBudget())
    }

    private func attachControlConnection(_ connection: NWConnection) {
        currentSession?.disconnect()

        let session = VSMacSession(
            controlConnection: connection,
            inputInjector: inputInjector,
            streamRouter: streamRouter,
            displaysProvider: { [weak self] in self?.displaysProvider?() ?? self?.displays ?? [] }
        )

        session.onStatusChange = { [weak self] status in
            guard let self else { return }
            switch status {
            case .idle:
                self.onConnectionStateChanged?(.ready)
            case .paired(let clientName):
                self.onClientDescriptionChanged?(clientName)
            case .failed(let message):
                self.onConnectionStateChanged?(.failed(message))
            case .disconnected:
                self.onConnectionStateChanged?(.cancelled)
            }
        }

        currentSession = session
        onClientDescriptionChanged?("Vision Pro client connected")
        session.start(on: tcpQueue)
        session.push(displayList: displays)
    }
}
