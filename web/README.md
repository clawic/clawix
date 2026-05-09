# Clawix Web

Web client for Clawix. Third bridge client (after the macOS GUI and the iOS companion) that talks to the local `clawix-bridged` daemon over WebSocket.

## Architecture

The web client is a pure SPA. It does NOT run Codex itself; it pairs with the user's `clawix-bridged` daemon and renders the same data the macOS app renders. Secrets and Codex auth never leave the user's Mac.

The daemon serves the static bundle at `http://localhost:7778/` and exposes the WebSocket at `/ws`. A loopback-only `/pairing/qr.json` endpoint lets the SPA self-configure when opened from the same machine.

For remote access, the user opens `http://<mac>.local:7778` (mDNS) or the Tailscale IP from another device and pastes the short code.

## Development

```bash
pnpm install
pnpm dev    # Vite dev server on http://localhost:5173, proxies /ws -> daemon
```

The daemon must be running:

```bash
# from the workspace root
bash dev.sh
```

For embedded mode (the daemon serves the built bundle), run from the workspace root:

```bash
pnpm --filter @clawix/web build
bash dev.sh   # restarts daemon, web is at http://localhost:7778
```

## Layout

```
src/
  bridge/    Wire types (Zod), frame codec, WebSocket client, Zustand store
  screens/   Per-feature screens: chat, sidebar, settings, secrets, ...
  components/ Squircle, ThinScrollbar, SlidingSegmented, MenuPopup, GlassPill
  icons/     SVG component icons (FileChip, FolderOpen, Mic, Bot, ...)
  theme/     Design tokens
  lib/       Argon2id wrapper, reconnect, utilities
scripts/
  check-wire-parity.ts   CI gate vs BridgeModels.swift
tests/
  unit/      Vitest, frame fixtures
  e2e/       Playwright vs mock daemon
```

## Wire protocol

Mirrors `packages/ClawixCore/Sources/ClawixCore/BridgeModels.swift` and `BridgeProtocol.swift`. Schema version is read from `bridgeSchemaVersion` (currently `5`). When the daemon advertises a higher version, the SPA shows an "Update Clawix" empty state.

## Tests

```bash
pnpm test        # Vitest
pnpm test:e2e    # Playwright (requires the mock daemon, see tests/e2e/README.md)
pnpm check:wire  # Compares Zod schemas against Swift models
```
