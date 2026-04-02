import AppKit
import CoreGraphics
import Foundation
import Shared

public enum VSInputInjectorError: Error, LocalizedError, Equatable {
    case accessibilityDenied
    case unknownDisplay(UInt8)

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Accessibility permission is required to inject mouse and keyboard input."
        case .unknownDisplay(let displayID):
            return "Could not resolve display \(displayID) for input injection."
        }
    }
}

@MainActor
public final class VSInputInjector {
    private let displayRegistry: VSDisplayRegistry

    public init(displayRegistry: VSDisplayRegistry) {
        self.displayRegistry = displayRegistry
    }

    public func injectMouseMove(_ message: VSMouseMoveMessage) throws {
        guard AXIsProcessTrusted() else {
            throw VSInputInjectorError.accessibilityDenied
        }
        let location = try globalPoint(for: message.displayID, normalizedX: message.x, normalizedY: message.y)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left) {
            event.timestamp = eventTimestamp()
            event.post(tap: .cghidEventTap)
        }
    }

    public func injectMouseButton(_ message: VSMouseButtonMessage) throws {
        guard AXIsProcessTrusted() else {
            throw VSInputInjectorError.accessibilityDenied
        }
        let location = try globalPoint(for: message.displayID, normalizedX: message.x, normalizedY: message.y)
        let button = cgMouseButton(from: message.button)

        let eventTypes: [CGEventType]
        switch message.phase {
        case .down:
            eventTypes = [mouseDownType(for: button)]
        case .up:
            eventTypes = [mouseUpType(for: button)]
        case .click:
            eventTypes = [mouseDownType(for: button), mouseUpType(for: button)]
        }

        for eventType in eventTypes {
            if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: location, mouseButton: button) {
                event.timestamp = eventTimestamp()
                event.post(tap: .cghidEventTap)
            }
        }
    }

    public func injectScroll(_ message: VSScrollMessage) throws {
        guard AXIsProcessTrusted() else {
            throw VSInputInjectorError.accessibilityDenied
        }

        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(message.deltaY.rounded()),
            wheel2: Int32(message.deltaX.rounded()),
            wheel3: 0
        )
        event?.timestamp = eventTimestamp()
        event?.post(tap: .cghidEventTap)
    }

    public func injectKey(_ message: VSKeyMessage) throws {
        guard AXIsProcessTrusted() else {
            throw VSInputInjectorError.accessibilityDenied
        }

        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(message.keyCode),
            keyDown: message.isKeyDown
        )
        event?.flags = cgEventFlags(from: message.modifiers)
        event?.timestamp = eventTimestamp()
        if let characters = message.characters {
            event?.keyboardSetUnicodeString(stringLength: characters.utf16.count, unicodeString: Array(characters.utf16))
        }
        event?.post(tap: .cghidEventTap)
    }

    private func globalPoint(for displayID: UInt8, normalizedX: Double, normalizedY: Double) throws -> CGPoint {
        guard let entry = displayRegistry.entry(for: displayID) else {
            throw VSInputInjectorError.unknownDisplay(displayID)
        }

        let boundedX = min(max(normalizedX, 0), 1)
        let boundedY = min(max(normalizedY, 0), 1)

        let x = entry.bounds.origin.x + (CGFloat(boundedX) * entry.bounds.width)
        let y = entry.bounds.origin.y + (CGFloat(boundedY) * entry.bounds.height)
        return CGPoint(x: x, y: y)
    }

    private func cgMouseButton(from button: Int) -> CGMouseButton {
        switch button {
        case 1:
            return .right
        case 2:
            return .center
        default:
            return .left
        }
    }

    private func mouseDownType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .right:
            return .rightMouseDown
        case .center:
            return .otherMouseDown
        default:
            return .leftMouseDown
        }
    }

    private func mouseUpType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .right:
            return .rightMouseUp
        case .center:
            return .otherMouseUp
        default:
            return .leftMouseUp
        }
    }

    private func cgEventFlags(from modifiers: VSKeyModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private func eventTimestamp() -> CGEventTimestamp {
        CGEventTimestamp(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    }
}
