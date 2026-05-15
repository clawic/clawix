# Clawix · Windows context

This directory is the Windows target for Clawix. Any conversation opened from here, or from the private `<workspace>/windows/` anchor, treats ambiguous references to "the app", "Clawix", "this", "the project", or "build it" as the Windows app, never macOS or iOS.

## Stack And Architecture

- **UI**: WinUI 3 on **.NET 8** (C# 12). Native Windows 11 Fluent Design with Mica windowing and acrylic backgrounds.
- **Daemon**: `Clawix.Bridged/clawix-bridge.exe` runs as a per-user process started at login through `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. It is not a Windows Service, does not require admin rights, and keeps running after the GUI closes.
- **Wire protocol**: identical to macOS and iOS. Schema version 1. JSON frames over WebSocket on `127.0.0.1:24080`.
- **Bonjour**: publishes `_clawix-bridge._tcp` with `Makaretu.Dns.Multicast` in pure C#, without requiring Apple Bonjour Service.
- **Codex CLI**: the daemon spawns `codex.cmd` as a subprocess, searched in `%APPDATA%\npm\codex.cmd`, `%LOCALAPPDATA%\nvm\v*\codex.cmd`, and `where codex`.
- **Parity**: functional parity with macOS, not visual parity. Each screen is redesigned with native WinUI components while preserving the same information architecture.

## Structure

```text
windows/
├── Clawix.sln
├── Clawix.App/             ← WinUI 3 GUI
├── Clawix.Core/            ← wire protocol + models (C# port of packages/ClawixCore)
├── Clawix.Engine/          ← bridge server, pairing, mDNS (C# port of packages/ClawixEngine)
├── Clawix.Bridged/         ← clawix-bridge.exe daemon
├── Clawix.Secrets/         ← vault crypto + persistence (port of packages/Secrets*)
├── Clawix.Tests/           ← xUnit, round-trip JSON against Swift fixtures
├── scripts/                ← dev.ps1, build-app.ps1, public_hygiene_check.ps1
├── VERSION                 ← semver
└── BUILD_NUMBER            ← monotonic build number
```

## Hard Rules Inherited From `<workspace>/AGENTS.md`

- **Literal blacklist**: the real Team ID, real bundle id (`BUNDLE_ID` in `.signing.env`), SKU (`APP_SKU`), and Authenticode certificate thumbprint (`WIN_SIGN_THUMBPRINT`) never appear in code under `clawix/windows/`. They are read from environment variables at runtime.
- **Signed build**: run `pwsh scripts/build-app.ps1` from the workspace root. The script reads `.signing.env` and signs with `signtool.exe` using `WIN_SIGN_THUMBPRINT`. Without stable signing, SmartScreen blocks the binary.
- **Coalesced restart**: agents use `pwsh scripts-dev/restart-app.ps1 --requester "<id>"` from the workspace root, not `dev.ps1` directly. It uses the same `SCHEDULED/QUEUED/BLOCKED/PENDING_UNLOCK` contract and `<workspace>\.dev-control\` state as macOS.
- **`real` vs `dummy` mode**: read `<workspace>\.app-mode`, same as macOS. The same user phrases switch the mode.
- **Commits**: Conventional Commits with a `windows/` or `win/` scope, for example `feat(windows): add daemon heartbeat`.

## When To Touch iOS Or macOS From Here

By default, do not touch `../macos/` or `../ios/`. Legitimate exceptions:

- Wire protocol changes start in `packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift` and `BridgeProtocol.md`, then get ported to `Clawix.Core/BridgeProtocol.cs`. If the change breaks iOS or macOS, edit those targets too; the Swift wire protocol remains the source of truth.
- Cross-platform compatibility changes for Windows may touch Mac or iOS, but call that out explicitly before editing.

## Shared Cross-Platform Code

`packages/*` (Swift) remains the source for `Clawix.Core` and `Clawix.Engine`. Any change in `BridgeProtocol`, bridge models, or `PairingService` starts in Swift and is mirrored here. `Clawix.Tests/Fixtures/` must match the Swift test fixtures byte for byte.

## Releases

Windows release rules live in the private `<workspace>/RELEASE_WINDOWS.md`. Before publishing, except dry runs, get user approval for the English release notes, using the same flow as macOS. Canonical asset: `Clawix-Setup.msix`. Auto-update uses NetSparkle and the same `appcast.xml` as macOS, with a `<enclosure sparkle:os="windows">` item.
