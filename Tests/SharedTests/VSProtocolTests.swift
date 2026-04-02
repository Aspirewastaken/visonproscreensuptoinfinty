import XCTest
@testable import Shared

final class VSProtocolTests: XCTestCase {
    func testRoundTripsLengthPrefixedMessage() throws {
        let message = VSControlMessage.pairRequest(
            .init(
                macName: "Mac Studio",
                displays: [
                    VSDisplayDescriptor(
                        id: 1,
                        name: "Desk Left",
                        width: 1920,
                        height: 1080,
                        refreshRate: 60,
                        isVirtual: true
                    )
                ],
                protocolVersion: Int(VSConstants.protocolVersion),
                appVersion: "0.1.0"
            )
        )

        let encoded = try VSProtocol.encodeControlMessage(message)
        let (decoded, consumed) = try VSProtocol.decodeFrame(from: encoded)

        XCTAssertEqual(consumed, encoded.count)
        XCTAssertEqual(decoded, message)
    }

    func testDecodeFrameRejectsWrongProtocolVersion() throws {
        XCTAssertThrowsError(try VSProtocol.validate(version: 255)) { error in
            guard case VSProtocolError.unsupportedVersion(let version) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, 255)
        }
    }

    func testMessageBoundaryRequiresCompletePayload() throws {
        let message = VSControlMessage.pairAccept(.init(sessionID: UUID()))
        let encoded = try VSProtocol.encodeControlMessage(message)

        XCTAssertThrowsError(try VSProtocol.decodeFrame(from: encoded.dropLast())) { error in
            guard case VSProtocolError.incompleteFrame = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
