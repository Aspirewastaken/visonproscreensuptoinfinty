# visionproscreensuptoinfinity

**Open source multi-Mac-display for Apple Vision Pro. Up to infinity.**

Stream unlimited Mac virtual displays to your Vision Pro as independent spatial windows.
Free. Open source. No accounts. No telemetry. Fully local.

---

## Features

- 🖥️ **Create virtual Mac displays** and stream them to Vision Pro
- 🪟 **Each display is an independent spatial window** — move it anywhere in your space
- ⚡ **60fps HEVC hardware encoding/decoding** — Apple Silicon media engine on both sides
- 🖱️ **Mouse + keyboard input forwarding** — look at a display and interact with it
- 📡 **Auto-discovery via Bonjour** — one tap to connect, no manual IP config
- 🔒 **Fully local** — no cloud, no accounts, no telemetry, no tracking
- 📖 **MIT licensed** — fork it, ship it, improve it

## Architecture

```
macOS Companion                         visionOS App
+---------------------------+           +------------------------------+
|                           |           |                              |
|  CGVirtualDisplay (1..N)  |  Network  |  RealityKit Window N         |
|         |                 |  ----->>  |  (spatial, moveable)         |
|         v                 |   HEVC    |                              |
|  ScreenCaptureKit         |  stream   |  VideoToolbox Decoder        |
|  (per-display capture)    |  (UDP)    |  (hardware HEVC)             |
|         |                 |           |                              |
|         v                 |  <<-----  |  Input Forwarding            |
|  VideoToolbox             |   HID     |  (cursor + keyboard)         |
|  HEVC Encoder (hardware)  |  events   |  via spatial gestures        |
|         |                 |  (TCP)    |                              |
|         v                 |           |  Bonjour Discovery           |
|  NWConnection (UDP video) |           |  + Pairing UI                |
|  NWConnection (TCP ctrl)  |           |                              |
+---------------------------+           +------------------------------+
```

**Pipeline per display:**
1. `CGVirtualDisplay` creates a virtual display visible to the system
2. `ScreenCaptureKit` captures frames as `CMSampleBuffer` (Metal-backed, zero-copy)
3. `VideoToolbox` encodes to HEVC in real-time (hardware, Apple Silicon media engine)
4. Encoded frames are packetized into MTU-safe UDP packets and streamed
5. Vision Pro receives, reassembles, and decodes frames (hardware HEVC decode)
6. Decoded frames render to `RealityKit` plane entities via `DrawableQueue`
7. Input events (mouse, keyboard) forward back to Mac over TCP control channel

## Requirements

| Component | Requirement |
|-----------|-------------|
| **Mac** | Apple Silicon (M1 or later), macOS 15.2+ (Sequoia) |
| **Vision Pro** | Apple Vision Pro, visionOS 2.2+ |
| **Network** | Both devices on the same Wi-Fi network |
| **Xcode** | 16.0+ (for building from source) |
| **XcodeGen** | 2.38.0+ (for generating Xcode project) |

## Build from Source

### Prerequisites

1. **Install XcodeGen** (generates the Xcode project from `project.yml`):
   ```bash
   brew install xcodegen
   ```

2. **Xcode 16.0+** with macOS 15.2 SDK and visionOS 2.2 SDK installed

### Build Steps

```bash
# 1. Clone the repository
git clone https://github.com/Aspirewastaken/visionproscreensuptoinfinity.git
cd visionproscreensuptoinfinity

# 2. Generate the Xcode project
xcodegen

# 3. Open in Xcode
open VisionProScreensUpToInfinity.xcodeproj
```

#### macOS Companion App
1. Select the **VisionScreenMac** scheme
2. Build and run (⌘R)
3. The app appears as a menu bar icon (no dock icon)

#### visionOS App
1. Select the **VisionProScreens** scheme
2. Select your Vision Pro device or visionOS Simulator as destination
3. Build and run (⌘R)

### Running Tests

```bash
# Run shared protocol tests
xcodebuild test -scheme SharedTests -destination 'platform=macOS'

# Run macOS-specific tests
xcodebuild test -scheme MacTests -destination 'platform=macOS'
```

## Usage

### First Time Setup

1. **Mac**: Launch VisionScreenMac — it appears in the menu bar
2. **Vision Pro**: Launch VisionProScreens
3. **Grant Permissions** on Mac:
   - **Screen Recording**: Required for `ScreenCaptureKit` to capture displays
   - **Accessibility**: Required for `CGEvent` input injection (mouse + keyboard forwarding)
4. **Connect**: The Vision Pro app will discover your Mac automatically via Bonjour. Tap "Connect"
5. **Add Displays**: Tap "Add Virtual Display" to create a new virtual Mac display
6. **Use**: Each display opens as an independent spatial window you can move anywhere

### Permissions Required

| Permission | Where | Why |
|-----------|-------|-----|
| Screen Recording | macOS System Settings > Privacy & Security | Capture virtual display content |
| Accessibility | macOS System Settings > Privacy & Security | Inject mouse/keyboard events from Vision Pro |
| Local Network | macOS + visionOS | Bonjour discovery and video streaming |

### Display Resolutions

| Preset | Resolution | Bitrate | Use Case |
|--------|-----------|---------|----------|
| 720p | 1280×720 | 10 Mbps | Low bandwidth |
| 1080p | 1920×1080 | 20 Mbps | Default / recommended |
| 1080p Low | 1920×1080 | 12 Mbps | Battery saver |
| 1440p | 2560×1440 | 30 Mbps | High quality |

## Project Structure

