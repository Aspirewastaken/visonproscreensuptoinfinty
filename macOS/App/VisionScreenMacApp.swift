// VisionScreenMacApp.swift
// visionproscreensuptoinfinity
//
// macOS menu bar companion app entry point.
// Runs as a menu bar app (no dock icon) using SwiftUI MenuBarExtra.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(macOS)
import SwiftUI

/// macOS companion app entry point.
///
/// This is a menu bar-only app (LSUIElement = true). It manages virtual
/// displays and streams them to connected Vision Pro clients.
@main
struct VisionScreenMacApp: App {
    @StateObject private var server = VSMacServer()

    var body: some Scene {
        // Menu bar extra — the primary (and only) UI for the Mac app
        MenuBarExtra {
            MenuBarView(server: server)
        } label: {
            Label("VS∞", systemImage: server.connectedClients > 0 ? "display.2" : "display")
        }
    }
}
#endif
