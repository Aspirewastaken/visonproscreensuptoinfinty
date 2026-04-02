import Foundation
import Observation
import Shared

@MainActor
@Observable
public final class MacAppModel {
    public private(set) var displays: [VSDisplayDescriptor] = []
    public private(set) var connectionStateDescription = "Server stopped"
    public private(set) var isServerRunning = false
    public private(set) var connectedHostDescription = "Not connected"
    public private(set) var serverErrorMessage: String?

    public let permissions = MacPermissionsModel()
    public let settings = MacSettingsStore()
    public let statistics = VSStatisticsStore()
    public let displayRegistry = VSDisplayRegistry()

    private let physicalDisplaySource = VSPhysicalDisplaySource()
    private lazy var virtualDisplayManager = VSVirtualDisplayManager(registry: displayRegistry)
    private lazy var capture = VSScreenCapture(registry: displayRegistry)
    private lazy var encoderPool = VSEncoderPool { [weak self] in
        self?.settings.selectedVideoConfig ?? .default
    }
    private lazy var inputInjector = VSInputInjector(displayRegistry: displayRegistry)
    private lazy var server = VSMacServer(inputInjector: inputInjector)
    private var selectedSourceProvider: any VSDisplaySourceProvider

    public init() {
        selectedSourceProvider = physicalDisplaySource

        if settings.backendPreference == .virtualExperimental {
            selectedSourceProvider = virtualDisplayManager
        }

        configureCallbacks()
        refreshPermissions()
    }

    public var canAddDisplay: Bool {
        displays.count < VSConstants.maxDisplayCount && selectedSourceProvider.backend == .virtual
    }

    public var canRemoveDisplay: Bool {
        !displays.isEmpty && selectedSourceProvider.backend == .virtual
    }

    public func start() async {
        await refreshDisplays()
        startCapturePipelineIfPossible()
    }

    public func refreshPermissions() {
        permissions.refresh()
    }

    public func refreshDisplays() async {
        await selectedSourceProvider.refresh()
        applySnapshot(selectedSourceProvider.snapshot)
    }

    public func toggleServer() {
        if isServerRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    public func startServer() {
        do {
            try server.start(
                displaysProvider: { [weak self] in self?.displays ?? [] },
                performanceHandler: { [weak self] snapshot in
                    guard let self else { return }
                    self.statistics.update(
                        VSStreamStatistics(
                            displayID: snapshot.displayID,
                            fps: snapshot.fps,
                            bitrateMbps: snapshot.bitrateMbps,
                            droppedFrames: Int(snapshot.droppedFrames),
                            roundTripLatencyMs: snapshot.roundTripLatencyMs
                        )
                    )
                }
            )
            isServerRunning = true
            connectionStateDescription = "Advertising over Bonjour"
            serverErrorMessage = nil

            for descriptor in displays {
                try? server.updateDisplay(descriptor)
            }
        } catch {
            connectionStateDescription = "Server failed"
            serverErrorMessage = error.localizedDescription
        }
    }

    public func stopServer() {
        server.stop()
        isServerRunning = false
        connectionStateDescription = "Server stopped"
        connectedHostDescription = "Not connected"
    }

    public func addDisplay() async {
        do {
            _ = try await selectedSourceProvider.createDisplay(config: settings.selectedVideoConfig)
            await refreshDisplays()
            startCapturePipelineIfPossible()
        } catch {
            serverErrorMessage = error.localizedDescription
        }
    }

    public func removeLastDisplay() async {
        guard let descriptor = displays.last else { return }
        await removeDisplay(descriptor)
    }

    public func removeDisplay(_ descriptor: VSDisplayDescriptor) async {
        do {
            try await selectedSourceProvider.removeDisplay(id: descriptor.id)
            statistics.remove(displayID: descriptor.id)
            await refreshDisplays()
        } catch {
            serverErrorMessage = error.localizedDescription
        }
    }

    public func applyCurrentSettings() async {
        selectedSourceProvider = settings.backendPreference == .virtualExperimental
            ? virtualDisplayManager
            : physicalDisplaySource

        await refreshDisplays()
        startCapturePipelineIfPossible()
    }

    private func startCapturePipelineIfPossible() {
        guard permissions.status.screenRecordingGranted else { return }

        encoderPool.configure(displays: displays)

        capture.onFrame = { [weak self] capturedFrame in
            Task { @MainActor in
                guard let self else { return }
                self.encoderPool.encode(capturedFrame)
            }
        }

        Task {
            for descriptor in displays {
                try? await capture.startCapture(for: descriptor, config: settings.selectedVideoConfig)
            }
        }
    }

    private func applySnapshot(_ snapshot: VSDisplaySourceSnapshot) {
        displays = snapshot.descriptors.sorted { $0.id < $1.id }
        displayRegistry.apply(displays: snapshot.displays)

        for descriptor in displays {
            try? server.updateDisplay(descriptor)
        }
    }

    private func configureCallbacks() {
        physicalDisplaySource.onSnapshotChanged = { [weak self] snapshot in
            guard let self, self.selectedSourceProvider.backend == .physicalFallback else { return }
            Task { @MainActor in
                self.applySnapshot(snapshot)
            }
        }

        virtualDisplayManager.onSnapshotChanged = { [weak self] snapshot in
            guard let self, self.selectedSourceProvider.backend == .virtual else { return }
            Task { @MainActor in
                self.applySnapshot(snapshot)
            }
        }

        encoderPool.onFrameEncoded = { [weak self] frame in
            guard let self else { return }
            self.server.send(frame: frame, using: self.settings.selectedVideoConfig)
        }

        server.onConnectionStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.connectionStateDescription = String(describing: state)
            }
        }

        server.onClientDescriptionChanged = { [weak self] description in
            Task { @MainActor in
                self?.connectedHostDescription = description
            }
        }

        server.onStatisticsUpdated = { [weak self] snapshot in
            Task { @MainActor in
                self?.statistics.update(
                    VSStreamStatistics(
                        displayID: snapshot.displayID,
                        fps: snapshot.fps,
                        bitrateMbps: snapshot.bitrateMbps,
                        droppedFrames: Int(snapshot.droppedFrames),
                        roundTripLatencyMs: snapshot.roundTripLatencyMs
                    )
                )
            }
        }
    }
}
