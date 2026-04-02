# visionproscreensuptoinfinity

Open source multi-Mac-display for Apple Vision Pro. Up to infinity.

> Status: MVP foundation in progress. The virtual display backend is **experimental** because it depends on private / reverse-engineered macOS APIs. The project includes a fallback architecture for capturing existing displays when virtual display creation is unavailable.

## What this project aims to do

`visionproscreensuptoinfinity` pairs:

- a **macOS menu bar companion app** that creates or selects displays, captures them with ScreenCaptureKit, encodes them with VideoToolbox, and streams them over the local network
- a **visionOS app** that discovers the Mac over Bonjour, receives HEVC video, shows each display in its own window, and forwards input back to macOS

The project is fully local:

- no cloud services
- no accounts
- no telemetry
- no remote relay

## MVP scope

Phase 1 intentionally focuses on a practical and testable MVP:

- 1–4 concurrent displays
- Bonjour discovery and pairing on the local network
- HEVC hardware encode/decode pipeline
- per-display windows on visionOS
- mouse + keyboard input forwarding
- performance overlay and reconnect handling

The long-term direction remains “up to infinity”, but the initial implementation is deliberately capped at four displays to reduce scene-management and transport risk.

## Platform requirements

- Apple Silicon Mac running **macOS 15.2+**
- Apple Vision Pro running **visionOS 2.2+**
- Both devices on the same Wi‑Fi network
- Xcode 16+ on a Mac for building

## Important implementation note

### Virtual displays are experimental

The proposed `CGVirtualDisplay` path does not appear to be a stable public API. Because of that:

- the code isolates virtual display creation behind a backend abstraction
- the project also includes a physical-display fallback path
- the virtual display backend should be treated as developer/experimental functionality

If Apple changes or blocks this path on future macOS releases, the rest of the streaming architecture can still function against captured physical displays.

## Repository layout

```text
visionproscreensuptoinfinity/
  Config/
  Docs/
  Shared/
  macOS/
  visionOS/
  Tests/
  project.yml
```

## Building

This repository uses an XcodeGen project specification:

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) on your Mac.
2. Run:

   ```bash
   xcodegen generate
   ```

3. Open the generated `VisionProScreensUpToInfinity.xcodeproj`.
4. Build the macOS and visionOS targets with Xcode.

## Permissions

The macOS companion app requires:

- Screen Recording permission
- Accessibility permission
- Local Network access

The visionOS app requires:

- Local Network access

## Documentation

- Architecture overview: `Docs/Architecture.md`
- Testing and validation checklist: `Docs/Testing.md`
- Contribution workflow: `CONTRIBUTING.md`

## License

MIT
