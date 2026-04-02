import Shared
import SwiftUI

@main
struct VisionProScreensApp: App {
    @State private var model = VisionAppModel()

    var body: some Scene {
        WindowGroup(id: VSConstants.Window.rootSceneID) {
            ContentView()
                .environment(model)
        }

        WindowGroup(id: VSConstants.Window.displaySceneIDs[0]) {
            VSDisplayWindow(displayID: 1)
                .environment(model)
        }

        WindowGroup(id: VSConstants.Window.displaySceneIDs[1]) {
            VSDisplayWindow(displayID: 2)
                .environment(model)
        }

        WindowGroup(id: VSConstants.Window.displaySceneIDs[2]) {
            VSDisplayWindow(displayID: 3)
                .environment(model)
        }

        WindowGroup(id: VSConstants.Window.displaySceneIDs[3]) {
            VSDisplayWindow(displayID: 4)
                .environment(model)
        }
    }
}
