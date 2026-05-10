# Clawix

Monorepo for the Clawix project. Native clients for the [`codex`](https://github.com/openai/codex) CLI. The repo hosts platform clients at the top level, with shared Swift packages under `packages/`.

## Repository layout

```
macos/          # macOS client (SwiftUI).
ios/            # iOS client.
packages/       # Shared Swift packages.
cli/            # npm CLI surface.
```

Each app is autonomous: its own `Package.swift` (or Xcode project), its own scripts, its own bundle id. The only repo-wide assets are the brand, this `CLAUDE.md`, and the hygiene gate run before publishing.

## Build (macOS app)

Requirements: macOS 14+, Swift 5.9+, Xcode Command Line Tools.

### Dev loop

```
bash macos/scripts/dev.sh
```

Compiles debug, kills the previous instance, relaunches. By default the build is ad-hoc-signed and bundled as `com.example.clawix.desktop` (a placeholder); macOS will re-prompt for permissions (Desktop folder, microphone, etc.) on every relaunch.

### Stable signing (recommended)

Create a `.signing.env` file at the repo root (or any parent directory) with your values:

```
SIGN_IDENTITY="<codesign identity>"
BUNDLE_ID="com.yourdomain.clawix"
```

`dev.sh` and `build_app.sh` source it automatically. Environment variables override the file. With a stable identity + bundle id, macOS persists TCC grants between rebuilds. List your codesign identities with `security find-identity -v -p codesigning`.

### Release

```
bash macos/scripts/build_app.sh
```

Produces `macos/build/Clawix.app`. Same `SIGN_IDENTITY` / `BUNDLE_ID` resolution as `dev.sh`.

## Hygiene gate (publication)

Before publishing anything, this must pass:

```
bash macos/scripts/public_hygiene_check.sh
```

It scans the entire repo publish surface (root docs, `macos/`, `ios/`, `packages/*/` and `cli/`) for: developer-machine paths, secret-looking literals, hex digests, hard-coded codesign material, Apple Team IDs and committed `.signing.env` files. The npm CLI under `cli/` is part of the same publish surface, so its source ships under the same blacklist.

## Commits

Conventional commits: `type(scope): description`. Types: `feat`, `fix`, `style`, `chore`, `refactor`, `docs`, `test`. Lowercase, no trailing period.

Use a platform prefix in the scope when the change is specific to one app:

- `feat(mac/composer): add model menu popup`
- `fix(ios/onboarding): prevent loop when token expires`
- `chore(repo): update hygiene globs`

Rules:

- One change per commit. Do not bundle unrelated changes.
- Only the changes from the current session; do not sweep unrelated edits in.

## Code style

- **Language: English.** Every identifier, every comment, every doc comment, every commit message, every script log line, every user-visible string in this repo is written in English. No Spanish (or any other language) in code, comments or commits, even if the contributor's working language is different. This is a public repo and the default reader is an English-speaking contributor.
- **Comments: minimal.** Default to writing none. Well-named identifiers explain WHAT the code does. Only add a comment when the WHY is non-obvious: a hidden constraint, a workaround for a specific bug, an invariant that would surprise a reader. One short line, not a paragraph. Never reference the current task or the PR ("added for X", "fixes Y") since that belongs in the commit message and rots over time.

## Hard privacy rules (important for any contributor and any AI agent)

This repository never contains the maintainer's real codesign identity, Apple Team ID, or bundle id. They live in a `.signing.env` file kept outside the public tree. When contributing code:

- **Do not hard-code** a `CFBundleIdentifier`, a `DEVELOPMENT_TEAM`, or a codesign identity literal anywhere in this repository. Those values are read at runtime from `.signing.env` or environment variables.
- **Do not commit** the file `.signing.env`. It is in `.gitignore` and `macos/scripts/public_hygiene_check.sh` fails the build if a copy is detected inside the public tree.
- **Do not introduce** an `Info.plist` with a literal bundle id. The plist is generated in `build_app.sh` interpolating `${BUNDLE_ID}`.
- **Do not add** an Xcode project with a concrete development team value. Leave the field empty; the script supplies it from the environment.

If you need to expose a new piece of local config (another identifier, another flag), add the variable to the scripts and document it in `.signing.env.example`. Never the other way around.

---

# macOS app · `macos/`

Native macOS client (SwiftUI) for the `codex` CLI. The visible app is a frontend. Runtime ownership is split by mode:

- Normal in-process mode: the app reads `~/.codex/auth.json`, runs the `codex` binary for login/logout, and connects to the JSON-RPC app-server the CLI exposes for threads, messages and events.
- Background bridge mode: a bundled `clawix-bridged` helper owns the Codex app-server connection and the local bridge. The Mac app connects back to that daemon over loopback instead of starting its own backend/bridge. iOS scans the daemon QR/token and talks to the same daemon, so Mac and iOS share one runtime owner.

Do not reintroduce a second GUI-owned bridge/backend when background bridge mode is enabled. Any iOS-visible runtime feature should be implemented on the daemon bridge surface first, then consumed by the Mac app and iOS clients.

## Layout

- `macos/Package.swift`: Swift Package, target `Clawix`, macOS 14+. One external dependency: [Sparkle 2](https://sparkle-project.org) for in-app updates.
- `macos/VERSION`: single source of truth for the marketing version. `dev.sh` and the release scripts read it via `_emit_version.sh` and inject it into the generated Info.plist.
- `macos/Sources/Clawix/`: SwiftUI source.
- `macos/Sources/Clawix/AppVersion.swift`: reads `CFBundleShortVersionString` / `CFBundleVersion` at runtime so the app reports the version it was actually compiled with.
- `macos/Sources/Clawix/Updater/UpdaterController.swift`: thin wrapper around `SPUStandardUpdaterController`. Drives the "Update" chip in the top bar.
- `macos/Sources/Clawix/DaemonBridgeClient.swift`: loopback client used by the Mac app when the background bridge daemon is active.
- `macos/Helpers/Bridged/`: Swift helper executable that runs as the background bridge daemon and owns the Codex runtime connection in background bridge mode.
- `packages/ClawixCore/`: shared bridge wire protocol.
- `packages/ClawixEngine/`: shared bridge server/session/pairing runtime.
- `macos/scripts/dev.sh`: dev launcher (build + relaunch). Copies Sparkle.framework into the bundle and signs deep.
- `macos/scripts/build_app.sh`: release-only `.app` builder (single identity, deep sign).
- `macos/scripts/build_release_app.sh`: notarization-ready builder. Reads `DEVELOPER_ID_IDENTITY` from env and applies per-component hardened-runtime signing in the order Sparkle requires.
- `macos/scripts/public_hygiene_check.sh`: hygiene gate scanned across the whole repo.

The full release orchestration (notarytool, DMG packaging, Sparkle EdDSA signing, appcast regeneration, GitHub Release upload) is intentionally NOT in this public tree. It lives in the maintainer's private workspace and consumes `build_release_app.sh` plus credentials from `.signing.env`.

## Background bridge daemon architecture

The bridge daemon is the canonical host for cross-device runtime work. It starts the Codex app-server over stdio, keeps the bridge listening on its configured port, and publishes the same wire protocol used by iOS. In daemon mode, the Mac app is just another authenticated desktop client over `127.0.0.1`.

Required invariants:

- One runtime owner. When background bridge mode is active, the Mac app must not also bootstrap its own Codex backend or publish another `BridgeServer`.
- Shared pairing. The QR payload, bearer token and port must point to the daemon, not to a GUI-local server.
- Shared state. Chat list, history hydration, new chat creation, prompt sending, streaming updates and archive state flow through the daemon so iOS and Mac observe the same source of truth.
- Daemon-first expansion. If a new bridge feature needs to work on iOS, add daemon support and E2E coverage for that frame before wiring UI clients to it.
- No real-cost validation by default. E2E tests should use isolated fake backends unless the user explicitly approves a real prompt. Real host validation may authenticate and list chats, but must not send real prompts without confirmation.
