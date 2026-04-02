# Architecture

```text
macOS Companion                         visionOS App
+---------------------------+           +------------------------------+
|                           |           |                              |
|  Display Source Provider  |  Network  |  Discovery + Pairing        |
|  - Virtual (experimental) |  ----->>  |  - Bonjour browse           |
|  - Physical fallback      |   HEVC    |  - TCP control              |
|         |                 |  stream   |                              |
|         v                 |           |  Window Manager             |
|  ScreenCaptureKit         |           |  - 4 predeclared windows    |
|  (per-display capture)    |           |                              |
|         |                 |           |  Video decode/present       |
|         v                 |  <<-----  |  - VTDecompressionSession   |
|  VideoToolbox             |   HID     |  - Sample-buffer surface    |
|  HEVC Encoder             |  events   |                              |
|         |                 |           |  Input forwarding           |
|         v                 |           |  - pointer/keyboard/scroll  |
|  TCP + UDP session        |           |                              |
|  Bonjour advertisement    |           |  Performance overlay        |
+---------------------------+           +------------------------------+
```

## Design principles

- **Local only:** all streaming and control traffic remains on the local network.
- **Backend isolation:** the rest of the pipeline does not assume virtual display creation succeeds.
- **Practical MVP:** phase 1 targets 1–4 concurrent displays, not arbitrary scene creation.
- **Recoverability:** packet loss and reconnects are expected and must be survivable.

## Components

### Shared

- `VSConstants`: protocol and transport defaults
- `VSMessage`: TCP control message envelope and payloads
- `VSFramePacket`: UDP frame fragmentation/reassembly contract
- `VSConnection`: Network.framework wrappers for TCP/UDP
- `VSBonjourService`: shared Bonjour advertise/browse support
- `VSVideoConfig`: presets and bitrate helpers

### macOS companion

- `MacAppModel`: top-level state orchestration
- `VSDisplaySourceProvider`: abstraction over display source backends
- `VSVirtualDisplayManager`: experimental private-API-backed virtual displays
- `VSPhysicalDisplaySource`: fallback backend for existing displays
- `VSScreenCapture`: ScreenCaptureKit capture
- `VSHEVCEncoder`: VideoToolbox encoder
- `VSMacServer` / `VSMacSession`: control + streaming server
- `VSInputInjector`: mouse and keyboard event injection

### visionOS client

- `VisionAppModel`: top-level client state
- `VSDiscoveryView`: Bonjour discovery UI
- `VSVisionClient`: TCP/UDP client
- `VSHEVCDecoder`: VideoToolbox decoder
- `VSWindowManager`: maps display IDs to one of four predeclared windows
- `VSDisplayWindow`: per-display window UI
- `VSInputForwarder`: sends input events back to the Mac

## Transport

### TCP

- Length-prefixed JSON control messages
- Pairing, display lifecycle, input events, and RTT ping/pong

### UDP

- Binary frame packets with:
  - magic/version
  - display ID
  - sequence number
  - frame number
  - fragment index/count
  - timestamp
- Per-display reassembly state on the client
- Keyframe requests when reassembly repeatedly fails

## Known limitations

- Virtual display creation is **experimental** and may break across macOS releases.
- The current cloud implementation environment cannot compile or run Apple targets.
- Real hardware validation is required on Apple Silicon + Vision Pro before claiming MVP complete.
