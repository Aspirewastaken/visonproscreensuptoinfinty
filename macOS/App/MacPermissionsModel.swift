import ApplicationServices
import Foundation
import Observation

@MainActor
@Observable
public final class MacPermissionsModel {
    public struct Status: Equatable, Sendable {
        public var screenRecordingGranted: Bool
        public var accessibilityGranted: Bool
        public var localNetworkReady: Bool

        public var allRequiredGranted: Bool {
            screenRecordingGranted && accessibilityGranted && localNetworkReady
        }

        public init(
            screenRecordingGranted: Bool,
            accessibilityGranted: Bool,
            localNetworkReady: Bool
        ) {
            self.screenRecordingGranted = screenRecordingGranted
            self.accessibilityGranted = accessibilityGranted
            self.localNetworkReady = localNetworkReady
        }
    }

    public private(set) var status: Status

    public init(
        status: Status = .init(
            screenRecordingGranted: false,
            accessibilityGranted: false,
            localNetworkReady: true
        )
    ) {
        self.status = status
        refresh()
    }

    public var screenRecordingGranted: Bool { status.screenRecordingGranted }
    public var accessibilityGranted: Bool { status.accessibilityGranted }
    public var localNetworkReady: Bool { status.localNetworkReady }

    public func refresh() {
        status = Status(
            screenRecordingGranted: queryScreenRecordingPermission(),
            accessibilityGranted: queryAccessibilityPermission(),
            localNetworkReady: queryLocalNetworkReadiness()
        )
    }

    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    private func queryScreenRecordingPermission() -> Bool {
        if #available(macOS 14.0, *) {
            return CGPreflightScreenCaptureAccess()
        } else {
            return false
        }
    }

    private func queryAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    private func queryLocalNetworkReadiness() -> Bool {
        true
    }
}
