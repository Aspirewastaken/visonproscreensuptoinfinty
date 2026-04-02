// VSInputForwarder.swift
// visionproscreensuptoinfinity
//
// Captures and forwards input events from visionOS to the Mac server.
// Maps spatial gestures and trackpad input to mouse/keyboard events.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(visionOS)
import Foundation

/// Forwards input events from the visionOS app to the connected Mac server.
///
/// Input types:
/// - Mouse movement: derived from gaze/hover position on display windows
/// - Mouse clicks: derived from tap gestures on display surfaces
/// - Keyboard: forwarded from hardware keyboard connected to Vision Pro
/// - Scroll: derived from trackpad scroll gestures
///
/// All coordinates are normalized to [0, 1] range relative to the
/// display window, then converted to display pixel coordinates on the Mac side.
final class VSInputForwarder {

    // MARK: - Dependencies

    /// Reference to the control connection for sending input messages.
    weak var controlConnection: VSControlConnection?

    // MARK: - Rate Limiting

    /// Minimum interval between mouse move events (seconds).
    /// Prevents flooding the network with cursor updates.
    private let mouseMoveThrottleInterval: TimeInterval = 1.0 / 120.0  // 120 Hz max
    private var lastMouseMoveTime: [UInt8: Date] = [:]

    // MARK: - Mouse Input

    /// Forward a mouse move event to the Mac.
    ///
    /// - Parameters:
    ///   - normalizedX: X position normalized to [0, 1] within the display.
    ///   - normalizedY: Y position normalized to [0, 1] within the display.
    ///   - displayID: Target display identifier.
    func forwardMouseMove(normalizedX: Double, normalizedY: Double, displayID: UInt8) {
        // Rate limiting
        let now = Date()
        if let lastTime = lastMouseMoveTime[displayID],
           now.timeIntervalSince(lastTime) < mouseMoveThrottleInterval {
            return
        }
        lastMouseMoveTime[displayID] = now

        let message = VSInputMouse(
            displayID: displayID,
            x: clamp(normalizedX),
            y: clamp(normalizedY),
            button: 0,
            pressed: nil  // nil = move only, no button event
        )

        controlConnection?.send(type: .inputMouse, message: message)
    }

    /// Forward a mouse click event to the Mac.
    ///
    /// - Parameters:
    ///   - normalizedX: X position normalized to [0, 1].
    ///   - normalizedY: Y position normalized to [0, 1].
    ///   - button: Mouse button (0 = left, 1 = right, 2 = middle).
    ///   - pressed: true for mouse down, false for mouse up.
    ///   - displayID: Target display identifier.
    func forwardMouseClick(
        normalizedX: Double,
        normalizedY: Double,
        button: Int,
        pressed: Bool,
        displayID: UInt8
    ) {
        let message = VSInputMouse(
            displayID: displayID,
            x: clamp(normalizedX),
            y: clamp(normalizedY),
            button: button,
            pressed: pressed
        )

        controlConnection?.send(type: .inputMouse, message: message)
    }

    // MARK: - Keyboard Input

    /// Forward a key press/release event to the Mac.
    ///
    /// - Parameters:
    ///   - keyCode: Virtual key code (macOS CGKeyCode values).
    ///   - down: true for key down, false for key up.
    ///   - displayID: Target display identifier.
    ///   - modifiers: Optional modifier flags.
    func forwardKeyPress(
        keyCode: UInt16,
        down: Bool,
        displayID: UInt8,
        modifiers: UInt64? = nil
    ) {
        let message = VSInputKey(
            displayID: displayID,
            keyCode: keyCode,
            down: down,
            modifiers: modifiers
        )

        controlConnection?.send(type: .inputKey, message: message)
    }

    // MARK: - Scroll Input

    /// Forward a scroll event to the Mac.
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal scroll delta.
    ///   - deltaY: Vertical scroll delta.
    ///   - displayID: Target display identifier.
    func forwardScroll(deltaX: Double, deltaY: Double, displayID: UInt8) {
        let message = VSInputScroll(
            displayID: displayID,
            deltaX: deltaX,
            deltaY: deltaY
        )

        controlConnection?.send(type: .inputScroll, message: message)
    }

    // MARK: - Helpers

    /// Clamp a value to [0, 1] range.
    private func clamp(_ value: Double) -> Double {
        return min(max(value, 0.0), 1.0)
    }
}
#endif
