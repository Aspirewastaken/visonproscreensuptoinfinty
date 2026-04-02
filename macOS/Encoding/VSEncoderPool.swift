import Foundation
import Shared

@MainActor
public final class VSEncoderPool {
    private var pipelines: [UInt8: VSHEVCEncoder] = [:]
    private let configProvider: @Sendable () -> VSVideoConfig

    public var onFrameEncoded: (@Sendable (VSEncodedFrame) -> Void)?
    public var onPerformanceSnapshot: (@Sendable (VSPerformanceSnapshot) -> Void)?

    public init(configProvider: @escaping @Sendable () -> VSVideoConfig) {
        self.configProvider = configProvider
    }

    public func configure(displays: [VSDisplayDescriptor], registry _: Any? = nil) {
        let nextIDs = Set(displays.map(\.id))

        for staleID in pipelines.keys where !nextIDs.contains(staleID) {
            pipelines[staleID]?.finish()
            pipelines.removeValue(forKey: staleID)
        }

        for descriptor in displays where pipelines[descriptor.id] == nil {
            do {
                let encoder = try VSHEVCEncoder(display: descriptor, config: configProvider())
                encoder.onEncodedFrame = { [weak self] frame in
                    self?.onFrameEncoded?(frame)
                }
                encoder.onPerformanceUpdate = { [weak self] snapshot in
                    self?.onPerformanceSnapshot?(snapshot)
                }
                pipelines[descriptor.id] = encoder
            } catch {
                continue
            }
        }
    }

    public func encode(_ capturedFrame: VSScreenCapture.CapturedFrame, forceKeyframe: Bool = false) {
        try? pipelines[capturedFrame.displayID]?.encode(
            sampleBuffer: capturedFrame.sampleBuffer,
            forceKeyframe: forceKeyframe
        )
    }

    public func requestKeyframe(displayID: UInt8) {
        pipelines[displayID]?.requestKeyframe()
    }

    public func stopAll() {
        for encoder in pipelines.values {
            encoder.finish()
        }
        pipelines.removeAll()
    }
}
