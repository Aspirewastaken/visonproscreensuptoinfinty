import XCTest
@testable import Shared

final class VSMessageTests: XCTestCase {
    func testPairRequestRoundTrip() throws {
        let message = VSControlMessage.pairRequest(
            .init(
                macName: "Studio",
                displays: [
                    VSDisplayDescriptor(
                        id: 1,
                        name: "Display 1",
                        width: 1920,
                        height: 1080,
                        refreshRate: 60,
                        isVirtual: true
                    )
                ],
                protocolVersion: Int(VSConstants.protocolVersion),
                appVersion: "0.1.0",
            )
        )

        let encoded = try VSProtocol.encodeControlMessage(message)
        let decoded = try VSProtocol.decodeControlMessage(encoded.subdata(in: 4 ..< encoded.count))

        guard case .pairRequest(let request) = decoded else {
            return XCTFail("Expected pairRequest")
        }

        XCTAssertEqual(request.macName, "Studio")
        XCTAssertEqual(request.displays.count, 1)
        XCTAssertEqual(request.displays.first?.id, 1)
        XCTAssertEqual(request.protocolVersion, Int(VSConstants.protocolVersion))
    }

    func testInputKeyRoundTrip() throws {
        let original = VSControlMessage.inputKey(
            .init(displayID: 2, keyCode: 36, isKeyDown: true, modifiers: [.command, .shift])
        )

        let encoded = try VSProtocol.encodeControlMessage(original)
        let decoded = try VSProtocol.decodeControlMessage(encoded.subdata(in: 4 ..< encoded.count))

        guard case .inputKey(let event) = decoded else {
            return XCTFail("Expected inputKey")
        }

        XCTAssertEqual(event.displayID, 2)
        XCTAssertEqual(event.keyCode, 36)
        XCTAssertTrue(event.isKeyDown)
        XCTAssertEqual(event.modifiers, [.command, .shift])
    }
}
