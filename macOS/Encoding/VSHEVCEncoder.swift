// VSHEVCEncoder.swift
// visionproscreensuptoinfinity
//
// Hardware-accelerated HEVC encoding using VideoToolbox.
// Real-time mode with low-latency configuration for streaming.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(macOS)
import Foundation
import VideoToolbox
import CoreMedia

/// Hardware-accelerated HEVC (H.265) encoder using VideoToolbox.
///
/// Configured for real-time streaming with low-latency settings:
/// - Hardware encoding via Apple Silicon media engine
/// - Real-time mode enabled
/// - No B-frames (AllowFrameReordering = false)
/// - Configurable bitrate and keyframe interval
final class VSHEVCEncoder {

    // MARK: - Types

    enum VSEncoderError: Error, LocalizedError {
        case sessionCreationFailed(OSStatus)
        case configurationFailed(String)
        case encodingFailed(OSStatus)
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .sessionCreationFailed(let status):
                return "Failed to create VTCompressionSession: OSStatus \(status)"
            case .configurationFailed(let reason):
                return "Encoder configuration failed: \(reason)"
            case .encodingFailed(let status):
                return "Frame encoding failed: OSStatus \(status)"
            case .notConfigured:
                return "Encoder not configured. Call configure() first."
            }
        }
    }

    // MARK: - State

    /// Called when an encoded frame is ready.
    /// Parameters: (encodedData, isKeyframe)
    var onEncodedFrame: ((Data, Bool) -> Void)?

    private var session: VTCompressionSession?
    private var config: VSVideoConfig?
    private var forceNextKeyframe = false
    private let encoderQueue = DispatchQueue(label: "com.visionproscreens.encoder", qos: .userInteractive)

    // MARK: - Configuration

    /// Configure the HEVC encoder with the given video configuration.
    ///
    /// Creates a `VTCompressionSession` with hardware encoding on Apple Silicon.
    /// Must be called before `encode()`.
    ///
    /// - Parameter config: Video configuration specifying resolution, bitrate, etc.
    /// - Throws: `VSEncoderError` if session creation or configuration fails.
    func configure(config: VSVideoConfig) throws {
        // Tear down existing session if any
        teardown()

        self.config = config

        // Encoder specification: prefer hardware encoder, enable low-latency rate control
        let encoderSpec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true
        ]

        // Source image buffer attributes
        let sourceAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: config.width,
            kCVPixelBufferHeightKey: config.height,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        // Create compression session
        var sessionOut: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(config.width),
            height: Int32(config.height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: sourceAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil,  // We use the block-based API instead
            refcon: nil,
            compressionSessionOut: &sessionOut
        )

        guard status == noErr, let session = sessionOut else {
            throw VSEncoderError.sessionCreationFailed(status)
        }

        self.session = session

        // Configure session properties for real-time streaming
        try setSessionProperties(session: session, config: config)

        // Prepare the session
        VTCompressionSessionPrepareToEncodeFrames(session)

        print("[VSHEVCEncoder] ✅ Configured: \(config.width)×\(config.height), \(config.bitrate / 1_000_000) Mbps, \(config.fps) fps")
    }

    /// Set compression session properties for low-latency real-time streaming.
    private func setSessionProperties(session: VTCompressionSession, config: VSVideoConfig) throws {
        let properties: [(CFString, CFTypeRef)] = [
            // Real-time encoding
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue),

            // HEVC Main profile, auto level
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel),

            // Bitrate
            (kVTCompressionPropertyKey_AverageBitRate, config.bitrate as CFNumber),

            // Keyframe interval (max frames between keyframes)
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, config.keyframeInterval as CFNumber),

            // Keyframe interval in seconds
            (kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (Double(config.keyframeInterval) / Double(config.fps)) as CFNumber),

            // Disable B-frames for lower latency
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),

            // Expected frame rate
            (kVTCompressionPropertyKey_ExpectedFrameRate, config.fps as CFNumber),

            // Data rate limits: allow burst up to 1.5x bitrate over 1 second
            (kVTCompressionPropertyKey_DataRateLimits, [config.bitrate * 3 / 2, 1] as CFArray),
        ]

        for (key, value) in properties {
            let status = VTSessionSetProperty(session, key: key, value: value)
            if status != noErr {
                print("[VSHEVCEncoder] ⚠️ Failed to set property \(key): \(status)")
            }
        }
    }

    // MARK: - Encoding

    /// Encode a captured video frame.
    ///
    /// The CMSampleBuffer must contain a CVPixelBuffer (CVImageBuffer).
    /// Encoded output is delivered asynchronously via `onEncodedFrame`.
    ///
    /// - Parameter sampleBuffer: The captured video frame from ScreenCaptureKit.
    func encode(sampleBuffer: CMSampleBuffer) {
        guard let session = session else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        // Build frame properties
        var frameProperties: [CFString: Any]? = nil
        if forceNextKeyframe {
            frameProperties = [
                kVTEncodeFrameOptionKey_ForceKeyFrame: true
            ]
            forceNextKeyframe = false
        }

        // Encode using the block-based API
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: frameProperties as CFDictionary?,
            infoFlagsOut: nil
        ) { [weak self] status, infoFlags, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer else {
                if status != noErr {
                    print("[VSHEVCEncoder] Encode callback error: \(status)")
                }
                return
            }

            self?.processEncodedFrame(sampleBuffer: sampleBuffer)
        }

        if status != noErr {
            print("[VSHEVCEncoder] VTCompressionSessionEncodeFrame failed: \(status)")
        }
    }

    /// Force the next encoded frame to be a keyframe (IDR).
    /// Called when the client requests a keyframe (e.g., after packet loss).
    func forceKeyframe() {
        forceNextKeyframe = true
    }

    // MARK: - Teardown

    /// Invalidate and release the compression session.
    func teardown() {
        if let session = session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
        config = nil
        print("[VSHEVCEncoder] Encoder torn down")
    }

    deinit {
        teardown()
    }

    // MARK: - Private

    /// Process an encoded sample buffer: extract HEVC data and keyframe status.
    private func processEncodedFrame(sampleBuffer: CMSampleBuffer) {
        // Check if this is a keyframe
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        var isKeyframe = false

        if let attachments = attachments, CFArrayGetCount(attachments) > 0 {
            let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
            let notSync = CFDictionaryGetValue(attachment, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self))
            // If NotSync is absent or false, this is a keyframe
            isKeyframe = (notSync == nil)
        }

        // Extract the encoded data from the CMBlockBuffer
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let pointer = dataPointer, totalLength > 0 else {
            return
        }

        // Copy encoded data
        let encodedData = Data(bytes: pointer, count: totalLength)

        // Deliver to callback
        onEncodedFrame?(encodedData, isKeyframe)
    }
}
#endif
