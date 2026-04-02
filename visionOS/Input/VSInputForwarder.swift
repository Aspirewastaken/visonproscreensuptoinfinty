import CoreGraphics
import Foundation
import Shared

@MainActor
public final class VSInputForwarder {
    private unowned let appModel: VisionAppModel

    public init(appModel: VisionAppModel) {
        self.appModel = appModel
    }

    public func sendPointerMove(displayID: UInt8, normalizedPoint: CGPoint) {
        appModel.send(.inputMouseMove(.init(
            displayID: displayID,
            x: normalizedPoint.x,
            y: normalizedPoint.y
        )))
    }

    public func sendClick(displayID: UInt8, normalizedPoint: CGPoint, button: Int = 0) {
        appModel.send(.inputMouseButton(.init(
            displayID: displayID,
            button: button,
            phase: .click,
            x: normalizedPoint.x,
            y: normalizedPoint.y
        )))
    }

    public func sendScroll(displayID: UInt8, deltaX: Double, deltaY: Double) {
        appModel.send(.inputScroll(.init(
            displayID: displayID,
            deltaX: deltaX,
            deltaY: deltaY
        )))
    }

    public func sendKey(
        displayID: UInt8,
        keyCode: UInt16,
        characters: String? = nil,
        isKeyDown: Bool,
        modifiers: VSKeyModifierFlags = []
    ) {
        appModel.send(.inputKey(.init(
            displayID: displayID,
            keyCode: keyCode,
            characters: characters,
            isKeyDown: isKeyDown,
            modifiers: modifiers
        )))
    }
}
