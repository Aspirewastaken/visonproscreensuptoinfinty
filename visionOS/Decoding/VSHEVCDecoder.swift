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

    public init() {}

    public func invalidate() {
        // Placeholder until a full VTDecompressionSession + sample buffer output path
        // is verified on Apple hardware.
    }

    public func decode(_ frame: VSReassembledFrame) {
        let decodedFrame = VSDecodedFrame(
            displayID: frame.displayID,
            frameNumber: frame.frameNumber,
            presentationTimestampMicros: frame.presentationTimestampMicros,
            accessUnit: frame.payload
        )
        onFrame?(decodedFrame)
    }
}
