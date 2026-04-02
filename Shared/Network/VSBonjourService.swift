// VSBonjourService.swift
// visionproscreensuptoinfinity
//
// Bonjour service advertisement (macOS) and discovery (visionOS)
// using Network.framework NWListener and NWBrowser.
// MIT License - Copyright (c) 2024 Aspirewastaken

import Foundation
import Network
import Combine

// MARK: - Bonjour Advertiser (macOS side)

/// Advertises the Mac companion app as a Bonjour service on the local network.
/// Used by the macOS app to make itself discoverable to Vision Pro clients.
final class VSBonjourAdvertiser: ObservableObject {

    /// Current advertiser state.
    enum State: String {
        case idle
        case starting
        case ready
        case failed
        case cancelled
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var serviceName: String = ""

    /// Called when a new TCP control connection is received from a client.
    var onNewConnection: ((NWConnection) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.visionproscreens.bonjour.advertiser", qos: .userInitiated)

    deinit {
        stopAdvertising()
    }

    /// Start advertising the Bonjour service.
    /// - Parameter name: The service name to advertise (typically the Mac hostname).
    func startAdvertising(name: String) {
        guard state != .ready else { return }

        state = .starting
        serviceName = name

        do {
            let tcpOptions = NWProtocolTCP.Options()
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.requiredInterfaceType = .wifi
            params.includePeerToPeer = false

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: VSConstants.controlPort)!)
        } catch {
            print("[VSBonjourAdvertiser] Failed to create listener: \(error)")
            state = .failed
            return
        }

        // Advertise as Bonjour service
        listener?.service = NWListener.Service(
            name: name,
            type: VSConstants.bonjourServiceType
        )

        // Handle state updates
        listener?.stateUpdateHandler = { [weak self] listenerState in
            DispatchQueue.main.async {
                switch listenerState {
                case .ready:
                    self?.state = .ready
                    if let port = self?.listener?.port {
                        print("[VSBonjourAdvertiser] Listening on port \(port)")
                    }
                case .failed(let error):
                    print("[VSBonjourAdvertiser] Listener failed: \(error)")
                    self?.state = .failed
                case .cancelled:
                    self?.state = .cancelled
                default:
                    break
                }
            }
        }

        // Handle service registration
        listener?.serviceRegistrationUpdateHandler = { change in
            switch change {
            case .add(let endpoint):
                print("[VSBonjourAdvertiser] Service registered: \(endpoint)")
            case .remove(let endpoint):
                print("[VSBonjourAdvertiser] Service removed: \(endpoint)")
            @unknown default:
                break
            }
        }

        // Handle incoming connections
        listener?.newConnectionHandler = { [weak self] connection in
            print("[VSBonjourAdvertiser] New connection from: \(connection.endpoint)")
            self?.onNewConnection?(connection)
        }

        listener?.start(queue: queue)
    }

    /// Stop advertising and tear down the listener.
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        state = .idle
    }
}

// MARK: - Bonjour Browser (visionOS side)

/// Discovers Mac companion apps on the local network via Bonjour.
/// Used by the visionOS app to find available Macs to connect to.
final class VSBonjourBrowser: ObservableObject {

    /// Current browser state.
    enum State: String {
        case idle
        case browsing
        case failed
        case cancelled
    }

    /// A discovered Mac service.
    struct DiscoveredService: Identifiable, Hashable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
        let result: NWBrowser.Result

        static func == (lhs: DiscoveredService, rhs: DiscoveredService) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var discoveredServices: [DiscoveredService] = []

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.visionproscreens.bonjour.browser", qos: .userInitiated)

    deinit {
        stopBrowsing()
    }

    /// Start browsing for Bonjour services.
    func startBrowsing() {
        guard state != .browsing else { return }

        state = .browsing
        discoveredServices = []

        let params = NWParameters()
        params.requiredInterfaceType = .wifi
        params.includePeerToPeer = false

        browser = NWBrowser(
            for: .bonjour(type: VSConstants.bonjourServiceType, domain: nil),
            using: params
        )

        browser?.stateUpdateHandler = { [weak self] browserState in
            DispatchQueue.main.async {
                switch browserState {
                case .ready:
                    self?.state = .browsing
                case .failed(let error):
                    print("[VSBonjourBrowser] Browser failed: \(error)")
                    self?.state = .failed
                case .cancelled:
                    self?.state = .cancelled
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            DispatchQueue.main.async {
                self?.updateServices(results: results)
            }
        }

        browser?.start(queue: queue)
    }

    /// Stop browsing for services.
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        state = .idle
    }

    /// Create a TCP control connection to a discovered service.
    /// - Parameter service: The discovered service to connect to.
    /// - Returns: An NWConnection ready to be started.
    func createConnection(to service: DiscoveredService) -> NWConnection {
        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        return NWConnection(to: service.endpoint, using: params)
    }

    // MARK: - Private

    private func updateServices(results: Set<NWBrowser.Result>) {
        discoveredServices = results.compactMap { result in
            let name: String
            let id: String

            switch result.endpoint {
            case .service(let serviceName, let type, let domain, _):
                name = serviceName
                id = "\(serviceName).\(type).\(domain)"
            default:
                return nil
            }

            return DiscoveredService(
                id: id,
                name: name,
                endpoint: result.endpoint,
                result: result
            )
        }
    }
}
