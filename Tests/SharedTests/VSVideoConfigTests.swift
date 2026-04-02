import XCTest
@testable import Shared

final class VSVideoConfigTests: XCTestCase {
    func testPayloadBudgetSubtractsHeaderSize() {
        let config = VSVideoConfig.default
        XCTAssertEqual(
            config.payloadBudget(maximumDatagramSize: VSConstants.Network.defaultMaximumDatagramSize),
            VSConstants.Network.defaultMaximumDatagramSize - VSFramePacketHeader.encodedLength
        )
    }

    func testEstimatedFragmentCountIsAtLeastOne() {
        let config = VSVideoConfig.default
        XCTAssertGreaterThanOrEqual(config.estimatedFragmentCount(), 1)
    }
}
