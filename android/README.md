# Clawix · Android client

Companion app for the Clawix bridge daemon (`clawix-bridge`) that runs on macOS. Pair via QR or short code, then chat with Codex from your phone over LAN or Tailscale.

100% functional + visual parity with the iOS app (`clawix/ios/`).

## Prereqs

- Android Studio Hedgehog or newer.
- JDK 21.
- Android SDK platform 35 + build-tools 35.
- A device or emulator running Android 10 (API 29) or newer.

## First build

The Gradle wrapper jar is not checked in. Generate it once on a machine that has Gradle installed:

```bash
cd clawix/android
gradle wrapper --gradle-version 8.10.2
```

Then:

```bash
./gradlew :app:assembleDebug
./gradlew :app:installDebug
```

Open Android Studio with the `clawix/android/` folder for IDE support; it regenerates the wrapper automatically on first sync.

## Stack

- Kotlin 2.0 + Jetpack Compose (Material3 vehicle, custom theme override).
- Dark mode forced (`UIUserInterfaceStyle = Dark` parity).
- min SDK 29, target SDK 35.
- OkHttp 4 WebSocket, kotlinx-serialization JSON, kotlinx-datetime ISO-8601.
- ML Kit barcode scanning + CameraX for QR.
- `NsdManager` + `WifiManager.MulticastLock` for Bonjour mDNS.
- `EncryptedSharedPreferences` for credentials.

## Known visual deltas vs iOS

- **Glass blur on API 29-30**: `RenderEffect.createBlurEffect` requires API 31+. Fallback uses translucent layer + dim, no real blur. Pills look "flat" rather than refractive on Android 10-11.
- **Speech-to-text**: requires the daemon to be online (sends `transcribeAudio` frame). iOS has an on-device fallback via `SFSpeechRecognizer`; Android does not without Google Play Services.
- **Permission rationale**: Android needs explicit modal copy before runtime permission prompt; iOS reads its `NSCameraUsageDescription` etc. directly. One extra UI step on Android.

## Layout

```
app/src/main/java/com/example/clawix/android/
├── theme/         design tokens, fonts, glass modifiers, haptics
├── icons/         lucide font wrapper + 16 path-based icons
├── core/          wire protocol port (mirrors clawix/packages/ClawixCore)
├── bridge/        BridgeClient, BridgeStore, mDNS, credentials
├── pairing/       QR + short-code pairing
├── chatlist/      home screen
├── chatdetail/    transcript + markdown + image/file viewers
├── projectdetail/ project view
├── composer/      input area + camera + photo picker + voice
└── util/          small helpers
```
