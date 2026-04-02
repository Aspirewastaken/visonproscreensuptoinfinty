import CoreGraphics
import Foundation
import Shared

private func CGDisplayCopyName(_ displayID: CGDirectDisplayID) -> CFString? {
    nil
}

@MainActor
public final class VSPhysicalDisplaySource: VSDisplaySourceProvider {
    public let backend: VSDisplaySourceBackend = .physicalFallback
    public var onSnapshotChanged: (@Sendable (VSDisplaySourceSnapshot) -> Void)?
    public private(set) var snapshot = VSDisplaySourceSnapshot(backend: .physicalFallback, displays: [])
    private var displayIDsByDescriptor: [UInt8: CGDirectDisplayID] = [:]

    public init() {}

    public func refresh() async {
        snapshot = buildSnapshot()
        onSnapshotChanged?(snapshot)
    }

    public func fetchDisplays() async throws -> [VSManagedDisplay] {
        snapshot.displays
    }

    @discardableResult
    public func createDisplay(config _: VSVideoConfig) async throws -> VSDisplayDescriptor {
        throw VSDisplaySourceError.unsupported
    }

    public func removeDisplay(id _: UInt8) async throws {
        // Physical fallback exposes attached displays only; removal is a no-op.
    }

    public func coreGraphicsDisplayID(for displayID: UInt8) -> CGDirectDisplayID? {
        displayIDsByDescriptor[displayID]
    }

    private func buildSnapshot() -> VSDisplaySourceSnapshot {
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: VSConstants.maxDisplayCount)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(activeDisplays.count), &activeDisplays, &count)

        displayIDsByDescriptor.removeAll()

        let displays = activeDisplays
            .prefix(Int(count))
            .enumerated()
            .map { index, displayID in
                let identifier = UInt8(index + 1)
                displayIDsByDescriptor[identifier] = displayID

                let width = CGDisplayPixelsWide(displayID)
                let height = CGDisplayPixelsHigh(displayID)
                let mode = CGDisplayCopyDisplayMode(displayID)
                let refreshRate = mode?.refreshRate ?? 60

                return VSDisplayDescriptor(
                    id: identifier,
                    name: CGDisplayCopyName(displayID) as String? ?? "Mac Display \(identifier)",
                    width: width,
                    height: height,
                    refreshRate: refreshRate == 0 ? 60 : refreshRate,
                    isVirtual: false
                )
            }

        return VSDisplaySourceSnapshot(
            backend: backend,
            displays: displays.map { descriptor in
                VSManagedDisplay(
                    descriptor: descriptor,
                    cgDisplayID: displayIDsByDescriptor[descriptor.id],
                    bounds: CGRect(x: 0, y: 0, width: descriptor.width, height: descriptor.height)
                )
            }
        )
    }
}
