import Foundation

public enum VSConstants {
    public static let productName = "visionproscreensuptoinfinity"
    public static let protocolVersion: UInt8 = 1
    public static let maxDisplayCount: Int = 4

    public enum Frame {
        public static let magicNumber: UInt32 = 0x5650_5349 // "VPSI"
        public static let headerLength: Int = 28
        public static let defaultFragmentPayloadSize: Int = 1_024
    }

    public enum Bonjour {
        public static let serviceType = "_visionproscreensuptoinfinity._tcp"
        public static let serviceDomain = "local."
        public static let txtVersionKey = "vs_version"
        public static let txtDisplayCountKey = "vs_display_count"
        public static let txtDeviceRoleKey = "vs_role"
        public static let serverRole = "mac"
    }

    public enum Network {
        public static let controlPort: UInt16 = 45991
        public static let defaultVideoPort: UInt16 = 45992
        public static let defaultMaximumDatagramSize = 1_200
        public static let controlMessagePrefixLength = 4
        public static let maximumControlMessageSize = 1 << 20
        public static let tcpQueueLabel = "com.aspirewastaken.visionproscreensuptoinfinity.tcp"
        public static let udpQueueLabel = "com.aspirewastaken.visionproscreensuptoinfinity.udp"
        public static let bonjourQueueLabel = "com.aspirewastaken.visionproscreensuptoinfinity.bonjour"
    }

    public enum Timing {
        public static let defaultKeyframeIntervalSeconds: Double = 1.0
        public static let performancePingIntervalSeconds: Double = 1.0
        public static let reconnectBaseDelaySeconds: Double = 0.5
        public static let reconnectMaximumDelaySeconds: Double = 8.0
    }

    public enum Window {
        public static let rootSceneID = "main"
        public static let displaySceneIDs = [
            "display-window-1",
            "display-window-2",
            "display-window-3",
            "display-window-4",
        ]
    }
}
