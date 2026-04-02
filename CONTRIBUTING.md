# Contributing

Thanks for helping build `visionproscreensuptoinfinity`.

## Ground rules

- Keep the project fully local-only.
- Do not add cloud services, telemetry, analytics, or account systems.
- Prefer Swift-only implementations.
- Treat the virtual display backend as experimental and keep it isolated behind abstractions.

## Development setup

1. Use an Apple Silicon Mac running macOS 15.2+.
2. Install Xcode 16+.
3. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
4. Generate the project:

   ```bash
   xcodegen generate
   ```

5. Open `VisionProScreensUpToInfinity.xcodeproj`.

## Testing expectations

- Add or update targeted unit tests for shared protocol and packetization changes.
- Validate streaming and input changes on real macOS + visionOS hardware.
- Document any private-API or entitlement regressions clearly in pull requests.

## Pull requests

- Keep changes scoped and reviewable.
- Include notes about which backend was tested:
  - virtual display backend
  - physical display fallback
- Include manual test evidence when changing streaming, pairing, or input code.
