import Foundation

public struct VSPerformanceSnapshot: Codable, Equatable, Sendable {
    public var displayID: UInt8
    public var fps: Double
    public var bitrateMbps: Double
    public var roundTripLatencyMs: Double
    public var droppedFrames: UInt32
    public var timestamp: Date

    public init(
        displayID: UInt8,
        fps: Double,
        bitrateMbps: Double,
        roundTripLatencyMs: Double,
        droppedFrames: UInt32,
        timestamp: Date = .now
    ) {
        self.displayID = displayID
        self.fps = fps
        self.bitrateMbps = bitrateMbps
        self.roundTripLatencyMs = roundTripLatencyMs
        self.droppedFrames = droppedFrames
        self.timestamp = timestamp
    }
}
