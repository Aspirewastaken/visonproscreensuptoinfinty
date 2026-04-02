import Foundation
import Observation
import Shared

@MainActor
@Observable
public final class VSDisplayStore {
    public private(set) var displaysByID: [UInt8: VSDisplayDescriptor]
    public private(set) var framesByID: [UInt8: VSDecodedFrame]

    public init(
        displaysByID: [UInt8: VSDisplayDescriptor] = [:],
        framesByID: [UInt8: VSDecodedFrame] = [:]
    ) {
        self.displaysByID = displaysByID
        self.framesByID = framesByID
    }

    public var activeDisplays: [VSDisplayDescriptor] {
        displaysByID.values.sorted { $0.id < $1.id }
    }

    public func apply(displayList: [VSDisplayDescriptor]) {
        displaysByID = Dictionary(uniqueKeysWithValues: displayList.map { ($0.id, $0) })
        framesByID = framesByID.filter { displaysByID[$0.key] != nil }
    }

    public func upsert(display: VSDisplayDescriptor) {
        displaysByID[display.id] = display
    }

    public func remove(displayID: UInt8) {
        displaysByID.removeValue(forKey: displayID)
        framesByID.removeValue(forKey: displayID)
    }

    public func set(frame: VSDecodedFrame) {
        framesByID[frame.displayID] = frame
    }

    public func display(for displayID: UInt8) -> VSDisplayDescriptor? {
        displaysByID[displayID]
    }

    public func frame(for displayID: UInt8) -> VSDecodedFrame? {
        framesByID[displayID]
    }
}
