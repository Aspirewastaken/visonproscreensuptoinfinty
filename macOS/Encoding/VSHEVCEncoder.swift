import CoreMedia
import CoreVideo
import Foundation
import Shared
import VideoToolbox

public enum VSHEVCEncoderError: Error, LocalizedError {
    case unsupportedCodec
    case sessionCreationFailed(OSStatus)
    case propertySetFailed(OSStatus)
    case encodeFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unsupportedCodec:
            return "Hardware HEVC encoding is not supported on this Mac."
        case .sessionCreationFailed(let status):
            return "Failed to create VTCompressionSession (\(status))."
        case .propertySetFailed(let status):
            return "Failed to configure VTCompressionSession (\(status))."
        case .encodeFailed(let status):
            return "Failed to encode video frame (\(status))."
        }
    }
}

@MainActor
public final class VSHEVCEncoder {
    public var onEncodedFrame: (@Sendable (VSEncodedFrame) -> Void)?
    public var onPerformanceUpdate: (@Sendable (VSPerformanceSnapshot) -> Void)?

    private let display: VSDisplayDescriptor
    private let config: VSVideoConfig
    private var session: VTCompressionSession?
    private var nextFrameNumber: UInt32 = 0
    private var encodedFrames: Int = 0
    private var encodedBytes: Int = 0
    private var lastMetricsEmission = Date()

    public init(display: VSDisplayDescriptor, config: VSVideoConfig) throws {
        self.display = display
        self.config = config
        try prepare()
    }

    deinit {
        finish()
    }

    public func encode(sampleBuffer: CMSampleBuffer, forceKeyframe: Bool = false) throws {
        guard let session, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw VSHEVCEncoderError.encodeFailed(kVTParameterErr)
        }

        let currentFrameNumber = nextFrameNumber
        nextFrameNumber &+= 1

        var frameProperties: CFDictionary?
        if forceKeyframe {
            frameProperties = [
                kVTEncodeFrameOptionKey_ForceKeyFrame as String: true
            ] as CFDictionary
        }

        var infoFlags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: CMSampleBufferGetDuration(sampleBuffer),
            frameProperties: frameProperties,
            sourceFrameRefcon: UnsafeMutableRawPointer(bitPattern: UInt(currentFrameNumber)),
            infoFlagsOut: &infoFlags
        )

        guard status == noErr else {
            throw VSHEVCEncoderError.encodeFailed(status)
        }
    }

    public func requestKeyframe() {
        guard let session else { return }
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
            value: NSNumber(value: config.keyframeIntervalSeconds)
        )
    }

    public func finish() {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            self.session = nil
        }
    }

    private func prepare() throws {
        guard VTIsHardwareEncodeSupported(kCMVideoCodecType_HEVC) else {
            throw VSHEVCEncoderError.unsupportedCodec
        }

        guard session == nil else { return }

        var compressionSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(config.resolution.width),
            height: Int32(config.resolution.height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: Self.compressionCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )

        guard status == noErr, let compressionSession else {
            throw VSHEVCEncoderError.sessionCreationFailed(status)
        }

        try configure(compressionSession)
        session = compressionSession
    }

    private func configure(_ session: VTCompressionSession) throws {
        try set(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        try set(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        try set(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        try set(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: config.keyframeIntervalSeconds))
        try set(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: config.framesPerSecond))
        try set(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: config.bitrate.bitsPerSecond))
        try set(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [NSNumber(value: config.bitrate.bitsPerSecond / 8), 1] as CFArray)

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else {
            throw VSHEVCEncoderError.propertySetFailed(prepareStatus)
        }
    }

    private func set(_ session: VTCompressionSession, key: CFString, value: CFTypeRef) throws {
        let status = VTSessionSetProperty(session, key: key, value: value)
        guard status == noErr else {
            throw VSHEVCEncoderError.propertySetFailed(status)
        }
    }

    private func handleCompressedSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        sourceFrameRefcon: UnsafeMutableRawPointer?
    ) {
        guard
            CMSampleBufferDataIsReady(sampleBuffer),
            let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        else {
            return
        }

        let frameNumber = UInt32(UInt(bitPattern: sourceFrameRefcon))
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKeyframe = !notSync

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let pointerStatus = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard pointerStatus == noErr, let dataPointer else {
            return
        }

        let payload = Data(bytes: dataPointer, count: totalLength)
        encodedFrames += 1
        encodedBytes += payload.count

        onEncodedFrame?(
            VSEncodedFrame(
                displayID: display.id,
                frameNumber: frameNumber,
                presentationTimestampMicros: UInt64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000),
                isKeyframe: isKeyframe,
                payload: payload
            )
        )

        emitMetricsIfNeeded()
    }

    private func emitMetricsIfNeeded() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastMetricsEmission)
        guard elapsed >= 1 else { return }

        let fps = Double(encodedFrames) / elapsed
        let bitrateMbps = (Double(encodedBytes) * 8 / elapsed) / 1_000_000
        onPerformanceUpdate?(
            VSPerformanceSnapshot(
                displayID: display.id,
                fps: fps,
                bitrateMbps: bitrateMbps,
                roundTripLatencyMs: 0,
                droppedFrames: 0,
                timestamp: now
            )
        )

        encodedFrames = 0
        encodedBytes = 0
        lastMetricsEmission = now
    }

    nonisolated private static let compressionCallback: VTCompressionOutputCallback = { refcon, sourceFrameRefcon, status, _, sampleBuffer in
        guard
            status == noErr,
            let refcon,
            let sampleBuffer
        else {
            return
        }

        let encoder = Unmanaged<VSHEVCEncoder>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in
            encoder.handleCompressedSampleBuffer(sampleBuffer, sourceFrameRefcon: sourceFrameRefcon)
        }
    }
}
