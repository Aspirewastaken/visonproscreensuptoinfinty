import AVFoundation
import Foundation
import ScreenCaptureKit
import Shared

@MainActor
public final class VSScreenCapture: NSObject, SCStreamOutput {
    public struct CapturedFrame: Sendable {
        public let displayID: UInt8
        public let sampleBuffer: CMSampleBuffer
        public let timestamp: CMTime

        public init(displayID: UInt8, sampleBuffer: CMSampleBuffer, timestamp: CMTime) {
            self.displayID = displayID
            self.sampleBuffer = sampleBuffer
            self.timestamp = timestamp
        }
    }

    private let registry: VSDisplayRegistry
    private let outputQueue = DispatchQueue(label: "com.aspirewastaken.visionproscreensuptoinfinity.capture")
    private var streams: [UInt8: SCStream] = [:]

    public var onFrame: (@Sendable (CapturedFrame) -> Void)?

    public init(registry: VSDisplayRegistry) {
        self.registry = registry
    }

    public func configure(display _: VSDisplayDescriptor, videoConfig _: VSVideoConfig) {}

    public func startCapture(for descriptor: VSDisplayDescriptor, config: VSVideoConfig) async throws {
        guard streams[descriptor.id] == nil else { return }
        guard let displayID = registry.displayID(for: descriptor.id) else { return }

        let available = try await SCShareableContent.current
        guard let display = available.displays.first(where: { $0.displayID == displayID }) else { return }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = descriptor.width
        streamConfiguration.height = descriptor.height
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.framesPerSecond))
        streamConfiguration.queueDepth = 5
        streamConfiguration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        streams[descriptor.id] = stream
    }

    public func stopCapture(displayID: UInt8) async {
        guard let stream = streams.removeValue(forKey: displayID) else { return }
        try? await stream.stopCapture()
    }

    public func stopAll() async {
        for displayID in Array(streams.keys) {
            await stopCapture(displayID: displayID)
        }
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }
        guard let displayID = streams.first(where: { $0.value === stream })?.key else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame?(CapturedFrame(displayID: displayID, sampleBuffer: sampleBuffer, timestamp: timestamp))
    }
}
