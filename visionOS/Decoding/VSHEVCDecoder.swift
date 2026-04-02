import AVFoundation
import Foundation
import Shared
import VideoToolbox

@MainActor
public final class VSHEVCDecoder {
    public enum DecoderError: LocalizedError, Equatable {
        case unsupportedFormatDescription
        case sessionCreationFailed(OSStatus)
        case decodeFailed(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormatDescription:
                return "Could not create an HEVC format description from the received access unit."
            case .sessionCreationFailed(let status):
                return "Failed to create HEVC decoder session (\(status))."
            case .decodeFailed(let status):
                return "Failed to decode frame (\(status))."
            }
        }
    }

    public var onFrame: (@Sendable (VSDecodedFrame) -> Void)?
    public var onFailure: (@Sendable (DecoderError) -> Void)?
    private let displayLayer = AVSampleBufferDisplayLayer()

    public init() {
        displayLayer.videoGravity = .resizeAspect
    }

    public func invalidate() {
        displayLayer.flushAndRemoveImage()
    }

    public func decode(_ frame: VSReassembledFrame) {
        let decodedFrame = VSDecodedFrame(
            displayID: frame.displayID,
            frameNumber: frame.frameNumber,
            presentationTimestampMicros: frame.presentationTimestampMicros,
            accessUnit: frame.payload,
            displayLayer: displayLayer
        )
        onFrame?(decodedFrame)
    }
}
