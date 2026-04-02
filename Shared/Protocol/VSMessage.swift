import Foundation

public enum VSControlMessage: Codable, Sendable, Equatable {
    case pairRequest(VSPairRequest)
    case pairAccept(VSPairAccept)
    case pairReject(VSPairReject)
    case displayList(VSDisplayListMessage)
    case displayAdded(VSDisplayDescriptor)
    case displayRemoved(VSDisplayRemoveMessage)
    case inputMouseMove(VSMouseMoveMessage)
    case inputMouseButton(VSMouseButtonMessage)
    case inputScroll(VSScrollMessage)
    case inputKey(VSKeyMessage)
    case requestKeyframe(VSRequestKeyframeMessage)
    case performancePing(VSPerformancePingMessage)
    case performancePong(VSPerformancePongMessage)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case VSMessageType.pairRequest.rawValue:
            self = .pairRequest(try container.decode(VSPairRequest.self, forKey: .payload))
        case VSMessageType.pairAccept.rawValue:
            self = .pairAccept(try container.decode(VSPairAccept.self, forKey: .payload))
        case VSMessageType.pairReject.rawValue:
            self = .pairReject(try container.decode(VSPairReject.self, forKey: .payload))
        case VSMessageType.displayList.rawValue:
            self = .displayList(try container.decode(VSDisplayListMessage.self, forKey: .payload))
        case VSMessageType.displayAdded.rawValue:
            self = .displayAdded(try container.decode(VSDisplayDescriptor.self, forKey: .payload))
        case VSMessageType.displayRemoved.rawValue:
            self = .displayRemoved(try container.decode(VSDisplayRemoveMessage.self, forKey: .payload))
        case VSMessageType.inputMouseMove.rawValue:
            self = .inputMouseMove(try container.decode(VSMouseMoveMessage.self, forKey: .payload))
        case VSMessageType.inputMouseButton.rawValue:
            self = .inputMouseButton(try container.decode(VSMouseButtonMessage.self, forKey: .payload))
        case VSMessageType.inputScroll.rawValue:
            self = .inputScroll(try container.decode(VSScrollMessage.self, forKey: .payload))
        case VSMessageType.inputKey.rawValue:
            self = .inputKey(try container.decode(VSKeyMessage.self, forKey: .payload))
        case VSMessageType.requestKeyframe.rawValue:
            self = .requestKeyframe(try container.decode(VSRequestKeyframeMessage.self, forKey: .payload))
        case VSMessageType.performancePing.rawValue:
            self = .performancePing(try container.decode(VSPerformancePingMessage.self, forKey: .payload))
        case VSMessageType.performancePong.rawValue:
            self = .performancePong(try container.decode(VSPerformancePongMessage.self, forKey: .payload))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported control message type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pairRequest(let payload):
            try container.encode(VSMessageType.pairRequest.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .pairAccept(let payload):
            try container.encode(VSMessageType.pairAccept.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .pairReject(let payload):
            try container.encode(VSMessageType.pairReject.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .displayList(let payload):
            try container.encode(VSMessageType.displayList.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .displayAdded(let payload):
            try container.encode(VSMessageType.displayAdded.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .displayRemoved(let payload):
            try container.encode(VSMessageType.displayRemoved.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .inputMouseMove(let payload):
            try container.encode(VSMessageType.inputMouseMove.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .inputMouseButton(let payload):
            try container.encode(VSMessageType.inputMouseButton.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .inputScroll(let payload):
            try container.encode(VSMessageType.inputScroll.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .inputKey(let payload):
            try container.encode(VSMessageType.inputKey.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .requestKeyframe(let payload):
            try container.encode(VSMessageType.requestKeyframe.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .performancePing(let payload):
            try container.encode(VSMessageType.performancePing.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .performancePong(let payload):
            try container.encode(VSMessageType.performancePong.rawValue, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

public typealias VSControlMessageEnvelope = VSControlMessage

public enum VSMessageType: String, Codable, Sendable, CaseIterable {
    case pairRequest = "pair_request"
    case pairAccept = "pair_accept"
    case pairReject = "pair_reject"
    case displayList = "display_list"
    case displayAdded = "display_added"
    case displayRemoved = "display_removed"
    case inputMouseMove = "input_mouse_move"
    case inputMouseButton = "input_mouse_button"
    case inputScroll = "input_scroll"
    case inputKey = "input_key"
    case requestKeyframe = "request_keyframe"
    case performancePing = "performance_ping"
    case performancePong = "performance_pong"
}

public struct VSPairRequest: Codable, Sendable, Equatable {
    public let macName: String
    public let displays: [VSDisplayDescriptor]
    public let protocolVersion: Int
    public let appVersion: String

    public init(macName: String, displays: [VSDisplayDescriptor], protocolVersion: Int, appVersion: String) {
        self.macName = macName
        self.displays = displays
        self.protocolVersion = protocolVersion
        self.appVersion = appVersion
    }
}

public struct VSPairAccept: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let acceptedAt: Date
    public let capabilities: [String]

    public init(sessionID: UUID, acceptedAt: Date = Date(), capabilities: [String] = []) {
        self.sessionID = sessionID
        self.acceptedAt = acceptedAt
        self.capabilities = capabilities
    }
}

public struct VSPairReject: Codable, Sendable, Equatable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

public struct VSDisplayListMessage: Codable, Sendable, Equatable {
    public let displays: [VSDisplayDescriptor]

    public init(displays: [VSDisplayDescriptor]) {
        self.displays = displays
    }
}

public struct VSDisplayRemoveMessage: Codable, Sendable, Equatable {
    public let displayID: UInt8

    public init(displayID: UInt8) {
        self.displayID = displayID
    }
}

public struct VSMouseMoveMessage: Codable, Sendable, Equatable {
    public let displayID: UInt8
    public let x: Double
    public let y: Double
    public let timestamp: TimeInterval

    public init(displayID: UInt8, x: Double, y: Double, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.displayID = displayID
        self.x = x
        self.y = y
        self.timestamp = timestamp
    }
}

public struct VSMouseButtonMessage: Codable, Sendable, Equatable {
    public enum Phase: String, Codable, Sendable {
        case down
        case up
        case click
    }

    public let displayID: UInt8
    public let button: Int
    public let phase: Phase
    public let x: Double
    public let y: Double
    public let timestamp: TimeInterval

    public init(
        displayID: UInt8,
        button: Int,
        phase: Phase,
        x: Double,
        y: Double,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.displayID = displayID
        self.button = button
        self.phase = phase
        self.x = x
        self.y = y
        self.timestamp = timestamp
    }
}

public struct VSScrollMessage: Codable, Sendable, Equatable {
    public let displayID: UInt8
    public let deltaX: Double
    public let deltaY: Double
    public let timestamp: TimeInterval

    public init(
        displayID: UInt8,
        deltaX: Double,
        deltaY: Double,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.displayID = displayID
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.timestamp = timestamp
    }
}

public struct VSKeyMessage: Codable, Sendable, Equatable {
    public let displayID: UInt8
    public let keyCode: UInt16
    public let characters: String?
    public let isKeyDown: Bool
    public let modifiers: VSKeyModifierFlags
    public let timestamp: TimeInterval

    public init(
        displayID: UInt8,
        keyCode: UInt16,
        characters: String? = nil,
        isKeyDown: Bool,
        modifiers: VSKeyModifierFlags = [],
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.displayID = displayID
        self.keyCode = keyCode
        self.characters = characters
        self.isKeyDown = isKeyDown
        self.modifiers = modifiers
        self.timestamp = timestamp
    }
}

public struct VSKeyModifierFlags: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: UInt8

    public static let shift = VSKeyModifierFlags(rawValue: 1 << 0)
    public static let control = VSKeyModifierFlags(rawValue: 1 << 1)
    public static let option = VSKeyModifierFlags(rawValue: 1 << 2)
    public static let command = VSKeyModifierFlags(rawValue: 1 << 3)
    public static let function = VSKeyModifierFlags(rawValue: 1 << 4)

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt8.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct VSRequestKeyframeMessage: Codable, Sendable, Equatable {
    public let displayID: UInt8
    public let reason: String

    public init(displayID: UInt8, reason: String) {
        self.displayID = displayID
        self.reason = reason
    }
}

public struct VSPerformancePingMessage: Codable, Sendable, Equatable {
    public let identifier: UUID
    public let sentAt: TimeInterval

    public init(identifier: UUID = UUID(), sentAt: TimeInterval = Date().timeIntervalSince1970) {
        self.identifier = identifier
        self.sentAt = sentAt
    }
}

public struct VSPerformancePongMessage: Codable, Sendable, Equatable {
    public let identifier: UUID
    public let echoedSentAt: TimeInterval
    public let receivedAt: TimeInterval

    public init(
        identifier: UUID,
        echoedSentAt: TimeInterval,
        receivedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.identifier = identifier
        self.echoedSentAt = echoedSentAt
        self.receivedAt = receivedAt
    }
}
