// VSInputInjector.swift
// visionproscreensuptoinfinity
//
// Injects mouse and keyboard events into macOS using CGEvent.
// Maps normalized coordinates from visionOS to absolute display positions.
// Requires Accessibility permissions.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(macOS)
import Foundation
import CoreGraphics
import ApplicationServices

/// Injects mouse and keyboard input events into macOS.
///
/// Events from the visionOS client are forwarded here for injection
/// into the correct virtual display's coordinate space.
///
/// Requires the "Accessibility" permission in System Settings >
/// Privacy & Security > Accessibility.
final class VSInputInjector {

    // MARK: - Types

    enum VSInputError: Error, LocalizedError {
        case accessibilityNotGranted
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Accessibility permission is required for input injection. Grant access in System Settings > Privacy & Security > Accessibility."
            case .eventCreationFailed:
                return "Failed to create CGEvent for input injection."
            }
        }
    }

    // MARK: - State

    private let eventSource: CGEventSource?

    init() {
        eventSource = CGEventSource(stateID: .hidSystemState)
    }

    // MARK: - Accessibility Permission

    /// Check whether accessibility permissions are granted.
    static var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }

    /// Prompt the user for accessibility permissions.
    /// Shows the system dialog if not already granted.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Mouse Input

    /// Inject a mouse move event.
    ///
    /// - Parameters:
    ///   - normalizedX: X position normalized to [0, 1] within the display.
    ///   - normalizedY: Y position normalized to [0, 1] within the display.
    ///   - displayID: The `CGDirectDisplayID` of the target display.
    func injectMouseMove(normalizedX: Double, normalizedY: Double, displayID: CGDirectDisplayID) {
        let point = absolutePosition(normalizedX: normalizedX, normalizedY: normalizedY, displayID: displayID)

        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)
    }

    /// Inject a mouse button event (click, press, or release).
    ///
    /// - Parameters:
    ///   - normalizedX: X position normalized to [0, 1].
    ///   - normalizedY: Y position normalized to [0, 1].
    ///   - button: Mouse button (0 = left, 1 = right, 2 = other/middle).
    ///   - pressed: true for button down, false for button up.
    ///   - displayID: Target display.
    func injectMouseButton(
        normalizedX: Double,
        normalizedY: Double,
        button: Int,
        pressed: Bool,
        displayID: CGDirectDisplayID
    ) {
        let point = absolutePosition(normalizedX: normalizedX, normalizedY: normalizedY, displayID: displayID)

        let mouseButton: CGMouseButton
        let mouseType: CGEventType

        switch button {
        case 0: // Left
            mouseButton = .left
            mouseType = pressed ? .leftMouseDown : .leftMouseUp
        case 1: // Right
            mouseButton = .right
            mouseType = pressed ? .rightMouseDown : .rightMouseUp
        default: // Middle / Other
            mouseButton = .center
            mouseType = pressed ? .otherMouseDown : .otherMouseUp
        }

        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: mouseType,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) else { return }

        event.post(tap: .cghidEventTap)
    }

    /// Inject a scroll wheel event.
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal scroll delta.
    ///   - deltaY: Vertical scroll delta.
    func injectScroll(deltaX: Int32, deltaY: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else { return }

        event.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard Input

    /// Inject a keyboard event (key press or release).
    ///
    /// - Parameters:
    ///   - keyCode: The virtual key code (CGKeyCode).
    ///   - down: true for key down, false for key up.
    ///   - modifiers: Optional modifier flags (shift, control, option, command).
    func injectKeyboard(keyCode: UInt16, down: Bool, modifiers: UInt64? = nil) {
        guard let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: down
        ) else { return }

        if let modifiers = modifiers {
            event.flags = CGEventFlags(rawValue: modifiers)
        }

        event.post(tap: .cghidEventTap)
    }

    // MARK: - Convenience: Process Control Messages

    /// Process a mouse input message from the visionOS client.
    func handleMouseInput(_ input: VSInputMouse, displayID: CGDirectDisplayID) {
        if let pressed = input.pressed {
            injectMouseButton(
                normalizedX: input.x,
                normalizedY: input.y,
                button: input.button,
                pressed: pressed,
                displayID: displayID
            )
        } else {
            injectMouseMove(
                normalizedX: input.x,
                normalizedY: input.y,
                displayID: displayID
            )
        }
    }

    /// Process a keyboard input message from the visionOS client.
    func handleKeyInput(_ input: VSInputKey) {
        injectKeyboard(
            keyCode: input.keyCode,
            down: input.down,
            modifiers: input.modifiers
        )
    }

    /// Process a scroll input message from the visionOS client.
    func handleScrollInput(_ input: VSInputScroll) {
        injectScroll(
            deltaX: Int32(input.deltaX),
            deltaY: Int32(input.deltaY)
        )
    }

    // MARK: - Private Helpers

    /// Convert normalized [0, 1] coordinates to absolute screen position
    /// accounting for display origin and size.
    private func absolutePosition(normalizedX: Double, normalizedY: Double, displayID: CGDirectDisplayID) -> CGPoint {
        let bounds = CGDisplayBounds(displayID)

        let x = bounds.origin.x + normalizedX * bounds.size.width
        let y = bounds.origin.y + normalizedY * bounds.size.height

        return CGPoint(x: x, y: y)
    }
}
#endif
