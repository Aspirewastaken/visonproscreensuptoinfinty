// VSWindowManager.swift
// visionproscreensuptoinfinity
//
// Manages the lifecycle and state of display windows in visionOS.
// Tracks which windows are open and persists state across sessions.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(visionOS)
import Foundation
import SwiftUI
import Combine

/// Manages the lifecycle and tracking of display windows in the visionOS app.
///
/// Tracks which display windows are currently open, prevents duplicate opens,
/// and persists window state via UserDefaults for session restoration.
@MainActor
final class VSWindowManager: ObservableObject {

    // MARK: - Published State

    /// Set of currently open display window IDs.
    @Published private(set) var activeWindows: Set<UInt8> = []

    // MARK: - Persistence

    private let windowStateKey = "com.visionproscreens.activeWindows"

    init() {
        loadPersistedState()
    }

    // MARK: - Window Lifecycle

    /// Mark a display window as opened.
    func markWindowOpened(id: UInt8) {
        activeWindows.insert(id)
        persistState()
    }

    /// Mark a display window as closed.
    func markWindowClosed(id: UInt8) {
        activeWindows.remove(id)
        persistState()
    }

    /// Check if a display window is currently open.
    func isWindowOpen(id: UInt8) -> Bool {
        return activeWindows.contains(id)
    }

    /// Open a display window if not already open.
    /// - Parameters:
    ///   - id: Display ID to open.
    ///   - openWindow: The SwiftUI `OpenWindowAction` environment value.
    func openDisplay(id: UInt8, openWindow: OpenWindowAction) {
        guard !isWindowOpen(id: id) else {
            print("[VSWindowManager] Display \(id) is already open")
            return
        }

        openWindow(id: "display", value: id)
        markWindowOpened(id: id)
    }

    /// Close a display window.
    /// - Parameters:
    ///   - id: Display ID to close.
    ///   - dismissWindow: The SwiftUI `DismissWindowAction` environment value.
    func closeDisplay(id: UInt8, dismissWindow: DismissWindowAction) {
        guard isWindowOpen(id: id) else { return }

        dismissWindow(id: "display", value: id)
        markWindowClosed(id: id)
    }

    /// Close all display windows.
    func closeAllDisplays(dismissWindow: DismissWindowAction) {
        for id in activeWindows {
            dismissWindow(id: "display", value: id)
        }
        activeWindows.removeAll()
        persistState()
    }

    /// Get the list of window IDs that were open in the previous session.
    /// Useful for restoring windows on app launch.
    func getPersistedWindowIDs() -> Set<UInt8> {
        guard let data = UserDefaults.standard.data(forKey: windowStateKey),
              let ids = try? JSONDecoder().decode(Set<UInt8>.self, from: data) else {
            return []
        }
        return ids
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        // Don't auto-open windows — just load the set for reference
        // The app will decide whether to restore windows based on connection state
    }

    private func persistState() {
        if let data = try? JSONEncoder().encode(activeWindows) {
            UserDefaults.standard.set(data, forKey: windowStateKey)
        }
    }
}
#endif
