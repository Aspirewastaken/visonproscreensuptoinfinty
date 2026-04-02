import SwiftUI

public struct VSDisplayWindow: View {
    @Environment(VisionAppModel.self) private var appModel
    private let displayID: UInt8

    public init(displayID: UInt8) {
        self.displayID = displayID
    }

    public var body: some View {
        let display = appModel.displayStore.display(for: displayID)
        let frame = appModel.displayStore.frame(for: displayID)
        let snapshot = appModel.statisticsStore.snapshots[displayID]
        let isOverlayVisible = appModel.windowManager.isOverlayVisible(for: displayID)

        VStack(alignment: .leading, spacing: 16) {
            if let display {
                HStack {
                    Text(display.name)
                        .font(.headline)
                    Spacer()
                    Button(isOverlayVisible ? "Hide Overlay" : "Show Overlay") {
                        appModel.toggleOverlay(for: displayID)
                    }
                }

                VSVideoSurfaceView(displayLayer: frame?.displayLayer ?? appModel.windowManager.displayLayer(for: displayID))
                    .frame(minWidth: 640, minHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                if isOverlayVisible {
                    VSPerformanceOverlay(title: display.name, snapshot: snapshot)
                }
            } else {
                ContentUnavailableView("Display Offline", systemImage: "display.slash")
            }
        }
        .padding(24)
        .navigationTitle(display?.name ?? "Display \(displayID)")
    }
}
