import Foundation
import Observation

public struct VSStreamStatistics: Sendable, Equatable {
    public let displayID: UInt8
    public var fps: Double
    public var bitrateMbps: Double
    public var droppedFrames: Int
    public var roundTripLatencyMs: Double

    public init(
        displayID: UInt8,
        fps: Double = 0,
        bitrateMbps: Double = 0,
        droppedFrames: Int = 0,
        roundTripLatencyMs: Double = 0
    ) {
        self.displayID = displayID
        self.fps = fps
        self.bitrateMbps = bitrateMbps
        self.droppedFrames = droppedFrames
        self.roundTripLatencyMs = roundTripLatencyMs
    }
}

@MainActor
@Observable
public final class VSStatisticsStore {
    public private(set) var snapshots: [UInt8: VSStreamStatistics]

    public init(snapshots: [UInt8: VSStreamStatistics] = [:]) {
        self.snapshots = snapshots
    }

    public func update(_ snapshot: VSStreamStatistics) {
        snapshots[snapshot.displayID] = snapshot
    }

    public func remove(displayID: UInt8) {
        snapshots.removeValue(forKey: displayID)
    }

    public func reset() {
        snapshots.removeAll()
    }
}
