// VSConstants.swift
// visionproscreensuptoinfinity
//
// Shared constants used by both macOS companion and visionOS app.
// MIT License - Copyright (c) 2024 Aspirewastaken

import Foundation

/// Central repository for all shared constants across the project.
enum VSConstants {

    // MARK: - Bonjour / Network Discovery

    /// Bonjour service type for discovering companion Mac apps on the local network.
    static let bonjourServiceType = "_visionproscreensuptoinfinity._tcp"

    /// Bonjour domain for local network browsing.
    static let bonjourDomain = "local."

    // MARK: - Wire Protocol

    /// Magic bytes that prefix every UDP frame packet: "VPSI" in ASCII.
    static let frameMagic: [UInt8] = [0x56, 0x50, 0x53, 0x49] // V P S I

    /// Size of the frame header in bytes: magic(4) + seqNum(4) + displayID(1) + flags(1) = 10
    static let frameHeaderSize = 10

    /// Maximum UDP packet payload size (fits within typical MTU without fragmentation).
    static let maxPacketPayloadSize = 1400

    // MARK: - Display Defaults

    /// Default display width in pixels.
    static let defaultWidth = 1920

    /// Default display height in pixels.
    static let defaultHeight = 1080

    /// Maximum supported display width.
    static let maxWidth = 2560

    /// Maximum supported display height.
    static let maxHeight = 1440

    // MARK: - Video Encoding Defaults

    /// Default target bitrate in bits per second (20 Mbps).
    static let defaultBitrate: Int = 20_000_000

    /// Minimum bitrate in bits per second (5 Mbps).
    static let minBitrate: Int = 5_000_000

    /// Maximum bitrate in bits per second (50 Mbps).
    static let maxBitrate: Int = 50_000_000

    /// Default target frames per second.
    static let defaultFPS: Int = 60

    /// Default keyframe interval in frames (1 keyframe per second at 60fps).
    static let defaultKeyframeInterval: Int = 60

    // MARK: - Network Ports

    /// TCP port used for the control channel (pairing, display management, input events).
    static let controlPort: UInt16 = 9847

    /// UDP port used for video frame streaming.
    static let videoPort: UInt16 = 9848

    // MARK: - Connection

    /// Heartbeat interval in seconds.
    static let heartbeatInterval: TimeInterval = 2.0

    /// Connection timeout in seconds (no heartbeat received).
    static let connectionTimeout: TimeInterval = 10.0

    /// Maximum number of simultaneous virtual displays.
    static let maxDisplays: Int = 4

    /// Maximum reconnection attempts before giving up.
    static let maxReconnectAttempts: Int = 5

    /// Base delay for reconnection backoff (seconds).
    static let reconnectBaseDelay: TimeInterval = 1.0

    // MARK: - Performance

    /// Number of consecutive dropped packets before requesting a keyframe.
    static let keyframeRequestThreshold: Int = 10

    /// Maximum number of packets to buffer during frame reassembly.
    static let maxReassemblyBufferSize: Int = 256
}
