import Foundation
import Observation
import Shared

public struct VSPairedHost: Codable, Equatable, Sendable {
    public let name: String
    public let endpointDebugDescription: String

    public init(name: String, endpointDebugDescription: String) {
        self.name = name
        self.endpointDebugDescription = endpointDebugDescription
    }
}

@MainActor
@Observable
public final class VSPairedHostStore {
    @ObservationIgnored
    private let defaults: UserDefaults

    public private(set) var lastPairedHost: VSPairedHost?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: Keys.lastPairedHost),
            let host = try? JSONDecoder().decode(VSPairedHost.self, from: data)
        {
            lastPairedHost = host
        } else {
            lastPairedHost = nil
        }
    }

    public var lastServiceName: String? {
        lastPairedHost?.name
    }

    public func remember(service: VSDiscoveredService) {
        lastPairedHost = VSPairedHost(
            name: service.name,
            endpointDebugDescription: service.endpoint.debugDescription
        )
        persist()
    }

    public func remember(serviceName: String, endpointDebugDescription: String = "") {
        lastPairedHost = VSPairedHost(
            name: serviceName,
            endpointDebugDescription: endpointDebugDescription
        )
        persist()
    }

    public func clear() {
        lastPairedHost = nil
        defaults.removeObject(forKey: Keys.lastPairedHost)
    }

    private func persist() {
        guard let lastPairedHost, let data = try? JSONEncoder().encode(lastPairedHost) else {
            return
        }
        defaults.set(data, forKey: Keys.lastPairedHost)
    }
}

private enum Keys {
    static let lastPairedHost = "vision.pairedHost.last"
}
