# clawix

Use the [Codex CLI](https://github.com/openai/codex) remotely from your phone via your Mac.

`clawix` is the standalone bridge surface: install once with npm, start the daemon, scan a QR (or type a 9-character code) on the Clawix iOS app, and your phone is now talking to the same Codex session your Mac is. The full Mac GUI is optional.

## Install

```bash
npm install -g clawix
```

`postinstall` downloads a pre-signed, pre-notarized macOS binary tarball from the matching GitHub release, verifies its SHA-256 against the manifest committed to this package, and verifies every binary with `codesign --strict`. Nothing is built on your machine.

Requirements: macOS 14 (Sonoma) or later, on Apple Silicon or Intel. Linux and Windows are planned.

## Quick start

```bash
clawix up
```

Starts the bridge, attaches the menu bar icon, prints a pairing QR + a typeable short code, and watches live for incoming connections. Press `Ctrl+C` to stop watching; the bridge keeps running in the background.

```
clawix bridge ready

  on lan       192.168.1.42:24080
  on tailscale 100.64.x.x

scan with the Clawix iOS app

  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
  █ █▀▀▀▀▀█ ▄ ▀▄ █▀▀▀▀▀█ ▀▄ █
  ...

or paste this short code in the iOS app

  XK4-7JM-9BP

watching… press Ctrl+C to stop watching (the bridge keeps running).

  ●  no devices paired yet
```

## Commands

| Command | What it does |
|---|---|
| `clawix up` | Start bridge + menu bar, print QR + short code, watch live status. |
| `clawix start` | Start bridge as a launchd agent (no QR, no watch). Survives reboots. |
| `clawix stop` | Stop bridge + menu bar. |
| `clawix restart` | Restart the bridge daemon. |
| `clawix status` | Bridge state, port, paired-device count, app presence. |
| `clawix pair` | Re-print pairing QR + short code. |
| `clawix unpair` | Rotate pairing token + short code; every previously paired device must scan a fresh QR. |
| `clawix doctor` | Run a battery of health checks (codex, port, firewall, signature, plist, heartbeat…) and tell you what's wrong if anything. |
| `clawix logs [-f]` | Tail bridge logs. `-f` to follow. |
| `clawix install-app` | Download Clawix.app from the latest release and install it into `/Applications`. |
| `clawix uninstall` | Bootout the launchd agents and remove `~/.clawix/bin`. Add `--purge` to also wipe the pairing token. |

Flags supported across commands where it makes sense:

- `--json` — machine-readable output (`status`, `pair`, `doctor`).
- `--no-color` — disable ANSI colors. Honoured automatically when stdout is not a TTY or `NO_COLOR=1` is set.
- `--version`, `-v` — print version.
- `--help`, `-h` — print help.

## Diagnostics

When something looks off, run:

```bash
clawix doctor
```

It checks the things that go wrong in real life:

- macOS version (must be 14+)
- `codex` CLI on PATH
- Port `24080` free or held by our daemon (not by something else)
- Both binaries present and codesigned
- Launchd agent loaded and running
- Plist file syntactically valid
- LAN IPv4 detected
- Tailscale presence (info only)
- macOS Application Firewall not blocking incoming connections
- Pairing token + short code generated
- Daemon heartbeat fresh

Each check shows `●` ok, `⚠` warning, or `✗` failure with a specific suggested fix below it.

For automation, add `--json`.

## Coexistence with Clawix.app

If you also install the macOS app (`clawix install-app`), both surfaces register the same launchd agent label (`clawix.bridge`) and share the same `UserDefaults` suite for the pairing token. Whoever holds the agent slot serves; the other defers. You can install one, both, or neither and switch back and forth without re-pairing your phone.

The CLI does not require the GUI, and the GUI does not require the CLI.

## Files this package manages

```
~/.clawix/bin/clawix-bridge                     bridge daemon (signed)
~/.clawix/bin/clawix-menubar                     menu bar icon (signed)
~/.clawix/bin/manifest.json                      install metadata
~/.clawix/state/bridge-status.json               daemon heartbeat
~/Library/LaunchAgents/clawix.bridge.plist       daemon registration
~/Library/LaunchAgents/clawix.menubar.plist      menu bar registration
~/Library/Preferences/clawix.bridge.plist        pairing token + short code (shared with the GUI)
/tmp/clawix-bridge.{out,err}                    daemon logs
```

`clawix uninstall` cleans everything except the pairing token; `--purge` also wipes that.

## Privacy

Your bridge listens on your LAN (and on Tailscale, if you use it) and accepts connections from your iPhone directly. There is no relay server — yours or anyone else's. Your code never leaves the network you and your phone share.

## License

MIT.
