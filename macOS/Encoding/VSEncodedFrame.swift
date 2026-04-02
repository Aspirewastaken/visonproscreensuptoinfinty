import Foundation

public struct VSEncodedFrame: Sendable, Equatable {
    public let displayID: UInt8
    public let frameNumber: UInt32
    public let presentationTimestampMicros: UInt64
    public let isKeyframe: Bool
    public let payload: Data

    public init(
        displayID: UInt8,
        frameNumber: UInt32,
        presentationTimestampMicros: UInt64,
        isKeyframe: Bool,
        payload: Data
    ) {
        self.displayID = displayID
        self.frameNumber = frameNumber
        self.presentationTimestampMicros = presentationTimestampMicros
        self.isKeyframe = isKeyframe
        self.payload = payload
    }
}
