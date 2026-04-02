// VSVirtualDisplayManager.swift
// visionproscreensuptoinfinity
//
// Creates and manages virtual displays using the private CGVirtualDisplay API.
// Accessed via NSClassFromString + KVC since the API is undocumented.
// Falls back gracefully if the API is unavailable.
// MIT License - Copyright (c) 2024 Aspirewastaken

#if os(macOS)
import Foundation
import CoreGraphics
import Combine

/// Manages the lifecycle of virtual displays on macOS using the
/// private CGVirtualDisplay API from CoreGraphics.
///
/// This API is undocumented and accessed via runtime introspection.
/// If the API is unavailable (e.g., future macOS removes it), the
/// manager fails gracefully with descriptive error messages.
///
/// Key classes used (private, loaded via NSClassFromString):
/// - `CGVirtualDisplayDescriptor` — configures display properties
/// - `CGVirtualDisplayMode` — defines resolution + refresh rate
/// - `CGVirtualDisplaySettings` — holds modes and HiDPI flag
/// - `CGVirtualDisplay` — the actual virtual display instance
final class VSVirtualDisplayManager: ObservableObject {

    // MARK: - Types

    struct VirtualDisplayEntry {
        let id: UInt8
        let config: VSVideoConfig
        let display: NSObject          // CGVirtualDisplay instance (kept alive via strong ref)
        let systemDisplayID: CGDirectDisplayID
    }

    enum VSVirtualDisplayError: Error, LocalizedError {
        case apiUnavailable(String)
        case creationFailed(String)
        case maxDisplaysReached
        case displayNotFound(UInt8)

        var errorDescription: String? {
            switch self {
            case .apiUnavailable(let cls):
                return "CGVirtualDisplay API unavailable: class '\(cls)' not found. This may require a specific macOS version or entitlement."
            case .creationFailed(let reason):
                return "Failed to create virtual display: \(reason)"
            case .maxDisplaysReached:
                return "Maximum number of virtual displays (\(VSConstants.maxDisplays)) reached."
            case .displayNotFound(let id):
                return "Virtual display with ID \(id) not found."
            }
        }
    }

    // MARK: - Published State

    @Published private(set) var activeDisplays: [UInt8: VirtualDisplayEntry] = [:]
    @Published private(set) var isAPIAvailable: Bool = false

    // MARK: - Private State

    /// Cached class references for the private API.
    private var descriptorClass: NSObject.Type?
    private var modeClass: NSObject.Type?
    private var settingsClass: NSObject.Type?
    private var displayClass: NSObject.Type?

    private let displayQueue = DispatchQueue(label: "com.visionproscreens.virtualdisplay", qos: .userInitiated)

    // MARK: - Initialization

    init() {
        loadPrivateClasses()
    }

    /// Attempt to load private CGVirtualDisplay classes via runtime introspection.
    private func loadPrivateClasses() {
        guard let descriptor = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let mode = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
              let settings = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let display = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
            print("[VSVirtualDisplayManager] ⚠️ CGVirtualDisplay private API not available on this system.")
            print("[VSVirtualDisplayManager] This may require macOS 14+ on Apple Silicon.")
            isAPIAvailable = false
            return
        }

