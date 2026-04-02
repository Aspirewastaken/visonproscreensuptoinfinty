import Foundation
import Shared

public actor VSMacStreamRouter {
    private let packetizer = VSFramePacketizer()
    private var videoChannel: VSUDPVideoChannel?
    private var sequenceNumbers: [UInt8: UInt32] = [:]
    private var frameNumbers: [UInt8: UInt32] = [:]
    private var keyframeRequests: Set<UInt8> = []

    public init() {}

    public func attachSession(_ channel: VSUDPVideoChannel) {
        videoChannel = channel
    }

    public func detachSession() {
        videoChannel = nil
    }

    public func enqueue(frame: VSEncodedFrame, videoConfig: VSVideoConfig) {
        Task {
            await send(frame, videoConfig: videoConfig)
        }
    }

    public func send(_ frame: VSEncodedFrame, videoConfig: VSVideoConfig) async {
        guard let videoChannel else { return }

        let nextSequence = sequenceNumbers[frame.displayID, default: 0]
        let nextFrameNumber = frameNumbers[frame.displayID, default: frame.frameNumber]
        let shouldForceKeyframe = keyframeRequests.remove(frame.displayID) != nil

        do {
            let packets = try packetizer.fragment(
                displayID: frame.displayID,
                frameNumber: nextFrameNumber,
                initialSequenceNumber: nextSequence,
                timestampMicros: frame.presentationTimestampMicros,
                payload: frame.payload,
                isKeyframe: frame.isKeyframe || shouldForceKeyframe,
                maxPayloadSize: videoConfig.payloadBudget()
            )

            for packet in packets {
                videoChannel.send(packet)
            }

            sequenceNumbers[frame.displayID] = nextSequence &+ UInt32(packets.count)
            frameNumbers[frame.displayID] = nextFrameNumber &+ 1
        } catch {
            assertionFailure("Failed to packetize encoded frame: \(error)")
        }
    }

    public func requestKeyframe(displayID: UInt8) {
        keyframeRequests.insert(displayID)
    }

    public func reset(displayID: UInt8) {
        sequenceNumbers[displayID] = 0
        frameNumbers[displayID] = 0
        keyframeRequests.remove(displayID)
    }

    public func resetAll() {
        sequenceNumbers.removeAll()
        frameNumbers.removeAll()
        keyframeRequests.removeAll()
    }
}
