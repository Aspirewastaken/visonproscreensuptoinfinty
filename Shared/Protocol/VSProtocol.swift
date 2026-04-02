import Foundation

public enum VSProtocolError: Error, Equatable {
    case unsupportedVersion(UInt8)
    case invalidDisplayID(UInt8)
    case controlMessageTooLarge(Int)
    case incompleteFrame
    case invalidFrameLength(Int)
}

public enum VSProtocol {
    public static func validate(version: UInt8) throws {
        guard version == VSConstants.protocolVersion else {
            throw VSProtocolError.unsupportedVersion(version)
        }
    }

    public static func validate(displayID: UInt8) throws {
        guard displayID >= 1 && Int(displayID) <= VSConstants.maxDisplayCount else {
            throw VSProtocolError.invalidDisplayID(displayID)
        }
    }

    public static func encodeControlMessage(_ message: VSControlMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let payload = try encoder.encode(message)

        guard payload.count <= VSConstants.Network.maximumControlMessageSize else {
            throw VSProtocolError.controlMessageTooLarge(payload.count)
        }

        var lengthPrefix = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &lengthPrefix, count: MemoryLayout<UInt32>.size)
        framed.append(payload)
        return framed
    }

    public static func decodeControlMessage(_ payload: Data) throws -> VSControlMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(VSControlMessage.self, from: payload)
    }

    public static func decodeFrame(from framedPayload: Data) throws -> (message: VSControlMessage, consumed: Int) {
        let prefixLength = VSConstants.Network.controlMessagePrefixLength
        guard framedPayload.count >= prefixLength else {
            throw VSProtocolError.incompleteFrame
        }

        let expectedLength = framedPayload.prefix(prefixLength).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        guard expectedLength > 0 else {
            throw VSProtocolError.invalidFrameLength(Int(expectedLength))
        }

        let totalLength = prefixLength + Int(expectedLength)
        guard framedPayload.count >= totalLength else {
            throw VSProtocolError.incompleteFrame
        }

        let payload = framedPayload.subdata(in: prefixLength ..< totalLength)
        let message = try decodeControlMessage(payload)
        return (message, totalLength)
    }
}
