import Foundation

public actor VSReconnectCoordinator {
    private var attempts: Int = 0

    public init() {}

    public func nextDelay() -> Double {
        defer { attempts += 1 }
        let base = VSConstants.Timing.reconnectBaseDelaySeconds
        let maxDelay = VSConstants.Timing.reconnectMaximumDelaySeconds
        return min(base * pow(2, Double(attempts)), maxDelay)
    }

    public func reset() {
        attempts = 0
    }
}
