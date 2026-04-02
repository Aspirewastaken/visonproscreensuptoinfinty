import Shared
import SwiftUI

public struct VSPerformanceOverlay: View {
    public let title: String
    public let snapshot: VSStreamStatistics?

    public init(title: String, snapshot: VSStreamStatistics?) {
        self.title = title
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())

            if let snapshot {
                Text("FPS \(snapshot.fps, specifier: "%.1f")")
                Text("Bitrate \(snapshot.bitrateMbps, specifier: "%.1f") Mbps")
                Text("Latency \(snapshot.roundTripLatencyMs, specifier: "%.1f") ms")
                Text("Drops \(snapshot.droppedFrames)")
            } else {
                Text("Waiting for metrics…")
            }
        }
        .font(.caption2.monospacedDigit())
        .padding(10)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.white)
    }
}
