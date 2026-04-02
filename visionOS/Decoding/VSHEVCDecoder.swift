// VSHEVCDecoder.swift
// visionproscreensuptoinfinity
//
// Hardware-accelerated HEVC decoding using VideoToolbox.
// Decodes HEVC NALUs from network into CVPixelBuffers for display.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(visionOS)
import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Hardware-accelerated HEVC (H.265) decoder using VideoToolbox.
///
/// Decodes HEVC encoded frames received from the network into
/// CVPixelBuffers suitable for rendering as Metal textures
/// in RealityKit.
final class VSHEVCDecoder {

    // MARK: - Types

    enum VSDecoderError: Error, LocalizedError {
        case sessionCreationFailed(OSStatus)
        case formatDescriptionFailed
        case decodingFailed(OSStatus)
        case noParameterSets
        case invalidData

        var errorDescription: String? {
            switch self {
            case .sessionCreationFailed(let status):
                return "Failed to create VTDecompressionSession: OSStatus \(status)"
            case .formatDescriptionFailed:
                return "Failed to create CMVideoFormatDescription from parameter sets."
            case .decodingFailed(let status):
                return "Frame decoding failed: OSStatus \(status)"
            case .noParameterSets:
                return "No VPS/SPS/PPS found in keyframe data."
            case .invalidData:
                return "Invalid HEVC data received."
            }
        }
    }

    // MARK: - State

    /// Called when a frame is decoded and ready for display.
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var isConfigured = false

    // MARK: - Configuration

    /// Configure the decoder from a keyframe containing parameter sets.
    ///
    /// Extracts VPS, SPS, and PPS NALUs from the keyframe data and
    /// creates a CMVideoFormatDescription for HEVC decoding.
    ///
    /// - Parameter keyframeData: Raw HEVC data from the first keyframe.
    /// - Throws: `VSDecoderError` if parameter set extraction or session creation fails.
    func configureFromKeyframe(_ keyframeData: Data) throws {
        // Extract VPS, SPS, PPS from the keyframe
        let paramSets = extractParameterSets(from: keyframeData)

        guard let vps = paramSets.vps,
              let sps = paramSets.sps,
              let pps = paramSets.pps else {
            throw VSDecoderError.noParameterSets
        }

        // Create format description from parameter sets
        let parameterSets: [Data] = [vps, sps, pps]
        let parameterSetPointers = parameterSets.map { data -> UnsafePointer<UInt8> in
            return data.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        }
        let parameterSetSizes = parameterSets.map { $0.count }

        var formatDesc: CMVideoFormatDescription?

        // Use the arrays to create format description
        try parameterSetPointers.withUnsafeBufferPointer { pointersBuffer in
            try parameterSetSizes.withUnsafeBufferPointer { sizesBuffer in
                let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: parameterSets.count,
                    parameterSetPointers: pointersBuffer.baseAddress!,
                    parameterSetSizes: sizesBuffer.baseAddress!,
                    nalUnitHeaderLength: 4,
                    extensions: nil,
                    formatDescriptionOut: &formatDesc
                )

                guard status == noErr, let desc = formatDesc else {
                    throw VSDecoderError.formatDescriptionFailed
                }

                self.formatDescription = desc
            }
        }

        // Create decompression session
        try createDecompressionSession()

