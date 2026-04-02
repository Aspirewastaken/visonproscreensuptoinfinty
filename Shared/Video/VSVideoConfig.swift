// VSVideoConfig.swift
// visionproscreensuptoinfinity
//
// Video configuration and display info types shared between
// macOS companion and visionOS app.
// MIT License - Copyright (c) 2024 Aspirewastaken

import Foundation

// MARK: - Video Configuration

/// Configuration for video encoding/decoding of a single display stream.
struct VSVideoConfig: Codable, Equatable, Sendable {
    /// Display width in pixels.
    let width: Int

    /// Display height in pixels.
    let height: Int

    /// Target frames per second.
    let fps: Int

    /// Target bitrate in bits per second.
    let bitrate: Int

    /// Keyframe interval in frames (e.g., 60 = one keyframe per second at 60fps).
    let keyframeInterval: Int

    // MARK: - Presets

    /// 1080p at 60fps, 20 Mbps — default for most use cases.
    static let hd1080 = VSVideoConfig(
        width: 1920,
        height: 1080,
        fps: 60,
        bitrate: 20_000_000,
        keyframeInterval: 60
    )

    /// 720p at 60fps, 10 Mbps — lower bandwidth option.
    static let hd720 = VSVideoConfig(
        width: 1280,
        height: 720,
        fps: 60,
        bitrate: 10_000_000,
        keyframeInterval: 60
    )

    /// 1440p at 60fps, 30 Mbps — high quality option.
    static let qhd1440 = VSVideoConfig(
        width: 2560,
        height: 1440,
        fps: 60,
        bitrate: 30_000_000,
        keyframeInterval: 60
    )

    /// 1080p at 30fps, 12 Mbps — battery saver / low bandwidth.
    static let hd1080Low = VSVideoConfig(
        width: 1920,
        height: 1080,
        fps: 30,
        bitrate: 12_000_000,
        keyframeInterval: 30
    )

    /// All available presets.
    static let allPresets: [String: VSVideoConfig] = [
        "720p": .hd720,
        "1080p": .hd1080,
        "1080p Low": .hd1080Low,
        "1440p": .qhd1440
    ]
}

// MARK: - Display Info

/// Information about a single virtual display, exchanged during pairing.
struct VSDisplayInfo: Codable, Identifiable, Equatable, Sendable {
    /// Unique display identifier (1-based, UInt8 range).
    let id: UInt8

    /// Human-readable display name (e.g., "Virtual Display 1").
    let name: String

    /// Current video configuration for this display.
    let config: VSVideoConfig

    /// Whether the display is currently actively streaming.
    var isStreaming: Bool

    init(id: UInt8, name: String, config: VSVideoConfig = .hd1080, isStreaming: Bool = false) {
        self.id = id
        self.name = name
        self.config = config
        self.isStreaming = isStreaming
    }
}

// MARK: - Display Resolution

/// Convenience struct for display resolution without full config.
struct VSResolution: Codable, Equatable, Hashable, Sendable {
    let width: Int
    let height: Int

    var label: String {
        "\(width)×\(height)"
    }

    static let r720p = VSResolution(width: 1280, height: 720)
    static let r1080p = VSResolution(width: 1920, height: 1080)
    static let r1440p = VSResolution(width: 2560, height: 1440)

    static let allResolutions: [VSResolution] = [.r720p, .r1080p, .r1440p]
}
