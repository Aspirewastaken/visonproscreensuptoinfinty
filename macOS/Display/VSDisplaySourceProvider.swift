import CoreGraphics
import Foundation
import Shared

public enum VSDisplaySourceBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case virtual
    case physicalFallback

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .virtual:
            return "Virtual Displays (Experimental)"
        case .physicalFallback:
            return "Physical Displays (Fallback)"
        }
    }
}

public struct VSDisplaySourceSnapshot: Sendable, Equatable {
    public var backend: VSDisplaySourceBackend
    public var displays: [VSManagedDisplay]

    public init(backend: VSDisplaySourceBackend, displays: [VSManagedDisplay]) {
        self.backend = backend
        self.displays = displays
    }

    public var descriptors: [VSDisplayDescriptor] {
        displays.map(\.descriptor)
    }
}

@MainActor
public protocol VSDisplaySourceProvider: AnyObject {
    var backend: VSDisplaySourceBackend { get }
    var snapshot: VSDisplaySourceSnapshot { get }
    var onSnapshotChanged: (@Sendable (VSDisplaySourceSnapshot) -> Void)? { get set }

    func refresh() async
    @discardableResult
    func createDisplay(config: VSVideoConfig) async throws -> VSDisplayDescriptor
    func removeDisplay(id: UInt8) async throws
    func fetchDisplays() async throws -> [VSManagedDisplay]
    func coreGraphicsDisplayID(for displayID: UInt8) -> CGDirectDisplayID?
}

public enum VSDisplaySourceError: LocalizedError, Equatable, Sendable {
    case unsupported
    case exhaustedDisplaySlots
    case displayNotFound(UInt8)

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "This display source backend does not support that operation."
        case .exhaustedDisplaySlots:
            return "The MVP supports up to \(VSConstants.maxDisplayCount) displays."
        case .displayNotFound(let displayID):
            return "Display \(displayID) was not found."
        }
    }
}
