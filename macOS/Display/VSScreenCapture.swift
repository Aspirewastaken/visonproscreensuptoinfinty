// VSScreenCapture.swift
// visionproscreensuptoinfinity
//
// ScreenCaptureKit-based capture for individual displays.
// Captures frames as CMSampleBuffer for encoding pipeline.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(macOS)
import Foundation
import ScreenCaptureKit
import CoreMedia
import Combine

/// Captures screen content from a specific display using ScreenCaptureKit.
///
/// Each `VSScreenCapture` instance captures from one display. The macOS server
/// creates one per virtual display, feeding captured frames into the HEVC encoder.
final class VSScreenCapture: NSObject, ObservableObject {

    // MARK: - Types

    enum CaptureState: String {
        case idle
        case starting
        case capturing
        case stopped
        case failed
    }

    enum VSCaptureError: Error, LocalizedError {
        case displayNotFound(CGDirectDisplayID)
        case streamCreationFailed
        case noPermission

        var errorDescription: String? {
            switch self {
            case .displayNotFound(let id):
                return "Display with ID \(id) not found in available displays."
            case .streamCreationFailed:
                return "Failed to create screen capture stream."
            case .noPermission:
                return "Screen recording permission is required. Grant access in System Settings > Privacy & Security > Screen Recording."
            }
        }
    }

    // MARK: - Published State

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var capturedFrameCount: UInt64 = 0

    // MARK: - Callbacks

    /// Called for each captured video frame. The CMSampleBuffer contains
    /// a CVPixelBuffer backed by an IOSurface (Metal-compatible, zero-copy).
    var onFrame: ((CMSampleBuffer) -> Void)?

    // MARK: - Private State

    private var stream: SCStream?
    private var streamOutput: StreamOutputHandler?
    private let captureQueue = DispatchQueue(label: "com.visionproscreens.capture", qos: .userInteractive)

    // MARK: - Capture Lifecycle

    /// Start capturing a specific display.
    ///
    /// - Parameters:
    ///   - displayID: The `CGDirectDisplayID` of the display to capture.
    ///   - config: Video configuration for resolution and frame rate.
    func startCapture(displayID: CGDirectDisplayID, config: VSVideoConfig) async throws {
        state = .starting

        // 1. Get available content (requires Screen Recording permission)
        let availableContent: SCShareableContent
        do {
            availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            state = .failed
            throw VSCaptureError.noPermission
        }

        // 2. Find the matching display
        guard let display = availableContent.displays.first(where: { $0.displayID == displayID }) else {
            state = .failed
            throw VSCaptureError.displayNotFound(displayID)
        }

        // 3. Create content filter for this display (capture everything on it)
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        // 4. Configure stream
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.width
        streamConfig.height = config.height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.showsCursor = true
        streamConfig.capturesAudio = false
        streamConfig.queueDepth = 3 // Buffer up to 3 frames

        // 5. Create and configure stream
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)

        // 6. Add output handler
        let outputHandler = StreamOutputHandler { [weak self] sampleBuffer in
            self?.handleCapturedFrame(sampleBuffer)
        }
        self.streamOutput = outputHandler

        try stream.addStreamOutput(outputHandler, type: .screen, sampleHandlerQueue: captureQueue)

        // 7. Start capture
        try await stream.startCapture()

        self.stream = stream
        state = .capturing
        print("[VSScreenCapture] ✅ Started capture for display \(displayID): \(config.width)×\(config.height) @ \(config.fps)fps")
    }

    /// Stop the capture stream.
    func stopCapture() async {
        guard let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            print("[VSScreenCapture] Error stopping capture: \(error)")
        }

        self.stream = nil
        self.streamOutput = nil
        state = .stopped
        print("[VSScreenCapture] Stopped capture")
    }

    // MARK: - Private

    private func handleCapturedFrame(_ sampleBuffer: CMSampleBuffer) {
        capturedFrameCount += 1
        onFrame?(sampleBuffer)
    }
}

// MARK: - SCStreamDelegate

extension VSScreenCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[VSScreenCapture] Stream stopped with error: \(error)")
        DispatchQueue.main.async {
            self.state = .failed
        }
    }
}

// MARK: - Stream Output Handler

/// Handles SCStream output callbacks, forwarding captured frames.
private final class StreamOutputHandler: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Ensure the sample buffer has valid video data
        guard sampleBuffer.isValid,
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            return
        }

        handler(sampleBuffer)
    }
}
#endif
