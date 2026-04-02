import Shared
import SwiftUI

public struct VSDiscoveryView: View {
    public let services: [VSDiscoveredService]
    public let onConnect: (VSDiscoveredService) -> Void

    public init(services: [VSDiscoveredService], onConnect: @escaping (VSDiscoveredService) -> Void) {
        self.services = services
        self.onConnect = onConnect
    }

    public var body: some View {
        List(services) { service in
            Button {
                onConnect(service)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.name)
                        .font(.headline)
                    Text(service.endpoint.debugDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
}
