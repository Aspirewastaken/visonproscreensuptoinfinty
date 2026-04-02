import Foundation

public enum VSFramePacketError: Error, Equatable, Sendable {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case headerTooShort
    case payloadTooLarge
    case inconsistentFragmentation
}

public struct VSFramePacketFlags: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: UInt8

    public static let keyframe = VSFramePacketFlags(rawValue: 1 << 0)
    public static let endOfFrame = VSFramePacketFlags(rawValue: 1 << 1)

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

public struct VSFramePacketHeader: Equatable, Codable, Sendable {
    public static let encodedLength = 4 + 1 + 1 + 1 + 1 + 4 + 4 + 2 + 2 + 8

    public var magic: UInt32
    public var version: UInt8
    public var displayID: UInt8
    public var flags: VSFramePacketFlags
    public var reserved: UInt8
    public var sequenceNumber: UInt32
    public var frameNumber: UInt32
    public var fragmentIndex: UInt16
    public var fragmentCount: UInt16
    public var presentationTimestampMicros: UInt64

    public init(
        magic: UInt32 = VSConstants.Frame.magicNumber,
        version: UInt8 = VSConstants.protocolVersion,
        displayID: UInt8,
        flags: VSFramePacketFlags,
        reserved: UInt8 = 0,
        sequenceNumber: UInt32,
        frameNumber: UInt32,
        fragmentIndex: UInt16,
        fragmentCount: UInt16,
        presentationTimestampMicros: UInt64
    ) {
        self.magic = magic
        self.version = version
        self.displayID = displayID
        self.flags = flags
        self.reserved = reserved
        self.sequenceNumber = sequenceNumber
        self.frameNumber = frameNumber
        self.fragmentIndex = fragmentIndex
        self.fragmentCount = fragmentCount
        self.presentationTimestampMicros = presentationTimestampMicros
    }
}

public struct VSFramePacket: Equatable, Codable, Sendable {
    public var header: VSFramePacketHeader
    public var payload: Data

    public init(header: VSFramePacketHeader, payload: Data) {
        self.header = header
        self.payload = payload
    }

    public init(
        displayID: UInt8,
        flags: VSFramePacketFlags,
        sequenceNumber: UInt32,
        frameNumber: UInt32,
        fragmentIndex: UInt16,
        fragmentCount: UInt16,
        presentationTimestampMicros: UInt64,
        payload: Data
    ) {
        self.header = VSFramePacketHeader(
            displayID: displayID,
            flags: flags,
            sequenceNumber: sequenceNumber,
            frameNumber: frameNumber,
            fragmentIndex: fragmentIndex,
            fragmentCount: fragmentCount,
            presentationTimestampMicros: presentationTimestampMicros
        )
        self.payload = payload
    }

    public func encode() throws -> Data {
        var data = Data()
        data.append(contentsOf: header.magic.bigEndianBytes)
        data.append(header.version)
        data.append(header.displayID)
        data.append(header.flags.rawValue)
        data.append(header.reserved)
        data.append(contentsOf: header.sequenceNumber.bigEndianBytes)
        data.append(contentsOf: header.frameNumber.bigEndianBytes)
        data.append(contentsOf: header.fragmentIndex.bigEndianBytes)
        data.append(contentsOf: header.fragmentCount.bigEndianBytes)
        data.append(contentsOf: header.presentationTimestampMicros.bigEndianBytes)
        data.append(payload)
        return data
    }

    public static func decode(from data: Data) throws -> VSFramePacket {
        try decode(data)
    }

