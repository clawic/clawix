# Clawix · Linux desktop

Tauri 2 (Rust shell + SolidJS frontend) talking to the same `clawix-bridged`
Swift daemon the macOS and iOS apps use. AppImage is the primary
distribution channel; .deb is the secondary channel for Debian/Ubuntu.

## Layout

```
linux/
├── app/            Tauri shell + SolidJS frontend
│   ├── src-tauri/  Rust crate (commands, tray, daemon WS client)
│   └── src/        SolidJS UI (views, components, lib)
├── packaging/      AppImage AppDir + Debian control files
├── scripts/        dev launcher + release builders + hygiene check
├── VERSION         Marketing version (semver)
└── BUILD_NUMBER    Monotonic build counter (matches macos/ scheme)
```

## Run locally

From the workspace root (the private dir, not this public repo):

```sh
bash dev.sh
```

The wrapper detects the cwd inside `<workspace>/Linux/` and delegates to
`linux/scripts/dev.sh`, which builds the bridge daemon (Swift), spawns
it under `systemd-run --user`, and then runs Tauri dev with HMR for the
frontend.

## Release

```sh
bash linux/scripts/build_release_appimage.sh
bash linux/scripts/build_release_deb.sh
```

Both honour `GPG_KEY_ID` from the workspace's `.signing.env`. Output
lands in `linux/release-output/`. Upload to GitHub Releases via the
workspace's `scripts-dev/release-linux.sh` (orchestrates appcast,
zsync, repo apt sync).

## Desktop environment notes

- **GNOME Wayland**: install the "AppIndicator and KStatusNotifierItem
  Support" extension for the tray icon. QuickAsk opens as a centered
  floating window because Wayland disallows arbitrary client-positioned
  surfaces.
- **KDE Plasma**: tray works natively. QuickAsk uses
  `zwlr_layer_shell_v1` to anchor under the cursor.
- **X11 sessions** (XFCE / Cinnamon / i3 / Mate): tray and global
  shortcut both work without extra configuration.

## Dependencies for installation users

The `.deb` declares them in `control.in`. AppImage users need the
runtime equivalents on their system:

- `libwebkit2gtk-4.1-0`, `libgtk-3-0`
- `libayatana-appindicator3-1` (for tray on KDE/X11)
- `libnotify4`
- Optional: `wtype` or `xdotool` (TextInjector), `wl-clipboard` or
  `xclip` (selection sniffer)
- Optional: `avahi-daemon` (mDNS for iPhone pairing); falls back to
  manual IP entry if missing.
