# Clawix Linux Context

These notes are public repository guidance for agents touching
`clawix/linux/`. Private local workspace rules still take precedence
for local-only preferences, signing, secrets, and launcher behavior.

## Stack

- Tauri 2 (Rust shell) + SolidJS + TypeScript + Vite + TailwindCSS.
- WebSocket client to `clawix-bridged` on `127.0.0.1:7778`, using the
  bearer read from `~/.clawix/state/bridge-token`.
- Local persistence: `rusqlite` on the Tauri side for chat history and
  preferences. The logical schema mirrors the Mac app's GRDB cache.
- Build artifacts:
  - Primary: GPG-signed AppImage with zsync metadata for AppImageUpdate.
  - Secondary: `.deb` package for Debian/Ubuntu.

## Agent Rules

- Ambiguous references inside `linux/` mean the Linux app. Do not touch
  `macos/` or `ios/` unless the issue is cross-platform integration; if
  it is, say so explicitly.
- Refactor `packages/` before touching `linux/app/` when adding features
  that depend on daemon capabilities (engine, bridge, secrets).
- The Swift daemon is the source of truth. The Tauri GUI must not persist
  state that the daemon also owns (chats, sessions, vault). It may only
  cache offline reads and store GUI-specific preferences.
- Keep the Tauri plugin runtime in sync: `package.json` and `Cargo.toml`
  versions move together. Mismatches break IPC.
- StatusNotifierItem tray support requires the GNOME AppIndicator
  extension. Document that in UI that depends on the tray; do not assume
  the tray is visible.

## Global Hotkeys And QuickAsk On Wayland

- GNOME Wayland: centered window, not cursor-positioned.
- KDE/wlroots: `zwlr_layer_shell_v1` allows a floating window anchored
  near the cursor.
- X11: arbitrary positioning and always-on-top are available.
- Do not try to work around GNOME with hostile shell extensions. The
  degradation is accepted and should be visible the first time the user
  opens QuickAsk on GNOME.

## Text Injector And Selection Sniffer

- Text injection: `wtype` on Wayland, `xdotool` on X11. Never use
  CGEvent or Cmd+V; they do not exist on Linux.
- Selection read: PRIMARY clipboard via `wl-paste -p` or
  `xclip -selection primary -o`. Do not use AT-SPI2; it breaks in
  Electron, JetBrains IDEs, and terminals.

## Dictation

- whisper.cpp is downloaded into `~/.clawix/whisper/` on first run.
- Acceleration runtime detection: CUDA, Vulkan, ROCm. CPU is the default.
- AppleSpeechRecorder does not exist on Linux, so that option is not
  shown in the UI.

## Shared Daemon Across Installers

The npm CLI, AppImage, and `.deb` all activate the same systemd user
unit: `clawix-bridge.service`. The binary path can be overridden with
`CLAWIX_BRIDGE_BIN`. `service_manager.rs` resolves the daemon path in
this order:

1. `$CLAWIX_BRIDGE_BIN`
2. `~/.clawix/bin/clawix-bridged` (CLI npm install)
3. `/usr/lib/clawix/clawix-bridged` (`.deb`)
4. `/opt/clawix/clawix-bridged` (AppImage extract or `.deb` opt layout)
5. `clawix-bridged` on `PATH`

## Versioning

The daemon exposes its version in the WebSocket handshake. The Tauri GUI
compares it against its `package.json` and shows a visible warning when
major.minor does not match. The daemon wins because it is the source of
truth.

## Out Of Scope For Linux

- WhisperKit / CoreML (Apple-only).
- AppKit / SwiftUI / MenuBarExtra (Apple-only).
- Sparkle (replaced by `tauri-plugin-updater` with a custom appcast).
- AppIntents / Shortcuts.app (degrades to CLI + D-Bus methods).
- launchd plists (replaced by systemd user units).

## Flatpak

Flatpak is planned as a third channel after AppImage and `.deb` are
validated in production. It is not part of v1.