        isConfigured = true
        print("[VSHEVCDecoder] ✅ Configured from keyframe")
    }

    private func createDecompressionSession() throws {
        // Tear down existing session
        if let session = session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }

        guard let formatDescription = formatDescription else {
            throw VSDecoderError.formatDescriptionFailed
        }

        // Destination pixel buffer attributes for Metal compatibility
        let destinationAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        var sessionOut: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &sessionOut
        )

        guard status == noErr, let session = sessionOut else {
            throw VSDecoderError.sessionCreationFailed(status)
        }

        self.session = session
    }

    // MARK: - Decoding

    /// Decode an HEVC encoded frame.
    ///
    /// If this is a keyframe and the decoder is not yet configured,
    /// it will auto-configure from the keyframe's parameter sets.
    ///
    /// - Parameters:
    ///   - data: Raw HEVC encoded frame data.
    ///   - isKeyframe: Whether this frame is a keyframe (IDR).
    func decode(data: Data, isKeyframe: Bool) {
        // Auto-configure from first keyframe
        if !isConfigured && isKeyframe {
            do {
                try configureFromKeyframe(data)
            } catch {
                print("[VSHEVCDecoder] Failed to configure from keyframe: \(error)")
                return
            }
        }

        guard isConfigured, let session = session, let formatDescription = formatDescription else {
            return
        }

        // Create CMBlockBuffer from data
        var blockBuffer: CMBlockBuffer?
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            let status = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: data.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: data.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            guard status == noErr, let buffer = blockBuffer else { return }

            CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }

        guard let blockBuffer = blockBuffer else { return }

        // Create CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = data.count
        let timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: CMTime.invalid
        )

        var timingInfoCopy = timingInfo
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfoCopy,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let buffer = sampleBuffer else {
            print("[VSHEVCDecoder] Failed to create sample buffer: \(status)")
            return
        }

        // Decode the frame
        let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        var infoFlags: VTDecodeInfoFlags = []

        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: buffer,
            flags: decodeFlags,
            infoFlagsOut: &infoFlags
        ) { [weak self] status, _, imageBuffer, _, _ in
            guard status == noErr, let pixelBuffer = imageBuffer else {
                if status != noErr {
                    print("[VSHEVCDecoder] Decode error: \(status)")
                }
                return
            }

            self?.onDecodedFrame?(pixelBuffer)
        }
    }

    // MARK: - Parameter Set Extraction

    /// Extract VPS, SPS, and PPS NALUs from HEVC keyframe data.
    ///
    /// Scans for NALU start codes (0x00000001 or 0x000001) and
    /// identifies parameter set NALUs by their type.
    func extractParameterSets(from data: Data) -> (vps: Data?, sps: Data?, pps: Data?) {
        var vps: Data?
        var sps: Data?
        var pps: Data?

        let nalus = splitNALUs(data: data)

        for nalu in nalus {
            guard nalu.count >= 2 else { continue }

            // HEVC NALU type is in bits 1-6 of the first byte
            let naluType = (nalu[0] >> 1) & 0x3F

            switch naluType {
            case 32: // VPS
                vps = nalu
            case 33: // SPS
                sps = nalu
            case 34: // PPS
                pps = nalu
            default:
                break
            }
        }

        return (vps, sps, pps)
    }

    /// Split data into individual NALUs by finding start codes.
    private func splitNALUs(data: Data) -> [Data] {
        var nalus: [Data] = []
        let bytes = Array(data)
        var i = 0

        while i < bytes.count {
            // Look for start code: 0x00000001 or 0x000001
            var startCodeLength = 0

            if i + 3 < bytes.count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 0 && bytes[i+3] == 1 {
                startCodeLength = 4
            } else if i + 2 < bytes.count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 1 {
                startCodeLength = 3
            }

            if startCodeLength > 0 {
                let naluStart = i + startCodeLength

                // Find the next start code or end of data
                var naluEnd = bytes.count
                for j in naluStart..<bytes.count {
                    if j + 3 < bytes.count && bytes[j] == 0 && bytes[j+1] == 0 && bytes[j+2] == 0 && bytes[j+3] == 1 {
                        naluEnd = j
                        break
                    } else if j + 2 < bytes.count && bytes[j] == 0 && bytes[j+1] == 0 && bytes[j+2] == 1 {
                        naluEnd = j
                        break
                    }
                }

                if naluStart < naluEnd {
                    nalus.append(Data(bytes[naluStart..<naluEnd]))
                }

                i = naluEnd
            } else {
                i += 1
            }
        }

        return nalus
    }

    // MARK: - Teardown

    func teardown() {
        if let session = session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
        isConfigured = false
        print("[VSHEVCDecoder] Decoder torn down")
    }

    deinit {
        teardown()
    }
}
#endif
