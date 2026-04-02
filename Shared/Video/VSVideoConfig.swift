import Foundation

public struct VSVideoResolutionPreset: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let width: Int
    public let height: Int
    public let label: String

    public init(id: String, width: Int, height: Int, label: String) {
        self.id = id
        self.width = width
        self.height = height
        self.label = label
    }
}

public struct VSBitratePreset: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let bitsPerSecond: Int
    public let label: String

    public init(id: String, bitsPerSecond: Int, label: String) {
        self.id = id
        self.bitsPerSecond = bitsPerSecond
        self.label = label
    }
}

public struct VSVideoConfig: Codable, Hashable, Sendable {
    public let resolution: VSVideoResolutionPreset
    public let bitrate: VSBitratePreset
    public let framesPerSecond: Int
    public let keyframeIntervalSeconds: Int

    public init(
        resolution: VSVideoResolutionPreset,
        bitrate: VSBitratePreset,
        framesPerSecond: Int,
        keyframeIntervalSeconds: Int = 1
    ) {
        self.resolution = resolution
        self.bitrate = bitrate
        self.framesPerSecond = framesPerSecond
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
    }

    public var estimatedBytesPerFrame: Int {
        max(bitrate.bitsPerSecond / 8 / max(framesPerSecond, 1), 1)
    }

    public func payloadBudget(maximumDatagramSize: Int = VSConstants.Network.defaultMaximumDatagramSize) -> Int {
        max(maximumDatagramSize - VSConstants.Frame.headerLength, 512)
    }

    public func estimatedFragmentCount(maximumDatagramSize: Int = VSConstants.Network.defaultMaximumDatagramSize) -> Int {
        let budget = payloadBudget(maximumDatagramSize: maximumDatagramSize)
        return Int(ceil(Double(estimatedBytesPerFrame) / Double(max(budget, 1))))
    }

    public static let resolutionPresets: [VSVideoResolutionPreset] = [
        .init(id: "720p", width: 1_280, height: 720, label: "1280×720"),
        .init(id: "1080p", width: 1_920, height: 1_080, label: "1920×1080"),
        .init(id: "1440p", width: 2_560, height: 1_440, label: "2560×1440")
    ]

    public static let bitratePresets: [VSBitratePreset] = [
        .init(id: "15mbps", bitsPerSecond: 15_000_000, label: "15 Mbps"),
        .init(id: "20mbps", bitsPerSecond: 20_000_000, label: "20 Mbps"),
        .init(id: "30mbps", bitsPerSecond: 30_000_000, label: "30 Mbps")
    ]

    public static let `default` = VSVideoConfig(
        resolution: resolutionPresets[1],
        bitrate: bitratePresets[1],
        framesPerSecond: 60
    )
}
