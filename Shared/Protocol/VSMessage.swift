// VSMessage.swift
// visionproscreensuptoinfinity
//
// Control message types for the TCP control channel.
// All messages are JSON-encoded with a type discriminator.
// MIT License - Copyright (c) 2024 Aspirewastaken

import Foundation

// MARK: - Message Type Enum

/// All control message types exchanged over the TCP control channel.
enum VSMessageType: String, Codable, CaseIterable {
    case pairRequest = "pair_request"
    case pairAccept = "pair_accept"
    case pairReject = "pair_reject"
    case displayAdd = "display_add"
    case displayRemove = "display_remove"
    case displayList = "display_list"
    case inputMouse = "input_mouse"
    case inputKey = "input_key"
    case inputScroll = "input_scroll"
    case requestKeyframe = "request_keyframe"
    case heartbeat = "heartbeat"
    case disconnect = "disconnect"
    case error = "error"
}

// MARK: - Envelope

/// Top-level message envelope. Every control message is wrapped in this structure.
/// The `payload` contains the JSON-encoded specific message data.
struct VSMessageEnvelope: Codable {
    let type: VSMessageType
    let payload: Data

    init<T: Encodable>(type: VSMessageType, message: T) throws {
        self.type = type
        self.payload = try JSONEncoder().encode(message)
    }

    func decode<T: Decodable>(as messageType: T.Type) throws -> T {
        return try JSONDecoder().decode(T.self, from: payload)
    }

    /// Serialize the entire envelope to JSON Data for transmission.
    func serialize() throws -> Data {
        return try JSONEncoder().encode(self)
    }

    /// Deserialize an envelope from received JSON Data.
    static func deserialize(from data: Data) throws -> VSMessageEnvelope {
        return try JSONDecoder().decode(VSMessageEnvelope.self, from: data)
    }
}

// MARK: - Concrete Message Types

/// Sent by visionOS client to initiate pairing with a Mac.
struct VSPairRequest: Codable {
    /// Human-readable name of the Vision Pro device.
    let deviceName: String
    /// Protocol version for compatibility checking.
    let protocolVersion: Int

    static let currentProtocolVersion = 1
}

/// Sent by Mac server to accept a pairing request.
struct VSPairAccept: Codable {
    /// Human-readable name of the Mac.
    let macName: String
    /// List of available/active display configurations.
    let displays: [VSDisplayInfo]
    /// Protocol version for compatibility checking.
    let protocolVersion: Int
}

/// Sent by Mac server to reject a pairing request.
struct VSPairReject: Codable {
    /// Reason for rejection.
    let reason: String
}

/// Request to create a new virtual display on the Mac.
struct VSDisplayAdd: Codable {
    /// Unique display identifier (1-based).
    let displayID: UInt8
    /// Desired display width in pixels.
    let width: Int
    /// Desired display height in pixels.
    let height: Int
    /// Desired display name.
    let name: String?
}

/// Request to remove a virtual display from the Mac.
struct VSDisplayRemove: Codable {
    /// Display identifier to remove.
    let displayID: UInt8
}

/// Current list of active displays on the Mac.
struct VSDisplayList: Codable {
    /// Array of active display information.
    let displays: [VSDisplayInfo]
}

/// Mouse input event forwarded from visionOS to Mac.
struct VSInputMouse: Codable {
    /// Target display identifier.
    let displayID: UInt8
    /// Normalized X position (0.0 = left edge, 1.0 = right edge).
    let x: Double
    /// Normalized Y position (0.0 = top edge, 1.0 = bottom edge).
    let y: Double
    /// Mouse button (0 = left, 1 = right, 2 = middle).
    let button: Int
    /// true = button pressed, false = button released, nil = move only.
    let pressed: Bool?
}

/// Keyboard input event forwarded from visionOS to Mac.
struct VSInputKey: Codable {
    /// Target display identifier.
    let displayID: UInt8
    /// Virtual key code (macOS CGKeyCode values).
    let keyCode: UInt16
    /// true = key pressed, false = key released.
    let down: Bool
    /// Modifier flags (shift, control, option, command).
    let modifiers: UInt64?
}

/// Scroll input event forwarded from visionOS to Mac.
struct VSInputScroll: Codable {
    /// Target display identifier.
    let displayID: UInt8
    /// Horizontal scroll delta.
    let deltaX: Double
    /// Vertical scroll delta.
    let deltaY: Double
}

/// Request from visionOS client for a fresh keyframe (IDR) on a specific display.
struct VSRequestKeyframe: Codable {
    /// Display identifier to request keyframe for.
    let displayID: UInt8
}

/// Heartbeat message to keep the connection alive and measure latency.
struct VSHeartbeat: Codable {
    /// Timestamp when the heartbeat was sent (milliseconds since epoch).
    let timestamp: UInt64

    /// Create a heartbeat with the current time.
    init() {
        self.timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
    }

    init(timestamp: UInt64) {
        self.timestamp = timestamp
    }
}

/// Disconnect notification.
struct VSDisconnect: Codable {
    /// Optional reason for disconnection.
    let reason: String?
}

/// Error message.
struct VSError: Codable {
    /// Error description.
    let message: String
    /// Error code for programmatic handling.
    let code: Int?
}

// MARK: - Display Statistics

/// Per-display streaming statistics for performance overlay and monitoring.
struct VSDisplayStats: Codable {
    /// Display identifier.
    let displayID: UInt8
    /// Current frames per second.
    let fps: Double
    /// Current bitrate in bits per second.
    let bitrate: Int
    /// Round-trip latency in milliseconds.
    let latencyMs: Double
    /// Number of dropped frames since last stats update.
    let droppedFrames: Int
    /// Total frames decoded/encoded since connection.
    let totalFrames: UInt64
}
