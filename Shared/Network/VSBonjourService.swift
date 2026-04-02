import Foundation
import Network

public struct VSDiscoveredService: Equatable, Identifiable, Sendable {
    public var id: String { endpoint.debugDescription }
    public let name: String
    public let endpoint: NWEndpoint
    public let interfaceType: NWInterface.InterfaceType?

    public init(name: String, endpoint: NWEndpoint, interfaceType: NWInterface.InterfaceType?) {
        self.name = name
        self.endpoint = endpoint
        self.interfaceType = interfaceType
    }
}

public final class VSBonjourAdvertiser {
    public enum State: Equatable {
        case idle
        case ready(port: UInt16)
        case failed(String)
    }

    private let serviceName: String
    private let serviceType: String
    private let queue: DispatchQueue
    private var listener: NWListener?

    public var onStateChange: (@Sendable (State) -> Void)?
    public var onConnection: (@Sendable (NWConnection) -> Void)?

    public init(
        serviceName: String,
        serviceType: String = VSConstants.Bonjour.serviceType,
        queue: DispatchQueue = DispatchQueue(label: VSConstants.Network.tcpQueueLabel + ".bonjour")
    ) {
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.queue = queue
    }

    public func start(onPort port: NWEndpoint.Port) throws {
        let listener = try NWListener(using: .tcp, on: port)
        listener.service = NWListener.Service(name: serviceName, type: serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onStateChange?(.ready(port: listener.port?.rawValue ?? port.rawValue))
            case .failed(let error):
                self?.onStateChange?(.failed(error.localizedDescription))
            default:
                self?.onStateChange?(.idle)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.onConnection?(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        onStateChange?(.idle)
    }
}

public final class VSBonjourBrowser {
    public enum State: Equatable {
        case idle
        case browsing
        case failed(String)
    }

    private let type: String
    private let queue: DispatchQueue
    private var browser: NWBrowser?

    public var onStateChange: (@Sendable (State) -> Void)?
    public var onServicesChanged: (@Sendable ([VSDiscoveredService]) -> Void)?

    public init(
        type: String = VSConstants.Bonjour.serviceType,
        queue: DispatchQueue = DispatchQueue(label: VSConstants.Network.tcpQueueLabel + ".bonjour")
    ) {
        self.type = type
        self.queue = queue
    }

    public func start() {
        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onStateChange?(.browsing)
            case .failed(let error):
                self?.onStateChange?(.failed(error.localizedDescription))
            default:
                self?.onStateChange?(.idle)
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let services = results.map { result -> VSDiscoveredService in
                VSDiscoveredService(
                    name: result.endpoint.debugDescription,
                    endpoint: result.endpoint,
                    interfaceType: result.interfaces.first?.type
                )
            }
            self?.onServicesChanged?(services.sorted { $0.name < $1.name })
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        onStateChange?(.idle)
        onServicesChanged?([])
    }
}
