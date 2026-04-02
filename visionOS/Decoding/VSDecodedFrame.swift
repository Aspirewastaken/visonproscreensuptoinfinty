import AVFoundation
import Foundation

public struct VSDecodedFrame: Sendable {
    public let displayID: UInt8
    public let frameNumber: UInt32
    public let presentationTimestampMicros: UInt64
    public let accessUnit: Data

    public init(
        displayID: UInt8,
        frameNumber: UInt32,
        presentationTimestampMicros: UInt64,
        accessUnit: Data
    ) {
        self.displayID = displayID
        self.frameNumber = frameNumber
        self.presentationTimestampMicros = presentationTimestampMicros
        self.accessUnit = accessUnit
    }
}
