import Foundation
import Observation
import Shared

@MainActor
@Observable
public final class VSDisplayInteractionModel {
    public var focusedDisplayID: UInt8?
    public var currentModifierFlags: VSKeyModifierFlags = []

    public init(focusedDisplayID: UInt8? = nil) {
        self.focusedDisplayID = focusedDisplayID
    }

    public func focus(displayID: UInt8?) {
        focusedDisplayID = displayID
    }
}
