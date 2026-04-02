import Foundation
import Observation
import Shared

@MainActor
@Observable
public final class MacSettingsStore {
    public enum DisplayBackendPreference: String, Codable, CaseIterable, Identifiable, Sendable {
        case virtualExperimental
        case physicalFallback

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .virtualExperimental:
                "Virtual Displays (Experimental)"
            case .physicalFallback:
                "Physical Displays (Fallback)"
            }
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    public var desiredDisplayCount: Int {
        didSet {
            desiredDisplayCount = min(max(desiredDisplayCount, 1), VSConstants.maxDisplayCount)
            defaults.set(desiredDisplayCount, forKey: Keys.desiredDisplayCount)
        }
    }

    public var selectedVideoConfig: VSVideoConfig {
        didSet {
            saveVideoConfig()
        }
    }

    public var backendPreference: DisplayBackendPreference {
        didSet {
            defaults.set(backendPreference.rawValue, forKey: Keys.backendPreference)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedCount = defaults.object(forKey: Keys.desiredDisplayCount) as? Int ?? 1
        desiredDisplayCount = min(max(storedCount, 1), VSConstants.maxDisplayCount)

        if
            let rawValue = defaults.string(forKey: Keys.backendPreference),
            let preference = DisplayBackendPreference(rawValue: rawValue)
        {
            backendPreference = preference
        } else {
            backendPreference = .virtualExperimental
        }

        if
            let data = defaults.data(forKey: Keys.videoConfig),
            let config = try? JSONDecoder().decode(VSVideoConfig.self, from: data)
        {
            selectedVideoConfig = config
        } else {
            selectedVideoConfig = .default
        }
    }

    public var selectedResolutionLabel: String {
        selectedVideoConfig.resolution.label
    }

    public var selectedBitrateLabel: String {
        selectedVideoConfig.bitrate.label
    }

    public func updateResolution(_ preset: VSVideoResolutionPreset) {
        selectedVideoConfig = VSVideoConfig(
            resolution: preset,
            bitrate: selectedVideoConfig.bitrate,
            framesPerSecond: selectedVideoConfig.framesPerSecond,
            keyframeIntervalSeconds: selectedVideoConfig.keyframeIntervalSeconds
        )
    }

    public func updateBitrate(_ preset: VSBitratePreset) {
        selectedVideoConfig = VSVideoConfig(
            resolution: selectedVideoConfig.resolution,
            bitrate: preset,
            framesPerSecond: selectedVideoConfig.framesPerSecond,
            keyframeIntervalSeconds: selectedVideoConfig.keyframeIntervalSeconds
        )
    }

    public func updateFramesPerSecond(_ value: Int) {
        selectedVideoConfig = VSVideoConfig(
            resolution: selectedVideoConfig.resolution,
            bitrate: selectedVideoConfig.bitrate,
            framesPerSecond: max(value, 1),
            keyframeIntervalSeconds: selectedVideoConfig.keyframeIntervalSeconds
        )
    }

    public func updateBackendPreference(_ preference: DisplayBackendPreference) {
        backendPreference = preference
    }

    private func saveVideoConfig() {
        if let data = try? JSONEncoder().encode(selectedVideoConfig) {
            defaults.set(data, forKey: Keys.videoConfig)
        }
    }
}

private enum Keys {
    static let desiredDisplayCount = "mac.settings.desiredDisplayCount"
    static let backendPreference = "mac.settings.backendPreference"
    static let videoConfig = "mac.settings.videoConfig"
}
