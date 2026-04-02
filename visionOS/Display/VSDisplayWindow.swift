// VSDisplayWindow.swift
// visionproscreensuptoinfinity
//
// RealityKit-based display surface for rendering decoded video frames.
// Uses DrawableQueue for real-time texture updates on a flat plane entity.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(visionOS)
import SwiftUI
import RealityKit
import CoreVideo
import Metal

/// A visionOS window that displays a streaming Mac virtual display.
///
/// Renders decoded HEVC frames onto a RealityKit flat plane entity
/// using `TextureResource.DrawableQueue` for real-time updates.
/// Each instance represents one virtual Mac display floating in space.
struct VSDisplayWindow: View {
    let displayID: UInt8

    @EnvironmentObject var connectionManager: VSConnectionManager
    @EnvironmentObject var windowManager: VSWindowManager

    @State private var displayEntity: ModelEntity?
    @State private var drawableQueue: TextureResource.DrawableQueue?
    @State private var textureResource: TextureResource?
    @State private var metalDevice: MTLDevice?
    @State private var commandQueue: MTLCommandQueue?

    var body: some View {
        ZStack {
            // RealityKit display surface
            RealityView { content in
                await setupDisplaySurface(content: content)
            }

            // Performance overlay
            if connectionManager.showPerformanceOverlay {
                performanceOverlay
            }

            // Input capture overlay
            inputCaptureOverlay
        }
        .navigationTitle(displayName)
        .onAppear {
            windowManager.markWindowOpened(id: displayID)
            connectionManager.startReceivingFrames(for: displayID) { pixelBuffer in
                renderFrame(pixelBuffer)
            }
        }
        .onDisappear {
            windowManager.markWindowClosed(id: displayID)
            connectionManager.stopReceivingFrames(for: displayID)
        }
    }

    // MARK: - Display Name

    private var displayName: String {
        connectionManager.availableDisplays.first(where: { $0.id == displayID })?.name ?? "Display \(displayID)"
    }

    // MARK: - Display Setup

    @MainActor
    private func setupDisplaySurface(content: RealityViewContent) async {
        // Get Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[VSDisplayWindow] ❌ Failed to create Metal device")
            return
        }
        metalDevice = device
        commandQueue = device.makeCommandQueue()

        // Get display config for dimensions
        let config = connectionManager.availableDisplays.first(where: { $0.id == displayID })?.config ?? .hd1080

        // Create DrawableQueue for real-time texture updates
        let descriptor = TextureResource.DrawableQueue.Descriptor(
            pixelFormat: .bgra8Unorm,
            width: config.width,
            height: config.height,
            usage: [.renderTarget, .shaderRead],
            mipmapsMode: .none
        )

        do {
            let queue = try TextureResource.DrawableQueue(descriptor)
            self.drawableQueue = queue

            // Create texture resource backed by the drawable queue
            let resource = try await TextureResource(dimensions: .dimensions(width: config.width, height: config.height), format: .bgra8Unorm, usage: [.shaderRead])
            resource.replace(withDrawables: queue)
            self.textureResource = resource

            // Create a flat plane entity for the display surface
            // Aspect ratio: width / height, normalized to ~1m height
            let aspectRatio = Float(config.width) / Float(config.height)
            let planeHeight: Float = 0.6  // 60cm in world space
            let planeWidth = planeHeight * aspectRatio

            let mesh = MeshResource.generatePlane(width: planeWidth, height: planeHeight)

            // Create unlit material with the texture
            var material = UnlitMaterial()
            material.color = .init(texture: .init(resource))

            let entity = ModelEntity(mesh: mesh, materials: [material])
            self.displayEntity = entity

            content.add(entity)

            print("[VSDisplayWindow] ✅ Display surface created: \(config.width)×\(config.height)")

        } catch {
            print("[VSDisplayWindow] ❌ Failed to setup display surface: \(error)")
        }
    }

    // MARK: - Frame Rendering

    /// Render a decoded video frame to the display surface.
    private func renderFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let drawableQueue = drawableQueue else {
            return
        }

        do {
            let drawable = try drawableQueue.nextDrawable()

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            // Lock the pixel buffer for reading
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                return
            }

            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let texture = drawable.texture

            // Copy pixel data directly to the drawable texture
            let region = MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: min(width, texture.width), height: min(height, texture.height), depth: 1)
            )

            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow
            )

            // Present the drawable to display the frame
            drawable.present()

        } catch {
            // DrawableQueue may throw if queue is full — this is expected under load
        }
    }

    // MARK: - Performance Overlay

    @ViewBuilder
    private var performanceOverlay: some View {
        if let stats = connectionManager.displayStats[displayID] {
            VStack(alignment: .leading, spacing: 4) {
                Text("FPS: \(String(format: "%.0f", stats.fps))")
                Text("Latency: \(String(format: "%.1f", stats.latencyMs)) ms")
                Text("Bitrate: \(stats.bitrate / 1_000_000) Mbps")
                Text("Dropped: \(stats.droppedFrames)")
            }
            .font(.system(.caption, design: .monospaced))
            .padding(8)
            .background(.black.opacity(0.7))
            .foregroundColor(.green)
            .cornerRadius(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }

    // MARK: - Input Capture

    @ViewBuilder
    private var inputCaptureOverlay: some View {
        // Transparent overlay to capture hover and gesture events.
        // GeometryReader provides the actual view size for coordinate normalization.
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        // Normalize to [0, 1] using actual view dimensions (points)
                        let normalizedX = location.x / geometry.size.width
                        let normalizedY = location.y / geometry.size.height

                        connectionManager.inputForwarder.forwardMouseMove(
                            normalizedX: normalizedX,
                            normalizedY: normalizedY,
                            displayID: displayID
                        )
                    case .ended:
                        break
                    }
                }
                .onTapGesture { location in
                    // Normalize tap position using actual view dimensions
                    let normalizedX = location.x / geometry.size.width
                    let normalizedY = location.y / geometry.size.height

                    connectionManager.inputForwarder.forwardMouseClick(
                        normalizedX: normalizedX,
                        normalizedY: normalizedY,
                        button: 0,
                        pressed: true,
                        displayID: displayID
                    )

                    // Send mouse up after short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        connectionManager.inputForwarder.forwardMouseClick(
                            normalizedX: normalizedX,
                            normalizedY: normalizedY,
                            button: 0,
                            pressed: false,
                            displayID: displayID
                        )
                    }
                }
        }
    }
}
#endif
