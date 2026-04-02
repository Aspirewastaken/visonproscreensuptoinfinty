// VSFramePacket.swift
// visionproscreensuptoinfinity
//
// Video frame packetization for UDP transport.
// Handles splitting large HEVC frames into MTU-safe packets
// and reassembling them on the receiving side.
// MIT License - Copyright (c) 2024 Aspirewastaken

import Foundation

// MARK: - Frame Packet

/// A single UDP packet containing a frame header and a chunk of HEVC payload.
///
/// Large HEVC encoded frames are split into multiple packets, each fitting
/// within the UDP MTU. The `endOfFrame` flag in the header marks the last
/// packet of a frame for reassembly.
struct VSFramePacket: Sendable {
    /// The 10-byte binary header.
    let header: VSFrameHeader

    /// HEVC NALU payload chunk (up to `VSConstants.maxPacketPayloadSize` bytes).
    let payload: Data

    // MARK: - Serialization

    /// Serialize the complete packet (header + payload) for UDP transmission.
    func serialize() -> Data {
        var data = header.serialize()
        data.append(payload)
        return data
    }

    /// Deserialize a packet from received UDP data.
    /// Returns nil if the data is invalid (too short, bad magic).
    static func deserialize(from data: Data) -> VSFramePacket? {
        guard let header = VSFrameHeader.deserialize(from: data) else {
            return nil
        }

        let payloadStart = data.startIndex + VSConstants.frameHeaderSize
        let payload: Data
        if payloadStart < data.endIndex {
            payload = data[payloadStart...]
        } else {
            payload = Data()
        }

        return VSFramePacket(header: header, payload: payload)
    }

    // MARK: - Packetization

    /// Split a complete encoded frame into MTU-safe packets.
    ///
    /// - Parameters:
    ///   - frameData: The complete HEVC encoded frame data.
    ///   - sequenceNumber: Sequence number for all packets of this frame.
    ///   - displayID: Display identifier this frame belongs to.
    ///   - isKeyframe: Whether this frame is a keyframe (IDR).
    ///   - maxPayloadSize: Maximum payload size per packet (default: 1400 bytes).
    /// - Returns: Array of packets that together contain the full frame.
    static func packetize(
        frameData: Data,
        sequenceNumber: UInt32,
        displayID: UInt8,
        isKeyframe: Bool,
        maxPayloadSize: Int = VSConstants.maxPacketPayloadSize
    ) -> [VSFramePacket] {
        guard !frameData.isEmpty else {
            // Even empty frames get one packet with endOfFrame set
            var flags: VSFrameFlags = [.endOfFrame]
            if isKeyframe { flags.insert(.keyframe) }
            let header = VSFrameHeader(
                sequenceNumber: sequenceNumber,
                displayID: displayID,
                flags: flags
            )
            return [VSFramePacket(header: header, payload: Data())]
        }

        var packets: [VSFramePacket] = []
        var offset = frameData.startIndex

        while offset < frameData.endIndex {
            let chunkEnd = min(offset + maxPayloadSize, frameData.endIndex)
            let chunk = frameData[offset..<chunkEnd]
            let isLast = (chunkEnd == frameData.endIndex)

            var flags = VSFrameFlags()
            if isKeyframe { flags.insert(.keyframe) }
            if isLast { flags.insert(.endOfFrame) }

            let header = VSFrameHeader(
                sequenceNumber: sequenceNumber,
                displayID: displayID,
                flags: flags
            )

            packets.append(VSFramePacket(header: header, payload: Data(chunk)))
            offset = chunkEnd
        }

        return packets
    }
}

// MARK: - Frame Reassembler

/// Reassembles complete frames from received packets.
///
/// Buffers incoming packets per display and sequence number.
/// When a packet with `endOfFrame` flag is received and all prior
/// packets for that sequence are present, the complete frame is emitted.
final class VSFrameReassembler {
    /// Callback invoked when a complete frame is assembled.
    /// Parameters: (displayID, sequenceNumber, frameData, isKeyframe)
    var onFrameComplete: ((UInt8, UInt32, Data, Bool) -> Void)?

    /// Per-display reassembly state.
    private var buffers: [UInt8: DisplayBuffer] = [:]

    private struct DisplayBuffer {
        /// Packets buffered for the current frame, keyed by fragment index.
        var packets: [VSFramePacket] = []
        /// The sequence number currently being assembled.
        var currentSequence: UInt32?
        /// Whether we've seen the endOfFrame flag.
        var hasEnd: Bool = false
        /// Whether this frame is a keyframe.
        var isKeyframe: Bool = false
    }

    /// Feed a received packet into the reassembler.
    func receive(packet: VSFramePacket) {
        let displayID = packet.header.displayID
        let seqNum = packet.header.sequenceNumber

        if buffers[displayID] == nil {
            buffers[displayID] = DisplayBuffer()
        }

        // If this is a new sequence number, start fresh
        if buffers[displayID]!.currentSequence != seqNum {
            buffers[displayID]!.packets = []
            buffers[displayID]!.currentSequence = seqNum
            buffers[displayID]!.hasEnd = false
            buffers[displayID]!.isKeyframe = false
        }

        buffers[displayID]!.packets.append(packet)

        if packet.header.isKeyframe {
            buffers[displayID]!.isKeyframe = true
        }

        if packet.header.isEndOfFrame {
            buffers[displayID]!.hasEnd = true
        }

        // Check if frame is complete
        if buffers[displayID]!.hasEnd {
            emitFrame(displayID: displayID)
        }
    }

    /// Assemble and emit the completed frame.
    private func emitFrame(displayID: UInt8) {
        guard let buffer = buffers[displayID],
              let seqNum = buffer.currentSequence else {
            return
        }

        // Concatenate all payload chunks in order received
        var frameData = Data()
        for packet in buffer.packets {
            frameData.append(packet.payload)
        }

        let isKeyframe = buffer.isKeyframe

        // Clear buffer
        buffers[displayID] = DisplayBuffer()

        // Emit the complete frame
        onFrameComplete?(displayID, seqNum, frameData, isKeyframe)
    }

    /// Reset all reassembly state (e.g., on disconnect).
    func reset() {
        buffers.removeAll()
    }

    /// Reset state for a specific display.
    func reset(displayID: UInt8) {
        buffers.removeValue(forKey: displayID)
    }
}
