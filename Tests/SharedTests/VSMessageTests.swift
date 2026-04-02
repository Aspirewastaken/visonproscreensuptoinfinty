// VSMessageTests.swift
// visionproscreensuptoinfinity
//
// Unit tests for control message encoding and decoding.
// MIT License - Copyright (c) 2024 Aspirewastaken

import XCTest
@testable import VisionScreenMac

final class VSMessageTests: XCTestCase {

    // MARK: - VSMessageEnvelope

    func testEnvelopeSerializeDeserializeRoundtrip() throws {
        let request = VSPairRequest(
            deviceName: "Test Vision Pro",
            protocolVersion: 1
        )

        let envelope = try VSMessageEnvelope(type: .pairRequest, message: request)
        let data = try envelope.serialize()
        let decoded = try VSMessageEnvelope.deserialize(from: data)

        XCTAssertEqual(decoded.type, .pairRequest)

        let decodedRequest = try decoded.decode(as: VSPairRequest.self)
        XCTAssertEqual(decodedRequest.deviceName, "Test Vision Pro")
        XCTAssertEqual(decodedRequest.protocolVersion, 1)
    }

    // MARK: - VSPairRequest

    func testPairRequestEncoding() throws {
        let request = VSPairRequest(
            deviceName: "My Vision Pro",
            protocolVersion: VSPairRequest.currentProtocolVersion
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(VSPairRequest.self, from: data)

        XCTAssertEqual(decoded.deviceName, "My Vision Pro")
        XCTAssertEqual(decoded.protocolVersion, VSPairRequest.currentProtocolVersion)
    }

    // MARK: - VSPairAccept

    func testPairAcceptWithDisplays() throws {
        let displays = [
            VSDisplayInfo(id: 1, name: "Display 1", config: .hd1080, isStreaming: true),
            VSDisplayInfo(id: 2, name: "Display 2", config: .hd720, isStreaming: false)
        ]

        let accept = VSPairAccept(
            macName: "Test Mac",
            displays: displays,
            protocolVersion: 1
        )

        let data = try JSONEncoder().encode(accept)
        let decoded = try JSONDecoder().decode(VSPairAccept.self, from: data)

        XCTAssertEqual(decoded.macName, "Test Mac")
        XCTAssertEqual(decoded.displays.count, 2)
        XCTAssertEqual(decoded.displays[0].name, "Display 1")
        XCTAssertEqual(decoded.displays[0].config.width, 1920)
        XCTAssertEqual(decoded.displays[1].name, "Display 2")
        XCTAssertEqual(decoded.displays[1].config.width, 1280)
    }

    // MARK: - VSDisplayAdd

    func testDisplayAddEncoding() throws {
        let add = VSDisplayAdd(
            displayID: 3,
            width: 2560,
            height: 1440,
            name: "Big Display"
        )

        let data = try JSONEncoder().encode(add)
        let decoded = try JSONDecoder().decode(VSDisplayAdd.self, from: data)

        XCTAssertEqual(decoded.displayID, 3)
        XCTAssertEqual(decoded.width, 2560)
        XCTAssertEqual(decoded.height, 1440)
        XCTAssertEqual(decoded.name, "Big Display")
    }

    func testDisplayAddWithNilName() throws {
        let add = VSDisplayAdd(
            displayID: 1,
            width: 1920,
            height: 1080,
            name: nil
        )

        let data = try JSONEncoder().encode(add)
        let decoded = try JSONDecoder().decode(VSDisplayAdd.self, from: data)

        XCTAssertEqual(decoded.displayID, 1)
        XCTAssertNil(decoded.name)
    }

    // MARK: - VSDisplayRemove

    func testDisplayRemoveEncoding() throws {
        let remove = VSDisplayRemove(displayID: 2)

        let data = try JSONEncoder().encode(remove)
        let decoded = try JSONDecoder().decode(VSDisplayRemove.self, from: data)

        XCTAssertEqual(decoded.displayID, 2)
    }

    // MARK: - VSInputMouse

    func testInputMouseMoveOnly() throws {
        let mouse = VSInputMouse(
            displayID: 1,
            x: 0.5,
            y: 0.75,
            button: 0,
            pressed: nil
        )

        let data = try JSONEncoder().encode(mouse)
        let decoded = try JSONDecoder().decode(VSInputMouse.self, from: data)

        XCTAssertEqual(decoded.displayID, 1)
        XCTAssertEqual(decoded.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded.y, 0.75, accuracy: 0.001)
        XCTAssertEqual(decoded.button, 0)
        XCTAssertNil(decoded.pressed)
    }

    func testInputMouseClick() throws {
        let mouse = VSInputMouse(
            displayID: 2,
            x: 0.3,
            y: 0.4,
            button: 1,
            pressed: true
        )

        let data = try JSONEncoder().encode(mouse)
        let decoded = try JSONDecoder().decode(VSInputMouse.self, from: data)

        XCTAssertEqual(decoded.button, 1)
        XCTAssertEqual(decoded.pressed, true)
    }

    // MARK: - VSInputKey

    func testInputKeyEncoding() throws {
        let key = VSInputKey(
            displayID: 1,
            keyCode: 36,  // Return key
            down: true,
            modifiers: nil
        )

        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(VSInputKey.self, from: data)

        XCTAssertEqual(decoded.displayID, 1)
        XCTAssertEqual(decoded.keyCode, 36)
        XCTAssertTrue(decoded.down)
        XCTAssertNil(decoded.modifiers)
    }

    func testInputKeyWithModifiers() throws {
        let key = VSInputKey(
            displayID: 1,
            keyCode: 0,
            down: true,
            modifiers: 0x100108 // Command + Shift
        )

        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(VSInputKey.self, from: data)

        XCTAssertEqual(decoded.modifiers, 0x100108)
    }

    // MARK: - VSInputScroll

    func testInputScrollEncoding() throws {
        let scroll = VSInputScroll(
            displayID: 1,
            deltaX: -3.5,
            deltaY: 10.0
        )

        let data = try JSONEncoder().encode(scroll)
        let decoded = try JSONDecoder().decode(VSInputScroll.self, from: data)

        XCTAssertEqual(decoded.displayID, 1)
        XCTAssertEqual(decoded.deltaX, -3.5, accuracy: 0.001)
        XCTAssertEqual(decoded.deltaY, 10.0, accuracy: 0.001)
    }

    // MARK: - VSRequestKeyframe

    func testRequestKeyframeEncoding() throws {
        let request = VSRequestKeyframe(displayID: 4)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(VSRequestKeyframe.self, from: data)

        XCTAssertEqual(decoded.displayID, 4)
    }

    // MARK: - VSHeartbeat

    func testHeartbeatTimestamp() throws {
        let heartbeat = VSHeartbeat()

        let data = try JSONEncoder().encode(heartbeat)
        let decoded = try JSONDecoder().decode(VSHeartbeat.self, from: data)

        XCTAssertGreaterThan(decoded.timestamp, 0)
        // Timestamp should be close to now
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
        XCTAssertTrue(abs(Int64(decoded.timestamp) - Int64(nowMs)) < 5000, "Timestamp should be within 5 seconds of now")
    }

    func testHeartbeatCustomTimestamp() throws {
        let heartbeat = VSHeartbeat(timestamp: 1234567890)

        let data = try JSONEncoder().encode(heartbeat)
        let decoded = try JSONDecoder().decode(VSHeartbeat.self, from: data)

        XCTAssertEqual(decoded.timestamp, 1234567890)
    }

    // MARK: - VSDisconnect

    func testDisconnectWithReason() throws {
        let disconnect = VSDisconnect(reason: "User requested")

        let data = try JSONEncoder().encode(disconnect)
        let decoded = try JSONDecoder().decode(VSDisconnect.self, from: data)

        XCTAssertEqual(decoded.reason, "User requested")
    }

    func testDisconnectWithoutReason() throws {
        let disconnect = VSDisconnect(reason: nil)

        let data = try JSONEncoder().encode(disconnect)
        let decoded = try JSONDecoder().decode(VSDisconnect.self, from: data)

        XCTAssertNil(decoded.reason)
    }

    // MARK: - VSError

    func testErrorEncoding() throws {
        let error = VSError(message: "Something went wrong", code: 42)

        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(VSError.self, from: data)

        XCTAssertEqual(decoded.message, "Something went wrong")
        XCTAssertEqual(decoded.code, 42)
    }

    // MARK: - VSDisplayStats

    func testDisplayStatsEncoding() throws {
        let stats = VSDisplayStats(
            displayID: 1,
            fps: 59.97,
            bitrate: 20_000_000,
            latencyMs: 8.5,
            droppedFrames: 3,
            totalFrames: 10000
        )

        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(VSDisplayStats.self, from: data)

        XCTAssertEqual(decoded.displayID, 1)
        XCTAssertEqual(decoded.fps, 59.97, accuracy: 0.01)
        XCTAssertEqual(decoded.bitrate, 20_000_000)
        XCTAssertEqual(decoded.latencyMs, 8.5, accuracy: 0.1)
        XCTAssertEqual(decoded.droppedFrames, 3)
        XCTAssertEqual(decoded.totalFrames, 10000)
    }

    // MARK: - VSMessageType

    func testAllMessageTypesHaveRawValues() {
        for type in VSMessageType.allCases {
            XCTAssertFalse(type.rawValue.isEmpty, "Message type \(type) should have a non-empty raw value")
        }
    }

    func testMessageTypeDecoding() throws {
        let json = "\"pair_request\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VSMessageType.self, from: data)
        XCTAssertEqual(decoded, .pairRequest)
    }
}