    public static func decode(_ data: Data) throws -> VSFramePacket {
        guard data.count >= VSFramePacketHeader.encodedLength else {
            throw VSFramePacketError.headerTooShort
        }

        let magic = try data.uint32(at: 0)
        guard magic == VSConstants.Frame.magicNumber else {
            throw VSFramePacketError.invalidMagic
        }

        let version = data[4]
        guard version == VSConstants.protocolVersion else {
            throw VSFramePacketError.unsupportedVersion(version)
        }

        let header = VSFramePacketHeader(
            magic: magic,
            version: version,
            displayID: data[5],
            flags: VSFramePacketFlags(rawValue: data[6]),
            reserved: data[7],
            sequenceNumber: try data.uint32(at: 8),
            frameNumber: try data.uint32(at: 12),
            fragmentIndex: try data.uint16(at: 16),
            fragmentCount: try data.uint16(at: 18),
            presentationTimestampMicros: try data.uint64(at: 20)
        )

        guard header.fragmentCount > 0, header.fragmentIndex < header.fragmentCount else {
            throw VSFramePacketError.inconsistentFragmentation
        }

        let payload = data.subdata(in: VSFramePacketHeader.encodedLength ..< data.count)
        return VSFramePacket(header: header, payload: payload)
    }

    public static func fragment(
        accessUnit: Data,
        displayID: UInt8,
        sequenceNumber: UInt32,
        frameNumber: UInt32,
        presentationTimestampMicros: UInt64,
        isKeyframe: Bool,
        config: VSVideoConfig
    ) throws -> [VSFramePacket] {
        try VSFramePacketizer().fragment(
            displayID: displayID,
            frameNumber: frameNumber,
            initialSequenceNumber: sequenceNumber,
            timestampMicros: presentationTimestampMicros,
            payload: accessUnit,
            isKeyframe: isKeyframe,
            maxPayloadSize: config.payloadBudget()
        )
    }
}

public struct VSReassembledFrame: Equatable, Sendable {
    public var displayID: UInt8
    public var frameNumber: UInt32
    public var sequenceNumber: UInt32
    public var flags: VSFramePacketFlags
    public var presentationTimestampMicros: UInt64
    public var payload: Data

    public init(
        displayID: UInt8,
        frameNumber: UInt32,
        sequenceNumber: UInt32,
        flags: VSFramePacketFlags,
        presentationTimestampMicros: UInt64,
        payload: Data
    ) {
        self.displayID = displayID
        self.frameNumber = frameNumber
        self.sequenceNumber = sequenceNumber
        self.flags = flags
        self.presentationTimestampMicros = presentationTimestampMicros
        self.payload = payload
    }
}

public struct VSFramePacketizer: Sendable {
    public init() {}

    public func fragment(
        displayID: UInt8,
        frameNumber: UInt32,
        initialSequenceNumber: UInt32,
        timestampMicros: UInt64,
        payload: Data,
        isKeyframe: Bool,
        maxPayloadSize: Int = VSConstants.Frame.defaultFragmentPayloadSize
    ) throws -> [VSFramePacket] {
        guard maxPayloadSize > 0 else {
            throw VSFramePacketError.payloadTooLarge
        }

        let ranges = payload.fragmentRanges(maxSize: maxPayloadSize)
        guard ranges.count <= Int(UInt16.max) else {
            throw VSFramePacketError.payloadTooLarge
        }

        let fragmentCount = UInt16(ranges.count)

        return ranges.enumerated().map { index, range in
            var flags: VSFramePacketFlags = []
            if isKeyframe {
                flags.insert(.keyframe)
            }
            if index == ranges.count - 1 {
                flags.insert(.endOfFrame)
            }

            return VSFramePacket(
                header: VSFramePacketHeader(
                    displayID: displayID,
                    flags: flags,
                    sequenceNumber: initialSequenceNumber &+ UInt32(index),
                    frameNumber: frameNumber,
                    fragmentIndex: UInt16(index),
                    fragmentCount: fragmentCount,
                    presentationTimestampMicros: timestampMicros
                ),
                payload: payload.subdata(in: range)
            )
        }
    }
}

public struct VSFrameReassembler: Sendable {
    public var displayID: UInt8?
    public private(set) var state: State

    public init(displayID: UInt8? = nil, state: State = State()) {
        self.displayID = displayID
        self.state = state
    }

    @discardableResult
    public mutating func ingest(packet: VSFramePacket) throws -> VSReassembledFrame? {
        if let displayID, packet.header.displayID != displayID {
            throw VSFramePacketError.inconsistentFragmentation
        }
        return state.insert(packet)
    }

