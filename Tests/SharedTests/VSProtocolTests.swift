// VSProtocolTests.swift
// visionproscreensuptoinfinity
//
// Unit tests for VSFrameHeader serialization, deserialization,
// and VSFrameFlags operations.
// MIT License - Copyright (c) 2024 Aspirewastaken

import XCTest
@testable import VisionScreenMac

final class VSProtocolTests: XCTestCase {

    // MARK: - Frame Header Serialization

    func testFrameHeaderSerializeProducesCorrectSize() {
        let header = VSFrameHeader(
            sequenceNumber: 1,
            displayID: 1,
            flags: VSFrameFlags()
        )

        let data = header.serialize()

        XCTAssertEqual(data.count, VSConstants.frameHeaderSize, "Header should be exactly \(VSConstants.frameHeaderSize) bytes")
    }

    func testFrameHeaderSerializeMagicBytes() {
        let header = VSFrameHeader(
            sequenceNumber: 0,
            displayID: 0,
            flags: VSFrameFlags()
        )

        let data = header.serialize()
        let magic = Array(data[0..<4])

        XCTAssertEqual(magic, VSConstants.frameMagic, "First 4 bytes should be VPSI magic bytes")
        XCTAssertEqual(magic, [0x56, 0x50, 0x53, 0x49])
    }

    func testFrameHeaderRoundtrip() {
        let original = VSFrameHeader(
            sequenceNumber: 42,
            displayID: 3,
            flags: [.keyframe, .endOfFrame]
        )

        let data = original.serialize()
        let deserialized = VSFrameHeader.deserialize(from: data)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.sequenceNumber, 42)
        XCTAssertEqual(deserialized?.displayID, 3)
        XCTAssertTrue(deserialized?.flags.contains(.keyframe) ?? false)
        XCTAssertTrue(deserialized?.flags.contains(.endOfFrame) ?? false)
    }

    func testFrameHeaderRoundtripMaxValues() {
        let original = VSFrameHeader(
            sequenceNumber: UInt32.max,
            displayID: UInt8.max,
            flags: VSFrameFlags(rawValue: 0xFF)
        )

        let data = original.serialize()
        let deserialized = VSFrameHeader.deserialize(from: data)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.sequenceNumber, UInt32.max)
        XCTAssertEqual(deserialized?.displayID, UInt8.max)
        XCTAssertEqual(deserialized?.flags.rawValue, 0xFF)
    }

    func testFrameHeaderRoundtripZeroValues() {
        let original = VSFrameHeader(
            sequenceNumber: 0,
            displayID: 0,
            flags: VSFrameFlags()
        )

        let data = original.serialize()
        let deserialized = VSFrameHeader.deserialize(from: data)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.sequenceNumber, 0)
        XCTAssertEqual(deserialized?.displayID, 0)
        XCTAssertEqual(deserialized?.flags.rawValue, 0)
    }

    func testFrameHeaderSequenceNumberLittleEndian() {
        let header = VSFrameHeader(
            sequenceNumber: 0x01020304,
            displayID: 0,
            flags: VSFrameFlags()
        )

        let data = header.serialize()
        // Bytes 4-7 should be little-endian: 04 03 02 01
        XCTAssertEqual(data[4], 0x04)
        XCTAssertEqual(data[5], 0x03)
        XCTAssertEqual(data[6], 0x02)
        XCTAssertEqual(data[7], 0x01)
    }

    // MARK: - Deserialization Error Cases

    func testDeserializeReturnsNilForTooShortData() {
        let shortData = Data([0x56, 0x50, 0x53]) // Only 3 bytes
        let result = VSFrameHeader.deserialize(from: shortData)
        XCTAssertNil(result, "Should return nil for data shorter than header size")
    }

    func testDeserializeReturnsNilForEmptyData() {
        let result = VSFrameHeader.deserialize(from: Data())
        XCTAssertNil(result, "Should return nil for empty data")
    }

    func testDeserializeReturnsNilForWrongMagic() {
        var data = Data(repeating: 0, count: VSConstants.frameHeaderSize)
        data[0] = 0x00 // Wrong magic
        data[1] = 0x00
        data[2] = 0x00
        data[3] = 0x00

        let result = VSFrameHeader.deserialize(from: data)
        XCTAssertNil(result, "Should return nil when magic bytes don't match")
    }

    func testDeserializeAcceptsExtraData() {
        let header = VSFrameHeader(
            sequenceNumber: 100,
            displayID: 2,
            flags: [.keyframe]
        )

        var data = header.serialize()
        data.append(Data(repeating: 0xAB, count: 100)) // Extra payload

        let deserialized = VSFrameHeader.deserialize(from: data)
        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.sequenceNumber, 100)
        XCTAssertEqual(deserialized?.displayID, 2)
    }

    // MARK: - Frame Flags

    func testFrameFlagsKeyframe() {
        let flags: VSFrameFlags = [.keyframe]
        XCTAssertEqual(flags.rawValue, 0x01)
        XCTAssertTrue(flags.contains(.keyframe))
        XCTAssertFalse(flags.contains(.endOfFrame))
    }

    func testFrameFlagsEndOfFrame() {
        let flags: VSFrameFlags = [.endOfFrame]
        XCTAssertEqual(flags.rawValue, 0x02)
        XCTAssertFalse(flags.contains(.keyframe))
        XCTAssertTrue(flags.contains(.endOfFrame))
    }

    func testFrameFlagsCombined() {
        let flags: VSFrameFlags = [.keyframe, .endOfFrame]
        XCTAssertEqual(flags.rawValue, 0x03)
        XCTAssertTrue(flags.contains(.keyframe))
        XCTAssertTrue(flags.contains(.endOfFrame))
    }

    func testFrameFlagsEmpty() {
        let flags = VSFrameFlags()
        XCTAssertEqual(flags.rawValue, 0x00)
        XCTAssertFalse(flags.contains(.keyframe))
        XCTAssertFalse(flags.contains(.endOfFrame))
    }

    // MARK: - Convenience Properties

    func testHeaderIsKeyframeProperty() {
        let keyframeHeader = VSFrameHeader(
            sequenceNumber: 1,
            displayID: 1,
            flags: [.keyframe]
        )
        XCTAssertTrue(keyframeHeader.isKeyframe)
        XCTAssertFalse(keyframeHeader.isEndOfFrame)

        let nonKeyframeHeader = VSFrameHeader(
            sequenceNumber: 2,
            displayID: 1,
            flags: []
        )
        XCTAssertFalse(nonKeyframeHeader.isKeyframe)
    }

    func testHeaderIsEndOfFrameProperty() {
        let endHeader = VSFrameHeader(
            sequenceNumber: 1,
            displayID: 1,
            flags: [.endOfFrame]
        )
        XCTAssertTrue(endHeader.isEndOfFrame)
        XCTAssertFalse(endHeader.isKeyframe)
    }
}
