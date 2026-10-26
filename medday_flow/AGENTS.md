# Antigravity Agent Constitution — MedDay Flow

## Environment & Commands
- **Project Root**: `medday_flow/` (current directory)
- **Framework**: Flutter (Dart ^3.7.2)
- **Primary Platforms**: iOS (HealthKit, Biometrics), Android (AlarmManager, Exact Alarms, Google Fit)

## Emulator & Simulator Workflows
1. **Discover Devices**:
   - `flutter devices` (lists running targets)
   - `flutter emulators` (lists all configured virtual devices)
   - `xcrun simctl list devices available | grep -E "iPhone|iPad"`

2. **Booting Simulators**:
   - 6.7" iPhone Display: `xcrun simctl boot "iPhone 16 Pro Max"` (or `iPhone 18 Pro Max`)
   - 13" iPad Display: `xcrun simctl boot "iPad Pro 13-inch (M4)"` (or `iPad Pro 13-inch (M5)`)

3. **Running the App**:
   - `flutter run -d <device_id>`
   - Use Agentic Hot Reload: send `r` to stdin on code updates, `R` on state changes.

4. **App Store Screenshot Automation**:
   - When generating App Store assets, take native uncompressed simulator captures:
     `xcrun simctl io booted screenshot ~/Desktop/screenshots/<screen_name>.png`
   - Ensure the resolution strictly matches Apple's required dimensions:
     - 6.7" iPhone: 1290 × 2796 px
     - 13" iPad: 2048 × 2732 px

## Safeguards & Rules
- Do not modify `ios/Runner.xcodeproj` or `Podfile` unless addressing specific build errors.
- Never force unwrap platform channel arguments in `AppDelegate.swift`.
- Keep biometrics and passkeys `false` / opt-in by default.
- Always wrap native HealthKit and platform calls in `CatchObjCException` to prevent unhandled `NSException` crashes.
