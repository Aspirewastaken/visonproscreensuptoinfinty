import Foundation
import AVFoundation
import Observation
import Shared

@MainActor
@Observable
public final class VSWindowManager {
    public private(set) var activeDisplayIDs: [UInt8] = []
    public private(set) var windowSceneByDisplayID: [UInt8: String] = [:]
    public private(set) var overlayDisplayIDs: Set<UInt8> = []
    private var displayLayers: [UInt8: AVSampleBufferDisplayLayer] = [:]
    public var focusedDisplayID: UInt8?

    public init() {}

    public func sceneID(for displayID: UInt8) -> String {
        if let existing = windowSceneByDisplayID[displayID] {
            return existing
        }

        let availableScenes = VSConstants.Window.displaySceneIDs.filter { candidate in
            !windowSceneByDisplayID.values.contains(candidate)
        }

        let assignedScene = availableScenes.first ?? VSConstants.Window.displaySceneIDs.first ?? VSConstants.Window.rootSceneID
        windowSceneByDisplayID[displayID] = assignedScene
        if !activeDisplayIDs.contains(displayID) {
            activeDisplayIDs.append(displayID)
            activeDisplayIDs.sort()
        }
        return assignedScene
    }

    public func toggleOverlay(for displayID: UInt8) {
        if overlayDisplayIDs.contains(displayID) {
            overlayDisplayIDs.remove(displayID)
        } else {
            overlayDisplayIDs.insert(displayID)
        }
    }

    public func isOverlayVisible(for displayID: UInt8) -> Bool {
        overlayDisplayIDs.contains(displayID)
    }

    public func displayLayer(for displayID: UInt8) -> AVSampleBufferDisplayLayer {
        if let existing = displayLayers[displayID] {
            return existing
        }

        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        displayLayers[displayID] = layer
        return layer
    }

    public func releaseWindow(for displayID: UInt8) {
        activeDisplayIDs.removeAll { $0 == displayID }
        windowSceneByDisplayID.removeValue(forKey: displayID)
        overlayDisplayIDs.remove(displayID)
        displayLayers.removeValue(forKey: displayID)
        if focusedDisplayID == displayID {
            focusedDisplayID = nil
        }
    }

    public func reset() {
        activeDisplayIDs.removeAll()
        windowSceneByDisplayID.removeAll()
        overlayDisplayIDs.removeAll()
        displayLayers.removeAll()
        focusedDisplayID = nil
    }
}
