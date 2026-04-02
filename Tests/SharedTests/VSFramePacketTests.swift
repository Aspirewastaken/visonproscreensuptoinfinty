import XCTest
@testable import Shared

final class VSFramePacketTests: XCTestCase {
    func testFramePacketRoundTrips() throws {
        let packet = VSFramePacket(
            header: VSFramePacketHeader(
                displayID: 2,
                flags: [.keyframe, .endOfFrame],
                sequenceNumber: 42,
                frameNumber: 7,
                fragmentIndex: 0,
                fragmentCount: 1,
                presentationTimestampMicros: 1_234_567
            ),
            payload: Data([0x01, 0x02, 0x03])
        )

        let encoded = try packet.encode()
        let decoded = try VSFramePacket.decode(encoded)

        XCTAssertEqual(decoded, packet)
    }

    func testFragmentationProducesMultiplePackets() throws {
        let payload = Data(repeating: 0xAB, count: 5_000)
        let packets = try VSFramePacketizer().fragment(
            displayID: 1,
            frameNumber: 55,
            initialSequenceNumber: 100,
            timestampMicros: 99,
            payload: payload,
            isKeyframe: true,
            maxPayloadSize: 1_000
        )

        XCTAssertGreaterThan(packets.count, 1)
        XCTAssertEqual(packets.first?.header.fragmentIndex, 0)
        XCTAssertEqual(packets.last?.header.flags.contains(.endOfFrame), true)
        XCTAssertEqual(Set(packets.map(\.header.fragmentCount)).count, 1)
    }

    func testReassemblySucceedsForOrderedPackets() throws {
        let payload = Data((0 ..< 3_000).map { UInt8($0 % 251) })
        let packets = try VSFramePacketizer().fragment(
            displayID: 1,
            frameNumber: 9,
            initialSequenceNumber: 0,
            timestampMicros: 321,
            payload: payload,
            isKeyframe: false,
            maxPayloadSize: 900
        )

        var reassembler = VSFrameReassembler.State()
        var reconstructed: VSReassembledFrame?

        for packet in packets {
            reconstructed = reassembler.insert(packet)
        }

        XCTAssertEqual(reconstructed?.payload, payload)
        XCTAssertEqual(reconstructed?.frameNumber, 9)
    }

    func testMissingFragmentPreventsReassembly() throws {
        let payload = Data(repeating: 0xCD, count: 4_000)
        let packets = try VSFramePacketizer().fragment(
            displayID: 1,
            frameNumber: 88,
            initialSequenceNumber: 10,
            timestampMicros: 432,
            payload: payload,
            isKeyframe: false,
            maxPayloadSize: 1_000
        )

        var reassembler = VSFrameReassembler.State()
        var result: VSReassembledFrame?

        for packet in packets.enumerated().filter({ $0.offset != 1 }).map(\.element) {
            result = reassembler.insert(packet)
        }

        XCTAssertNil(result)
    }

    func testStaleFrameIsDiscardedWhenNewerFrameArrives() throws {
        let older = try VSFramePacketizer().fragment(
            displayID: 1,
            frameNumber: 10,
            initialSequenceNumber: 1,
            timestampMicros: 100,
            payload: Data(repeating: 0x11, count: 2_000),
            isKeyframe: false,
            maxPayloadSize: 900
        )
        let newer = try VSFramePacketizer().fragment(
            displayID: 1,
            frameNumber: 11,
            initialSequenceNumber: 9,
            timestampMicros: 101,
            payload: Data(repeating: 0x22, count: 2_000),
            isKeyframe: true,
            maxPayloadSize: 900
        )

        var reassembler = VSFrameReassembler.State()
        _ = reassembler.insert(older[0])
        let dropped = reassembler.droppedFrameCount

        var frame: VSReassembledFrame?
        for packet in newer {
            frame = reassembler.insert(packet) ?? frame
        }

        XCTAssertGreaterThan(reassembler.droppedFrameCount, dropped)
        XCTAssertEqual(frame?.frameNumber, 11)
        XCTAssertEqual(frame?.payload, Data(repeating: 0x22, count: 2_000))
    }
}
