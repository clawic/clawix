# Clawix · Windows target

Windows port of Clawix. Pairs with the local `clawix-bridged.exe`
daemon and the iOS companion exactly the same way macOS does.

## Quick start

Prereqs:
- Windows 11 (Windows 10 best-effort)
- .NET 8 SDK
- Visual Studio 2022 with the *Windows App SDK* workload (or `dotnet`
  CLI alone for headless builds)
- Codex CLI installed via `npm install -g codex` (or `volta`/`pnpm`)

```powershell
# From this folder:
dotnet restore
dotnet build Clawix.sln -c Debug -p:Platform=x64

# Or use the dev launcher (kills previous instance, picks .app-mode):
pwsh scripts\dev.ps1
```

Run the daemon standalone for protocol smoke tests:

```powershell
dotnet run --project Clawix.Bridged
```

The daemon writes a heartbeat at
`%USERPROFILE%\.clawix\state\bridge-status.json` every 2 seconds so the
GUI and the npm CLI know it's alive.

## Layout

```
windows/
|-- Clawix.sln                    Solution
|-- Clawix.App/                   WinUI 3 GUI (.NET 8)
|-- Clawix.Core/                  Wire protocol + models (port of packages/ClawixCore)
|-- Clawix.Engine/                Bridge server + pairing + mDNS (port of packages/ClawixEngine)
|-- Clawix.Bridged/               clawix-bridged.exe daemon
|-- Clawix.Secrets/               Vault crypto + persistence
|-- Clawix.Tests/                 xUnit, round-trip JSON against Swift fixtures
|-- scripts/                      dev.ps1, build-app.ps1, build-release.ps1, public_hygiene_check.ps1
|-- VERSION                       Semver
|-- BUILD_NUMBER                  Monotonic build counter
|-- CLAUDE.md                     Anchor for AI agents (read first)
`-- README.md                     This file
```

## How parity works

- **Wire protocol** (`Clawix.Core`): the JSON shape on the wire is
  bit-identical to Swift. Tests in `Clawix.Tests` round-trip the
  fixtures from the Swift test suite, so any drift fails fast.
- **Pairing** (`Clawix.Engine.Pairing`): bearer + short code generated
  with the same algorithm as macOS. Stored in
  `%APPDATA%\Clawix\pairing.json`. The QR JSON is identical: an iPhone
  paired against this PC sees the same payload it would see paired
  against a Mac.
- **mDNS** (`Clawix.Engine.Discovery.BonjourPublisher`): publishes
  `_clawix-bridge._tcp` via `Makaretu.Dns.Multicast` (pure C#, no Apple
  Bonjour Service required). The iPhone discovery code does not change.
- **Daemon process** (`Clawix.Bridged`): registers itself for auto-start
  via the HKCU `Run` registry key (mirroring macOS LaunchAgent), spawns
  the Codex CLI as a JSON-RPC subprocess, owns the WebSocket server.
- **Auto-update**: NetSparkle reads the same `appcast.xml` Sparkle uses
  on macOS, filtered by `sparkle:os="windows"`. Same EdDSA signing key.

## Where to start when adding a feature

1. If it's a new wire frame: add it to `packages/ClawixCore` (Swift)
   first, then mirror it in `Clawix.Core/BridgeProtocol.cs`. Tests
   should be added in both Swift and `Clawix.Tests`.
2. If it's a new daemon capability (e.g. better Codex routing): add to
   `Clawix.Bridged/DaemonEngineHost.cs`, ensure macOS counterpart
   matches behaviorally.
3. If it's a new GUI screen: create `Views/<Name>.xaml` +
   `ViewModels/<Name>ViewModel.cs`. Bind to `App.Services.State` for
   shared chat / message state.

## Tests

```powershell
dotnet test Clawix.Tests
```

The fixtures in `Clawix.Tests/Fixtures/` come from running the Swift
test suite with `swift test --filter BridgeProtocolFixturesTests`. Any
JSON drift between Swift and C# fails the round-trip tests.

## Release

The release pipeline lives in `<workspace>/RELEASE_WINDOWS.md`
(private). Asset name is `Clawix-Setup.msix`. Code signing via
`signtool.exe` using `WIN_SIGN_THUMBPRINT` from `.signing.env`.
