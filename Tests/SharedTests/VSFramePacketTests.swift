// VSFramePacketTests.swift
// visionproscreensuptoinfinity
//
// Unit tests for VSFramePacket serialization, packetization,
// and frame reassembly.
// MIT License - Copyright (c) 2024 Aspirewastaken

import XCTest
@testable import VisionScreenMac

final class VSFramePacketTests: XCTestCase {

    // MARK: - Packet Serialization

    func testPacketSerializeDeserializeRoundtrip() {
        let header = VSFrameHeader(
            sequenceNumber: 1,
            displayID: 1,
            flags: [.keyframe, .endOfFrame]
        )
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let packet = VSFramePacket(header: header, payload: payload)

        let serialized = packet.serialize()
        let deserialized = VSFramePacket.deserialize(from: serialized)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.header.sequenceNumber, 1)
        XCTAssertEqual(deserialized?.header.displayID, 1)
        XCTAssertTrue(deserialized?.header.isKeyframe ?? false)
        XCTAssertTrue(deserialized?.header.isEndOfFrame ?? false)
        XCTAssertEqual(deserialized?.payload, payload)
    }

    func testPacketSerializeSizeCorrect() {
        let payload = Data(repeating: 0xAA, count: 100)
        let header = VSFrameHeader(
            sequenceNumber: 0,
            displayID: 0,
            flags: VSFrameFlags()
        )
        let packet = VSFramePacket(header: header, payload: payload)

        let serialized = packet.serialize()
        XCTAssertEqual(serialized.count, VSConstants.frameHeaderSize + 100)
    }

    func testPacketDeserializeEmptyPayload() {
        let header = VSFrameHeader(
            sequenceNumber: 5,
            displayID: 2,
            flags: [.endOfFrame]
        )
        let packet = VSFramePacket(header: header, payload: Data())

        let serialized = packet.serialize()
        let deserialized = VSFramePacket.deserialize(from: serialized)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.payload.count, 0)
        XCTAssertEqual(deserialized?.header.sequenceNumber, 5)
    }

    func testPacketDeserializeInvalidData() {
        let result = VSFramePacket.deserialize(from: Data([0x00, 0x01, 0x02]))
        XCTAssertNil(result, "Should return nil for invalid data")
    }

    // MARK: - Packetization

    func testPacketizeSmallFrame() {
        let frameData = Data(repeating: 0xAA, count: 100)
        let packets = VSFramePacket.packetize(
            frameData: frameData,
            sequenceNumber: 1,
            displayID: 1,
            isKeyframe: true
        )

        XCTAssertEqual(packets.count, 1, "Small frame should fit in one packet")
        XCTAssertTrue(packets[0].header.isKeyframe)
        XCTAssertTrue(packets[0].header.isEndOfFrame)
        XCTAssertEqual(packets[0].payload, frameData)
    }

    func testPacketizeLargeFrame() {
        let maxPayload = VSConstants.maxPacketPayloadSize
        let frameData = Data(repeating: 0xBB, count: maxPayload * 3 + 500) // 3.x packets worth

        let packets = VSFramePacket.packetize(
            frameData: frameData,
            sequenceNumber: 42,
            displayID: 2,
            isKeyframe: false
        )

        XCTAssertEqual(packets.count, 4, "Should split into 4 packets")

        // All packets should have same sequence number and display ID
        for packet in packets {
            XCTAssertEqual(packet.header.sequenceNumber, 42)
            XCTAssertEqual(packet.header.displayID, 2)
            XCTAssertFalse(packet.header.isKeyframe, "Non-keyframe should not have keyframe flag")
        }

        // Only last packet should have endOfFrame
        for (index, packet) in packets.enumerated() {
            if index == packets.count - 1 {
                XCTAssertTrue(packet.header.isEndOfFrame, "Last packet should have endOfFrame")
            } else {
                XCTAssertFalse(packet.header.isEndOfFrame, "Non-last packet should not have endOfFrame")
            }
        }

        // Reconstruct and verify total data
        var reconstructed = Data()
        for packet in packets {
            reconstructed.append(packet.payload)
        }
        XCTAssertEqual(reconstructed, frameData, "Reconstructed data should match original")
    }

    func testPacketizeKeyframeFlag() {
        let frameData = Data(repeating: 0xCC, count: 3000) // Multiple packets
        let packets = VSFramePacket.packetize(
            frameData: frameData,
            sequenceNumber: 1,
            displayID: 1,
            isKeyframe: true
        )

        // All packets of a keyframe should have the keyframe flag
        for packet in packets {
            XCTAssertTrue(packet.header.isKeyframe, "All packets of a keyframe should have keyframe flag set")
        }
    }

    func testPacketizeEmptyFrame() {
        let packets = VSFramePacket.packetize(
            frameData: Data(),
            sequenceNumber: 99,
            displayID: 1,
            isKeyframe: false
        )

        XCTAssertEqual(packets.count, 1, "Empty frame should produce one packet")
        XCTAssertTrue(packets[0].header.isEndOfFrame)
        XCTAssertEqual(packets[0].payload.count, 0)
    }

    func testPacketizeExactlyMaxPayloadSize() {
        let frameData = Data(repeating: 0xDD, count: VSConstants.maxPacketPayloadSize)
        let packets = VSFramePacket.packetize(
            frameData: frameData,
            sequenceNumber: 1,
            displayID: 1,
            isKeyframe: false
        )

        XCTAssertEqual(packets.count, 1, "Frame exactly at max payload size should be one packet")
        XCTAssertEqual(packets[0].payload.count, VSConstants.maxPacketPayloadSize)
    }

    func testPacketizeOneByteOverMaxPayloadSize() {
        let frameData = Data(repeating: 0xEE, count: VSConstants.maxPacketPayloadSize + 1)
        let packets = VSFramePacket.packetize(
            frameData: frameData,
            sequenceNumber: 1,
            displayID: 1,
            isKeyframe: false
        )

        XCTAssertEqual(packets.count, 2, "Frame one byte over max should split into 2 packets")
        XCTAssertEqual(packets[0].payload.count, VSConstants.maxPacketPayloadSize)
        XCTAssertEqual(packets[1].payload.count, 1)
    }

    func testPacketizeCustomMaxPayloadSize() {
        let frameData = Data(repeating: 0xFF, count: 100)
        let packets = VSFramePacket.packetize(
            frameData: frameData,
            sequenceNumber: 1,
            displayID: 1,
            isKeyframe: false,
            maxPayloadSize: 30
        )

        XCTAssertEqual(packets.count, 4, "100 bytes / 30 bytes per packet = 4 packets (ceiling)")

        var reconstructed = Data()
        for packet in packets {
            reconstructed.append(packet.payload)
        }
        XCTAssertEqual(reconstructed, frameData)
    }

    // MARK: - Frame Reassembler

    func testReassemblerSinglePacketFrame() {
        let reassembler = VSFrameReassembler()
        var completedFrames: [(UInt8, UInt32, Data, Bool)] = []

        reassembler.onFrameComplete = { displayID, seqNum, data, isKeyframe in
            completedFrames.append((displayID, seqNum, data, isKeyframe))
        }

        let packet = VSFramePacket(
            header: VSFrameHeader(sequenceNumber: 1, displayID: 1, flags: [.keyframe, .endOfFrame]),
            payload: Data([0x01, 0x02, 0x03])
        )

        reassembler.receive(packet: packet)

        XCTAssertEqual(completedFrames.count, 1)
        XCTAssertEqual(completedFrames[0].0, 1) // displayID
        XCTAssertEqual(completedFrames[0].1, 1) // seqNum
        XCTAssertEqual(completedFrames[0].2, Data([0x01, 0x02, 0x03]))
        XCTAssertTrue(completedFrames[0].3) // isKeyframe
    }

    func testReassemblerMultiPacketFrame() {
        let reassembler = VSFrameReassembler()
        var completedFrames: [(UInt8, UInt32, Data, Bool)] = []

        reassembler.onFrameComplete = { displayID, seqNum, data, isKeyframe in
            completedFrames.append((displayID, seqNum, data, isKeyframe))
        }

        // First packet (not end of frame)
        let packet1 = VSFramePacket(
            header: VSFrameHeader(sequenceNumber: 5, displayID: 2, flags: []),
            payload: Data([0xAA, 0xBB])
        )

        // Second packet (end of frame)
        let packet2 = VSFramePacket(
            header: VSFrameHeader(sequenceNumber: 5, displayID: 2, flags: [.endOfFrame]),
            payload: Data([0xCC, 0xDD])
        )

        reassembler.receive(packet: packet1)
        XCTAssertEqual(completedFrames.count, 0, "Frame should not be complete yet")

        reassembler.receive(packet: packet2)
        XCTAssertEqual(completedFrames.count, 1, "Frame should be complete now")
        XCTAssertEqual(completedFrames[0].2, Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    func testReassemblerMultipleDisplays() {
        let reassembler = VSFrameReassembler()
        var completedFrames: [(UInt8, UInt32, Data, Bool)] = []

        reassembler.onFrameComplete = { displayID, seqNum, data, isKeyframe in
            completedFrames.append((displayID, seqNum, data, isKeyframe))
        }

        // Display 1 packet
        let d1p1 = VSFramePacket(
            header: VSFrameHeader(sequenceNumber: 1, displayID: 1, flags: [.endOfFrame]),
            payload: Data([0x11])
        )

        // Display 2 packet
        let d2p1 = VSFramePacket(
            header: VSFrameHeader(sequenceNumber: 1, displayID: 2, flags: [.endOfFrame]),
            payload: Data([0x22])
        )

        reassembler.receive(packet: d1p1)
        reassembler.receive(packet: d2p1)

        XCTAssertEqual(completedFrames.count, 2)
        XCTAssertEqual(completedFrames[0].0, 1) // Display 1
        XCTAssertEqual(completedFrames[1].0, 2) // Display 2
    }

    func testReassemblerReset() {
        let reassembler = VSFrameReassembler()
        var completedFrames: [(UInt8, UInt32, Data, Bool)] = []

        reassembler.onFrameComplete = { displayID, seqNum, data, isKeyframe in
            completedFrames.append((displayID, seqNum, data, isKeyframe))
        }

        // Send first packet but don't complete frame
        let packet1 = VSFramePacket(
            header: VSFrameHeader(sequenceNumber: 1, displayID: 1, flags: []),
            payload: Data([0xAA])
        )
        reassembler.receive(packet: packet1)

        // Reset
        reassembler.reset()

        // Frame should not be emitted since we reset
        XCTAssertEqual(completedFrames.count, 0)
    }

    func testReassemblerNewSequenceDiscardsOld() {
        let reassembler = VSFrameReassembler()
        var completedFrames: [(UInt8, UInt32, Data, Bool)] = []

        reassembler.onFrameComplete = { displayID, seqNum, data, isKeyframe in
            completedFrames.append((displayID, seqNum, data, isKeyframe))
        }

        // Old frame (incomplete)
        let old = VSFramePacket(
            header: VSFrameHeader(sequenceNumber: 1, displayID: 1, flags: []),
            payload: Data([0xAA])
        )

        // New frame (different sequence, complete)
        let new = VSFramePacket(
            header: VSFrameHeader(sequenceNumber: 2, displayID: 1, flags: [.endOfFrame]),
            payload: Data([0xBB])
        )

        reassembler.receive(packet: old)
        reassembler.receive(packet: new)

        // Only the new frame should be emitted
        XCTAssertEqual(completedFrames.count, 1)
        XCTAssertEqual(completedFrames[0].1, 2) // New sequence number
        XCTAssertEqual(completedFrames[0].2, Data([0xBB]))
    }

    // MARK: - Full Pipeline Test

    func testPacketizeAndReassemble() {
        let originalData = Data(repeating: 0xAB, count: 5000) // ~4 packets

        // Packetize
        let packets = VSFramePacket.packetize(
            frameData: originalData,
            sequenceNumber: 10,
            displayID: 3,
            isKeyframe: true
        )

        XCTAssertGreaterThan(packets.count, 1)

        // Reassemble
        let reassembler = VSFrameReassembler()
        var result: (UInt8, UInt32, Data, Bool)?

        reassembler.onFrameComplete = { displayID, seqNum, data, isKeyframe in
            result = (displayID, seqNum, data, isKeyframe)
        }

        for packet in packets {
            // Simulate serialization over network
            let serialized = packet.serialize()
            let deserialized = VSFramePacket.deserialize(from: serialized)!
            reassembler.receive(packet: deserialized)
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, 3)  // displayID
        XCTAssertEqual(result?.1, 10) // seqNum
        XCTAssertEqual(result?.2, originalData) // data matches
        XCTAssertTrue(result?.3 ?? false) // isKeyframe
    }
}