        descriptorClass = descriptor
        modeClass = mode
        settingsClass = settings
        displayClass = display
        isAPIAvailable = true
        print("[VSVirtualDisplayManager] ✅ CGVirtualDisplay API loaded successfully")
    }

    // MARK: - Display Management

    /// Create a new virtual display.
    ///
    /// - Parameters:
    ///   - id: Unique display identifier (1-based, up to maxDisplays).
    ///   - config: Video configuration (resolution, fps).
    /// - Throws: `VSVirtualDisplayError` if creation fails.
    /// - Returns: The system-assigned `CGDirectDisplayID` for the new display.
    @discardableResult
    func createDisplay(id: UInt8, config: VSVideoConfig) throws -> CGDirectDisplayID {
        guard isAPIAvailable else {
            throw VSVirtualDisplayError.apiUnavailable("CGVirtualDisplay classes")
        }

        guard activeDisplays.count < VSConstants.maxDisplays else {
            throw VSVirtualDisplayError.maxDisplaysReached
        }

        guard activeDisplays[id] == nil else {
            // Display already exists with this ID — remove it first
            try removeDisplay(id: id)
        }

        guard let descriptorClass = descriptorClass,
              let modeClass = modeClass,
              let settingsClass = settingsClass,
              let displayClass = displayClass else {
            throw VSVirtualDisplayError.apiUnavailable("cached classes nil")
        }

        // 1. Create descriptor
        let descriptor = descriptorClass.init()

        // Physical size in millimeters (approximate for a ~24" display)
        let physicalWidth = Double(config.width) / 3.78  // ~96 DPI
        let physicalHeight = Double(config.height) / 3.78

        descriptor.setValue(config.width, forKey: "maxPixelsWide")
        descriptor.setValue(config.height, forKey: "maxPixelsHigh")
        descriptor.setValue(CGSize(width: physicalWidth, height: physicalHeight), forKey: "sizeInMillimeters")
        descriptor.setValue("VisionScreen \(id)", forKey: "name")
        descriptor.setValue(UInt32(0x1234), forKey: "vendorID")
        descriptor.setValue(UInt32(0x5678 + UInt32(id)), forKey: "productID")
        descriptor.setValue(UInt32(id), forKey: "serialNum")
        descriptor.setValue(displayQueue, forKey: "dispatchQueue")

        // 2. Create display mode
        let mode = modeClass.init()
        mode.setValue(config.width, forKey: "width")
        mode.setValue(config.height, forKey: "height")
        mode.setValue(Double(config.fps), forKey: "refreshRate")

        // 3. Create settings
        let settings = settingsClass.init()
        settings.setValue([mode], forKey: "modes")
        settings.setValue(false, forKey: "hiDPI")

        // 4. Create virtual display using initWithDescriptor:
        //    We use perform() which returns the initialized object. The private API
        //    pattern is: [[CGVirtualDisplay alloc] initWithDescriptor:desc]
        let initSel = NSSelectorFromString("initWithDescriptor:")
        guard displayClass.instancesRespond(to: initSel) else {
            throw VSVirtualDisplayError.creationFailed("CGVirtualDisplay does not respond to initWithDescriptor:")
        }

        let allocated = displayClass.alloc()
        guard let display = allocated.perform(initSel, with: descriptor)?.takeUnretainedValue() as? NSObject else {
            throw VSVirtualDisplayError.creationFailed("initWithDescriptor: returned nil")
        }

        // 5. Apply settings
        let applySel = NSSelectorFromString("applySettings:")
        if display.responds(to: applySel) {
            display.perform(applySel, with: settings)
        } else {
            print("[VSVirtualDisplayManager] ⚠️ applySettings: not available, display may not configure correctly")
        }

        // 6. Get the system display ID
        var systemDisplayID: CGDirectDisplayID = 0
        if display.responds(to: NSSelectorFromString("displayID")) {
            if let idValue = display.value(forKey: "displayID") {
                // The value may come back as NSNumber
                if let number = idValue as? NSNumber {
                    systemDisplayID = number.uint32Value
                } else if let directID = idValue as? CGDirectDisplayID {
                    systemDisplayID = directID
                }
            }
        }

        // If we couldn't get the displayID, try to find it by looking at active displays
        if systemDisplayID == 0 {
            systemDisplayID = findNewDisplayID()
        }

        let entry = VirtualDisplayEntry(
            id: id,
            config: config,
            display: display,
            systemDisplayID: systemDisplayID
        )

        DispatchQueue.main.async {
            self.activeDisplays[id] = entry
        }

        print("[VSVirtualDisplayManager] ✅ Created virtual display \(id): \(config.width)x\(config.height) @ \(config.fps)fps (system ID: \(systemDisplayID))")

        return systemDisplayID
    }

    /// Remove a virtual display.
    func removeDisplay(id: UInt8) throws {
        guard let entry = activeDisplays[id] else {
            throw VSVirtualDisplayError.displayNotFound(id)
        }

        // Release the display object — deallocation should remove it from the system
        DispatchQueue.main.async {
            self.activeDisplays.removeValue(forKey: id)
        }

        print("[VSVirtualDisplayManager] Removed virtual display \(id) (system ID: \(entry.systemDisplayID))")
    }

    /// Remove all virtual displays.
    func removeAllDisplays() {
        let ids = Array(activeDisplays.keys)
        for id in ids {
            try? removeDisplay(id: id)
        }
    }

    /// Get the system `CGDirectDisplayID` for a managed virtual display.
    func getSystemDisplayID(for id: UInt8) -> CGDirectDisplayID? {
        return activeDisplays[id]?.systemDisplayID
    }

    /// Get display info for all active displays.
    func getDisplayInfoList() -> [VSDisplayInfo] {
        return activeDisplays.values.map { entry in
            VSDisplayInfo(
                id: entry.id,
                name: "VisionScreen \(entry.id)",
                config: entry.config,
                isStreaming: true
            )
        }.sorted { $0.id < $1.id }
    }

    // MARK: - Private Helpers

    /// Try to find a newly added display ID by comparing active display list.
    private func findNewDisplayID() -> CGDirectDisplayID {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        CGGetActiveDisplayList(UInt32(displayIDs.count), &displayIDs, &displayCount)

        let knownIDs = Set(activeDisplays.values.map { $0.systemDisplayID })
        for i in 0..<Int(displayCount) {
            if !knownIDs.contains(displayIDs[i]) && displayIDs[i] != CGMainDisplayID() {
                return displayIDs[i]
            }
        }

        return 0
    }

    deinit {
        removeAllDisplays()
    }
}
#endif
