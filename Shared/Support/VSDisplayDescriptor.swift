import Foundation

public struct VSDisplayDescriptor: Codable, Hashable, Identifiable, Sendable {
    public let id: UInt8
    public var name: String
    public var width: Int
    public var height: Int
    public var refreshRate: Double
    public var isVirtual: Bool

    public init(
        id: UInt8,
        name: String,
        width: Int,
        height: Int,
        refreshRate: Double,
        isVirtual: Bool
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.isVirtual = isVirtual
    }

    public var pixelCount: Int {
        width * height
    }

    public var aspectRatio: Double {
        guard height != 0 else { return 0 }
        return Double(width) / Double(height)
    }
}
