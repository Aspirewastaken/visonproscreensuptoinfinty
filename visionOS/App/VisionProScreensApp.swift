// VisionProScreensApp.swift
// visionproscreensuptoinfinity
//
// visionOS app entry point. Manages window groups for the main
// discovery UI and dynamically opened display windows.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(visionOS)
import SwiftUI

/// visionOS app entry point.
///
/// Defines two window groups:
/// 1. Main window — Discovery, pairing, and connection management UI
/// 2. Display windows — Opened dynamically for each streaming display,
///    identified by display ID (UInt8)
@main
struct VisionProScreensApp: App {

    @StateObject private var connectionManager = VSConnectionManager()
    @StateObject private var windowManager = VSWindowManager()

    var body: some Scene {
        // Main window — discovery and connection UI
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(windowManager)
        }

        // Display windows — one per streaming virtual display
        // Opened programmatically via openWindow(id: "display", value: displayID)
        WindowGroup(id: "display", for: UInt8.self) { $displayID in
            if let displayID = displayID {
                VSDisplayWindow(displayID: displayID)
                    .environmentObject(connectionManager)
                    .environmentObject(windowManager)
            } else {
                Text("Invalid display ID")
                    .font(.title)
                    .foregroundColor(.secondary)
            }
        }
        .defaultSize(width: 1920, height: 1080, depth: 0, in: .points)
    }
}
#endif
