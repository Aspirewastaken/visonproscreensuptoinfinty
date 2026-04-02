import CoreGraphics
import Foundation
import Shared

@MainActor
public final class VSDisplayRegistry {
    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: UInt8 { descriptor.id }
        public var descriptor: VSDisplayDescriptor
        public var cgDisplayID: CGDirectDisplayID?
        public var bounds: CGRect

        public init(
            descriptor: VSDisplayDescriptor,
            cgDisplayID: CGDirectDisplayID?,
            bounds: CGRect
        ) {
            self.descriptor = descriptor
            self.cgDisplayID = cgDisplayID
            self.bounds = bounds
        }
    }

    public private(set) var entries: [UInt8: Entry] = [:]

    public init(entries: [UInt8: Entry] = [:]) {
        self.entries = entries
    }

    public func register(
        descriptor: VSDisplayDescriptor,
        cgDisplayID: CGDirectDisplayID?,
        bounds: CGRect
    ) {
        update(
            Entry(
                descriptor: descriptor,
                cgDisplayID: cgDisplayID,
                bounds: bounds
            )
        )
    }

    public func update(_ entry: Entry) {
        entries[entry.id] = entry
    }

    public func replace(with entries: [Entry]) {
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    public func apply(displays: [VSManagedDisplay]) {
        entries = Dictionary(uniqueKeysWithValues: displays.map { display in
            (
                display.id,
                Entry(
                    descriptor: display.descriptor,
                    cgDisplayID: display.cgDisplayID,
                    bounds: display.bounds
                )
            )
        })
    }

    public func unregister(displayID: UInt8) {
        entries.removeValue(forKey: displayID)
    }

    public func remove(displayID: UInt8) {
        unregister(displayID: displayID)
    }

    public func entry(for displayID: UInt8) -> Entry? {
        entries[displayID]
    }

    public func descriptor(for displayID: UInt8) -> VSDisplayDescriptor? {
        entries[displayID]?.descriptor
    }

    public func bounds(for displayID: UInt8) -> CGRect? {
        entries[displayID]?.bounds
    }

    public func cgDisplayID(for displayID: UInt8) -> CGDirectDisplayID? {
        entries[displayID]?.cgDisplayID
    }

    public func displayID(for displayID: UInt8) -> CGDirectDisplayID? {
        cgDisplayID(for: displayID)
    }

    public func globalPoint(
        for displayID: UInt8,
        normalizedX: Double,
        normalizedY: Double
    ) -> CGPoint? {
        guard let bounds = bounds(for: displayID) else {
            return nil
        }

        let clampedX = min(max(normalizedX, 0), 1)
        let clampedY = min(max(normalizedY, 0), 1)
        let x = bounds.origin.x + bounds.width * clampedX
        let y = bounds.origin.y + bounds.height * clampedY
        return CGPoint(x: x, y: y)
    }
}
