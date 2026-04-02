import Foundation
import Shared

@MainActor
public final class VSVisionReconnectCoordinator {
    public private(set) var attempts: Int = 0

    public init() {}

    public func nextDelay() -> Double {
        attempts += 1
        let base = VSConstants.Timing.reconnectBaseDelaySeconds
        let delay = base * pow(2, Double(max(0, attempts - 1)))
        return min(delay, VSConstants.Timing.reconnectMaximumDelaySeconds)
    }

    public func reset() {
        attempts = 0
    }
}
