// VSEncoderTests.swift
// visionproscreensuptoinfinity
//
// Unit tests for video configuration and encoder-related types.
// Note: VTCompressionSession tests require macOS hardware and
// will only pass when run on a Mac with Apple Silicon.
// MIT License - Copyright (c) 2024 Aspirewastaken

import XCTest
@testable import VisionScreenMac

final class VSEncoderTests: XCTestCase {

    // MARK: - VSVideoConfig Presets

    func testHD1080Preset() {
        let config = VSVideoConfig.hd1080
        XCTAssertEqual(config.width, 1920)
        XCTAssertEqual(config.height, 1080)
        XCTAssertEqual(config.fps, 60)
        XCTAssertEqual(config.bitrate, 20_000_000)
        XCTAssertEqual(config.keyframeInterval, 60)
    }

    func testHD720Preset() {
        let config = VSVideoConfig.hd720
        XCTAssertEqual(config.width, 1280)
        XCTAssertEqual(config.height, 720)
        XCTAssertEqual(config.fps, 60)
        XCTAssertEqual(config.bitrate, 10_000_000)
    }

    func testQHD1440Preset() {
        let config = VSVideoConfig.qhd1440
        XCTAssertEqual(config.width, 2560)
        XCTAssertEqual(config.height, 1440)
        XCTAssertEqual(config.fps, 60)
        XCTAssertEqual(config.bitrate, 30_000_000)
    }

    func testHD1080LowPreset() {
        let config = VSVideoConfig.hd1080Low
        XCTAssertEqual(config.width, 1920)
        XCTAssertEqual(config.height, 1080)
        XCTAssertEqual(config.fps, 30)
        XCTAssertEqual(config.bitrate, 12_000_000)
        XCTAssertEqual(config.keyframeInterval, 30)
    }

    // MARK: - VSVideoConfig Codable

    func testVideoConfigCodableRoundtrip() throws {
        let config = VSVideoConfig(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrate: 25_000_000,
            keyframeInterval: 120
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VSVideoConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    func testVideoConfigEquality() {
        let a = VSVideoConfig.hd1080
        let b = VSVideoConfig(width: 1920, height: 1080, fps: 60, bitrate: 20_000_000, keyframeInterval: 60)
        let c = VSVideoConfig.hd720

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - VSDisplayInfo

    func testDisplayInfoCreation() {
        let info = VSDisplayInfo(id: 1, name: "Test Display")
        XCTAssertEqual(info.id, 1)
        XCTAssertEqual(info.name, "Test Display")
        XCTAssertEqual(info.config, .hd1080)
        XCTAssertFalse(info.isStreaming)
    }

    func testDisplayInfoCodableRoundtrip() throws {
        let info = VSDisplayInfo(
            id: 3,
            name: "Big Monitor",
            config: .qhd1440,
            isStreaming: true
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(VSDisplayInfo.self, from: data)

        XCTAssertEqual(decoded.id, 3)
        XCTAssertEqual(decoded.name, "Big Monitor")
        XCTAssertEqual(decoded.config, .qhd1440)
        XCTAssertTrue(decoded.isStreaming)
    }

    // MARK: - VSResolution

    func testResolutionPresets() {
        XCTAssertEqual(VSResolution.r720p.width, 1280)
        XCTAssertEqual(VSResolution.r720p.height, 720)
        XCTAssertEqual(VSResolution.r1080p.width, 1920)
        XCTAssertEqual(VSResolution.r1080p.height, 1080)
        XCTAssertEqual(VSResolution.r1440p.width, 2560)
        XCTAssertEqual(VSResolution.r1440p.height, 1440)
    }

    func testResolutionLabel() {
        XCTAssertEqual(VSResolution.r1080p.label, "1920×1080")
        XCTAssertEqual(VSResolution.r720p.label, "1280×720")
    }

    func testAllResolutionsCount() {
        XCTAssertEqual(VSResolution.allResolutions.count, 3)
    }

    func testResolutionHashable() {
        var set = Set<VSResolution>()
        set.insert(.r1080p)
        set.insert(.r1080p) // Duplicate
        set.insert(.r720p)

        XCTAssertEqual(set.count, 2)
    }

    // MARK: - VSConstants

    func testDefaultValues() {
        XCTAssertEqual(VSConstants.defaultWidth, 1920)
        XCTAssertEqual(VSConstants.defaultHeight, 1080)
        XCTAssertEqual(VSConstants.defaultFPS, 60)
        XCTAssertEqual(VSConstants.defaultBitrate, 20_000_000)
        XCTAssertEqual(VSConstants.maxDisplays, 4)
    }

    func testFrameMagicIsVPSI() {
        // V = 0x56, P = 0x50, S = 0x53, I = 0x49
        let magic = VSConstants.frameMagic
        let str = String(bytes: magic, encoding: .ascii)
        XCTAssertEqual(str, "VPSI")
    }

    func testFrameHeaderSize() {
        // magic(4) + seqNum(4) + displayID(1) + flags(1) = 10
        XCTAssertEqual(VSConstants.frameHeaderSize, 10)
    }

    func testPortsAreInValidRange() {
        XCTAssertGreaterThan(VSConstants.controlPort, 1024, "Control port should be above well-known range")
        XCTAssertGreaterThan(VSConstants.videoPort, 1024, "Video port should be above well-known range")
        XCTAssertNotEqual(VSConstants.controlPort, VSConstants.videoPort, "Control and video ports must differ")
    }

    func testBonjourServiceType() {
        XCTAssertTrue(VSConstants.bonjourServiceType.hasPrefix("_"), "Bonjour type should start with underscore")
        XCTAssertTrue(VSConstants.bonjourServiceType.hasSuffix("._tcp"), "Bonjour type should end with ._tcp")
    }

    // MARK: - Preset Map

    func testAllPresetsMap() {
        let presets = VSVideoConfig.allPresets
        XCTAssertGreaterThanOrEqual(presets.count, 3)
        XCTAssertNotNil(presets["1080p"])
        XCTAssertNotNil(presets["720p"])
        XCTAssertNotNil(presets["1440p"])
    }
}