```
visionproscreensuptoinfinity/
├── Shared/                          # Code shared between macOS and visionOS
│   ├── Protocol/
│   │   ├── VSConstants.swift        # Shared constants (ports, limits, magic bytes)
│   │   ├── VSMessage.swift          # Control message types (JSON/Codable)
│   │   └── VSProtocol.swift         # Wire protocol (binary frame headers)
│   ├── Network/
│   │   ├── VSBonjourService.swift   # Bonjour advertise (NWListener) + browse (NWBrowser)
│   │   ├── VSConnection.swift       # TCP control + UDP video wrappers
│   │   └── VSFramePacket.swift      # Frame packetization + reassembly
│   └── Video/
│       └── VSVideoConfig.swift      # Resolution, bitrate, FPS configs
├── macOS/                           # macOS companion app
│   ├── App/
│   │   ├── VisionScreenMacApp.swift # @main entry point (MenuBarExtra)
│   │   └── MenuBarView.swift        # Menu bar dropdown UI
│   ├── Display/
│   │   ├── VSVirtualDisplayManager.swift  # CGVirtualDisplay private API
│   │   └── VSScreenCapture.swift          # ScreenCaptureKit per-display capture
│   ├── Encoding/
│   │   └── VSHEVCEncoder.swift      # VideoToolbox HEVC hardware encoder
│   ├── Input/
│   │   └── VSInputInjector.swift    # CGEvent mouse/keyboard injection
│   └── Network/
│       └── VSMacServer.swift        # Server orchestrator (capture→encode→stream)
├── visionOS/                        # visionOS spatial app
│   ├── App/
│   │   ├── VisionProScreensApp.swift  # @main entry point (multi-window)
│   │   └── ContentView.swift          # Main UI (discovery + connected state)
│   ├── Discovery/
│   │   └── VSDiscoveryView.swift    # Bonjour browser UI
│   ├── Decoding/
│   │   └── VSHEVCDecoder.swift      # VideoToolbox HEVC hardware decoder
│   ├── Display/
│   │   ├── VSDisplayWindow.swift    # RealityKit display surface + DrawableQueue
│   │   └── VSWindowManager.swift    # Multi-window lifecycle management
│   ├── Input/
│   │   └── VSInputForwarder.swift   # Mouse/keyboard event forwarding
│   └── Network/
│       └── VSVisionClient.swift     # Connection manager (pair, receive, decode)
├── Tests/
│   ├── SharedTests/                 # Protocol & packet tests
│   └── macOSTests/                  # Encoder & config tests
├── project.yml                      # XcodeGen project specification
├── LICENSE                          # MIT License
└── README.md                        # This file
```

## Wire Protocol

### Video Frames (UDP)

```
Frame Packet:
+----------+-----------+----------+----------+---------------+
| Magic(4) | SeqNum(4) | DispID(1)| Flags(1) | Payload       |
| "VPSI"   | uint32 LE | uint8    | bitfield | HEVC NALUs    |
+----------+-----------+----------+----------+---------------+

Flags:
  bit 0: keyframe (IDR frame)
  bit 1: end of frame (last packet for this frame)
  bit 2-7: reserved
```

Large frames are split into 1400-byte packets (MTU-safe). The receiver reassembles them using sequence numbers and the `endOfFrame` flag.

### Control Messages (TCP, JSON)

```json
{ "type": "pair_request",    "payload": { "deviceName": "...", "protocolVersion": 1 } }
{ "type": "pair_accept",     "payload": { "macName": "...", "displays": [...] } }
{ "type": "display_add",     "payload": { "displayID": 1, "width": 1920, "height": 1080 } }
{ "type": "display_remove",  "payload": { "displayID": 1 } }
{ "type": "input_mouse",     "payload": { "displayID": 1, "x": 0.5, "y": 0.3, "button": 0 } }
{ "type": "input_key",       "payload": { "displayID": 1, "keyCode": 36, "down": true } }
{ "type": "request_keyframe","payload": { "displayID": 1 } }
{ "type": "heartbeat",       "payload": { "timestamp": 1234567890 } }
```

## Known Limitations

- **CGVirtualDisplay is a private API** — it's undocumented and may change in future macOS versions. If Apple removes it, the app falls back to capturing existing displays.
- **No encryption** in v1 — video streams are unencrypted on the local network. Use on trusted networks only.
- **Input forwarding is limited** — visionOS restricts low-level input access. Mouse forwarding uses gaze/hover position; keyboard requires a hardware keyboard connected to Vision Pro.
- **Maximum 4 displays** in v1 — configurable in code, but untested beyond 4.

## Roadmap

- [ ] Adaptive bitrate based on network conditions
- [ ] Individual app window streaming (via `SCWindow` filtering)
- [ ] Multi-Mac support (connect to 2+ Macs simultaneously)
- [ ] Audio forwarding to Vision Pro spatial audio
- [ ] TLS/DTLS encryption for video streams
- [ ] 3D display arrangement with snap-to-grid
- [ ] Pre-built releases (DMG for macOS, TestFlight for visionOS)

## Why "up to infinity"?

Because Apple gatekeeps multi-display behind unreleased visionOS feature flags. They have it internally. They're saving it for Vision Pro 2. The APIs to build this exist **today** — `CGVirtualDisplay`, `ScreenCaptureKit`, `VideoToolbox` HEVC hardware encode/decode. We just used them. You're welcome.

## Contributing

PRs welcome. Please:
1. Fork the repo
2. Create a feature branch
3. Write tests for new protocol/packet code
4. Submit a PR with a clear description

## License

MIT License. See [LICENSE](LICENSE) for details.

---

**Built with ❤️ for the open source spatial computing community.**
