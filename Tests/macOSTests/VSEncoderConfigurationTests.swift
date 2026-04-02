import XCTest
@testable import Shared

final class VSEncoderConfigurationTests: XCTestCase {
    func testDefaultVideoConfigUsesOneSecondKeyframeInterval() {
        XCTAssertEqual(VSVideoConfig.default.keyframeIntervalSeconds, 1)
    }

    func testDefaultBitrateMatchesTwentyMbpsPreset() {
        XCTAssertEqual(VSVideoConfig.default.bitrate.id, "20mbps")
        XCTAssertEqual(VSVideoConfig.default.bitrate.bitsPerSecond, 20_000_000)
    }

    func testEstimatedBytesPerFrameIsPositive() {
        XCTAssertGreaterThan(VSVideoConfig.default.estimatedBytesPerFrame, 0)
    }
}