    public var discardedFrameCount: Int {
        state.droppedFrameCount
    }

    public struct State: Sendable {
        public private(set) var assemblies: [UInt8: PartialFrameAssembly] = [:]
        public private(set) var droppedFrameCount: Int = 0

        public init() {}

        @discardableResult
        public mutating func insert(_ packet: VSFramePacket) -> VSReassembledFrame? {
            let displayID = packet.header.displayID
            let incomingFrameNumber = packet.header.frameNumber

            if let existing = assemblies[displayID], incomingFrameNumber > existing.frameNumber {
                droppedFrameCount += 1
                assemblies[displayID] = nil
            }

            if assemblies[displayID] == nil {
                assemblies[displayID] = PartialFrameAssembly(
                    displayID: displayID,
                    frameNumber: incomingFrameNumber,
                    expectedFragments: Int(packet.header.fragmentCount),
                    sequenceNumber: packet.header.sequenceNumber,
                    flags: packet.header.flags,
                    presentationTimestampMicros: packet.header.presentationTimestampMicros
                )
            }

            guard var assembly = assemblies[displayID], assembly.frameNumber == incomingFrameNumber else {
                return nil
            }

            assembly.flags.formUnion(packet.header.flags)
            assembly.insert(packet.payload, at: Int(packet.header.fragmentIndex))

            if assembly.isComplete {
                assemblies[displayID] = nil
                return VSReassembledFrame(
                    displayID: displayID,
                    frameNumber: assembly.frameNumber,
                    sequenceNumber: assembly.sequenceNumber,
                    flags: assembly.flags,
                    presentationTimestampMicros: assembly.presentationTimestampMicros,
                    payload: assembly.joinedPayload()
                )
            }

            assemblies[displayID] = assembly
            return nil
        }
    }

    public struct PartialFrameAssembly: Sendable {
        public var displayID: UInt8
        public var frameNumber: UInt32
        public var expectedFragments: Int
        public var sequenceNumber: UInt32
        public var flags: VSFramePacketFlags
        public var presentationTimestampMicros: UInt64
        private var fragments: [Int: Data]

        public init(
            displayID: UInt8,
            frameNumber: UInt32,
            expectedFragments: Int,
            sequenceNumber: UInt32,
            flags: VSFramePacketFlags,
            presentationTimestampMicros: UInt64
        ) {
            self.displayID = displayID
            self.frameNumber = frameNumber
            self.expectedFragments = expectedFragments
            self.sequenceNumber = sequenceNumber
            self.flags = flags
            self.presentationTimestampMicros = presentationTimestampMicros
            self.fragments = [:]
        }

        public var isComplete: Bool {
            fragments.count == expectedFragments
        }

        public mutating func insert(_ payload: Data, at index: Int) {
            fragments[index] = payload
        }

        public func joinedPayload() -> Data {
            var combined = Data()
            for index in 0 ..< expectedFragments {
                if let fragment = fragments[index] {
                    combined.append(fragment)
                }
            }
            return combined
        }
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian, Array.init)
    }
}

private extension Data {
    func uint16(at offset: Int) throws -> UInt16 {
        guard count >= offset + 2 else { throw VSFramePacketError.headerTooShort }
        return subdata(in: offset ..< offset + 2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard count >= offset + 4 else { throw VSFramePacketError.headerTooShort }
        return subdata(in: offset ..< offset + 4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    func uint64(at offset: Int) throws -> UInt64 {
        guard count >= offset + 8 else { throw VSFramePacketError.headerTooShort }
        return subdata(in: offset ..< offset + 8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }

    func fragmentRanges(maxSize: Int) -> [Range<Int>] {
        guard !isEmpty else {
            return [0 ..< 0]
        }

        var ranges: [Range<Int>] = []
        var offset = 0

        while offset < count {
            let upperBound = Swift.min(offset + maxSize, count)
            ranges.append(offset ..< upperBound)
            offset = upperBound
        }

        return ranges
    }
}
