import CoreGraphics
import Foundation
import Observation
import Shared

@MainActor
@Observable
public final class VSVirtualDisplayManager: VSDisplaySourceProvider {
    public let backend: VSDisplaySourceBackend = .virtual
    public var onSnapshotChanged: (@Sendable (VSDisplaySourceSnapshot) -> Void)?
    public private(set) var snapshot = VSDisplaySourceSnapshot(backend: .virtual, displays: [])
    public private(set) var isExperimentalBackendAvailable: Bool

    private let registry: VSDisplayRegistry
    private var displays: [UInt8: VSDisplayDescriptor] = [:]

    public init(registry: VSDisplayRegistry) {
        self.registry = registry
        isExperimentalBackendAvailable = true
    }

    public func refresh() async {
        snapshot = VSDisplaySourceSnapshot(
            backend: backend,
            displays: displays.values.sorted { $0.id < $1.id }
        )
        onSnapshotChanged?(snapshot)
    }

    @discardableResult
    public func createDisplay(config: VSVideoConfig) async throws -> VSDisplayDescriptor {
        guard displays.count < VSConstants.maxDisplayCount else {
            throw VSDisplaySourceError.exhaustedDisplaySlots
        }

        let nextID = UInt8((displays.keys.max() ?? 0) + 1)
        try VSProtocol.validate(displayID: nextID)

        let descriptor = VSDisplayDescriptor(
            id: nextID,
            name: "Virtual Display \(nextID)",
            width: config.resolution.width,
            height: config.resolution.height,
            refreshRate: Double(config.framesPerSecond),
            isVirtual: true
        )

        let syntheticDisplayID = CGDirectDisplayID(10_000 + UInt32(nextID))
        displays[nextID] = descriptor
        registry.update(
            .init(
                descriptor: descriptor,
                cgDisplayID: syntheticDisplayID,
                bounds: CGRect(
                    x: Int(nextID - 1) * descriptor.width,
                    y: 0,
                    width: descriptor.width,
                    height: descriptor.height
                )
            )
        )
        await refresh()
        return descriptor
    }

    public func removeDisplay(id: UInt8) async throws {
        guard displays.removeValue(forKey: id) != nil else {
            throw VSDisplaySourceError.displayNotFound(id)
        }
        registry.remove(displayID: id)
        await refresh()
    }

    public func coreGraphicsDisplayID(for displayID: UInt8) -> CGDirectDisplayID? {
        registry.cgDisplayID(for: displayID)
    }

    public func fetchDisplays() async throws -> [VSManagedDisplay] {
        await refresh()
        return snapshot.displays
    }
}
