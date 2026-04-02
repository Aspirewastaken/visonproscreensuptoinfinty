import XCTest
@testable import Shared

final class VSVideoConfigMacTests: XCTestCase {
    func testDefaultConfigUses1080pPreset() {
        XCTAssertEqual(VSVideoConfig.default.resolution.id, "1080p")
        XCTAssertEqual(VSVideoConfig.default.framesPerSecond, 60)
    }
}
