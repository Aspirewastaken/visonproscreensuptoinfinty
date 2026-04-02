// VSProtocol.swift
// visionproscreensuptoinfinity
//
// Wire protocol definitions for UDP video frame transport.
// Binary frame header format for low-overhead parsing.
// MIT License - Copyright (c) 2024 Aspirewastaken

import Foundation

// MARK: - Frame Flags

/// Bitfield flags carried in each frame packet header.
///
/// ```
/// Bit 0: keyframe     - This packet contains (part of) a keyframe / IDR frame
/// Bit 1: endOfFrame   - This is the last packet for the current frame
/// Bit 2-7: reserved
/// ```
struct VSFrameFlags: OptionSet, Sendable {
    let rawValue: UInt8

    /// This packet contains keyframe data (IDR frame).
    static let keyframe    = VSFrameFlags(rawValue: 1 << 0)

    /// This is the last (or only) packet for the current frame.
    static let endOfFrame  = VSFrameFlags(rawValue: 1 << 1)
}

// MARK: - Frame Header

/// Fixed-size binary header prepended to every UDP video packet.
///
/// Layout (10 bytes total):
/// ```
/// +----------+-----------+----------+----------+
/// | Magic(4) | SeqNum(4) | DispID(1)| Flags(1) |
/// | "VPSI"   | uint32 LE | uint8    | bitfield |
/// +----------+-----------+----------+----------+
/// ```
///
/// All multi-byte integers are little-endian.
struct VSFrameHeader: Sendable {
    /// Frame sequence number. Monotonically increasing per display.
    let sequenceNumber: UInt32

    /// Identifier of the display this frame belongs to (1-based).
    let displayID: UInt8

    /// Bitfield flags (keyframe, end-of-frame, etc.).
    let flags: VSFrameFlags

    // MARK: - Serialization

    /// Serialize the header to a 10-byte Data blob.
    func serialize() -> Data {
        var data = Data(capacity: VSConstants.frameHeaderSize)

        // Magic bytes: "VPSI"
        data.append(contentsOf: VSConstants.frameMagic)

        // Sequence number (little-endian UInt32)
        var seqLE = sequenceNumber.littleEndian
        data.append(Data(bytes: &seqLE, count: MemoryLayout<UInt32>.size))

        // Display ID (UInt8)
        data.append(displayID)

        // Flags (UInt8)
        data.append(flags.rawValue)

        return data
    }

    /// Deserialize a header from at least 10 bytes of data.
    /// Returns nil if data is too short or magic bytes don't match.
    static func deserialize(from data: Data) -> VSFrameHeader? {
        guard data.count >= VSConstants.frameHeaderSize else {
            return nil
        }

        // Validate magic bytes
        let magic = Array(data[data.startIndex..<data.startIndex + 4])
        guard magic == VSConstants.frameMagic else {
            return nil
        }

        // Parse sequence number (little-endian)
        let seqBytes = data[data.startIndex + 4..<data.startIndex + 8]
        let sequenceNumber = seqBytes.withUnsafeBytes { ptr -> UInt32 in
            return UInt32(littleEndian: ptr.load(as: UInt32.self))
        }

        // Parse display ID
        let displayID = data[data.startIndex + 8]

        // Parse flags
        let flagsByte = data[data.startIndex + 9]
        let flags = VSFrameFlags(rawValue: flagsByte)

        return VSFrameHeader(
            sequenceNumber: sequenceNumber,
            displayID: displayID,
            flags: flags
        )
    }
}

// MARK: - Convenience Extensions

extension VSFrameHeader {
    /// Whether this packet contains keyframe data.
    var isKeyframe: Bool {
        flags.contains(.keyframe)
    }

    /// Whether this is the last packet of the current frame.
    var isEndOfFrame: Bool {
        flags.contains(.endOfFrame)
    }
}
