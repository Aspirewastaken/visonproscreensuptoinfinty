# Testing and validation

This repository targets macOS and visionOS, but the initial implementation was authored in a Linux cloud environment without access to Apple SDKs or `xcodebuild`. Because of that, validation is split into:

1. **source-level validation** that can be reviewed in this repository
2. **hardware validation** that must be completed on Apple Silicon Mac hardware and Apple Vision Pro hardware

## Source-level validation included in the repo

The repository includes:

- shared protocol types
- packetization and control-message tests
- declarative project configuration through `project.yml`
- architecture and permission documentation

These artifacts validate the code structure and wire contract, but they do **not** prove runtime correctness of macOS or visionOS frameworks.

## Required hardware and software

- Apple Silicon Mac running macOS 15.2+
- Apple Vision Pro running visionOS 2.2+
- Xcode 16+
- XcodeGen
- both devices on the same local Wi‑Fi network

## Build steps

1. Install XcodeGen.
2. From the repository root run:

   ```bash
   xcodegen generate
   ```

3. Open `VisionProScreensUpToInfinity.xcodeproj`.
4. Build the `VisionScreenMac` and `VisionProScreens` schemes.

## Permission checklist

### macOS companion

The app should prompt for or otherwise require:

- Screen Recording
- Accessibility
- Local Network

Expected behavior:

- capture features stay disabled until Screen Recording permission is granted
- input injection stays disabled until Accessibility permission is granted
- discovery/streaming waits for Local Network approval

### visionOS app

The app requires:

- Local Network access

Expected behavior:

- discovery UI should explain when no local network permission has been granted yet

## Manual validation plan

## 1. Menu bar shell

1. Launch the macOS app.
2. Verify it appears in the menu bar.
3. Verify it does not appear as a normal dock app.
4. Confirm the UI shows:
   - permission states
   - server/discovery state
   - display count controls
   - bitrate and frame-rate configuration

## 2. Display source validation

### Experimental virtual-display path

1. Select the virtual-display backend.
2. Add one display.
3. Verify a new display appears in System Settings > Displays.
4. Repeat until four displays or until the backend fails.

If this backend fails on the host machine, switch to the physical-display fallback and continue validating the rest of the pipeline.

### Physical-display fallback path

1. Select the fallback backend.
2. Verify attached physical displays are enumerated.
3. Mark one display active for capture/streaming.

## 3. Capture and encode validation

1. Activate one display for capture.
2. Start the stream server.
3. Confirm per-display stats show:
   - frame production
   - encoded frame rate
   - bitrate updates
4. Verify keyframes are emitted approximately once per second or when requested.

## 4. Discovery and pairing validation

1. Launch the visionOS app.
2. Grant Local Network access.
3. Verify the Mac appears in the available hosts list.
4. Tap connect.
5. Confirm the control channel transitions to connected/paired state.

## 5. End-to-end display streaming validation

1. Start with one display.
2. Verify display window 1 opens and shows the expected stream.
3. Add display 2 and verify window 2 opens.
4. Repeat through display 4.
5. Confirm each window is independently visible and labelled.

## 6. Input validation

1. Open a simple app such as TextEdit on the streamed display.
2. Move the pointer over the corresponding visionOS display window.
3. Click into the text area.
4. Type on the paired keyboard.
5. Confirm the correct display receives:
   - mouse move
   - mouse down/up
   - scroll events
   - key down/up

## 7. Recovery validation

1. While streaming, disconnect the visionOS app.
2. Verify the macOS app cleans up session state without crashing.
3. Reconnect and confirm streaming resumes.
4. Repeat 20 times to validate disconnect/reconnect stability.

## 8. Performance validation

1. Stream 1 display, then 2, then 4.
2. Observe:
   - FPS
   - bitrate
   - dropped fragments/frames
   - round-trip latency
3. Use Activity Monitor and Instruments on the Mac to assess:
   - CPU usage
   - memory growth
   - encoder/decoder stability over time

## Success criteria

The MVP should only be considered validated when all of the following are true on Apple hardware:

- the Mac advertises successfully over Bonjour
- the visionOS app connects and pairs with one tap
- 1–4 displays can be viewed in separate windows
- input can be forwarded back to the correct display
- reconnect does not crash either side
- performance telemetry is visible and useful

## Known limits of current cloud validation

The cloud executor cannot currently verify:

- macOS compilation
- visionOS compilation
- ScreenCaptureKit runtime behavior
- VideoToolbox runtime behavior
- local network behavior on Apple devices
- accessibility and screen-recording permission flows

Those checks are intentionally documented here so they can be completed on real hardware immediately after code review.
