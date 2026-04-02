import SwiftUI

@main
struct VisionScreenMacApp: App {
    @State private var appModel = MacAppModel()

    var body: some Scene {
        MenuBarExtra("Vision Screens", systemImage: "visionpro") {
            MenuBarView(model: appModel)
                .frame(minWidth: 360, idealWidth: 420)
        }
        .menuBarExtraStyle(.window)
    }
}
