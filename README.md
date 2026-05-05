<p align="center">
  <img src="./media/readme-banner.webp" alt="Clawix — Native macOS client for Codex">
</p>

# Clawix

> [!WARNING]
> Clawix is currently experimental, pre-beta software. Expect severe breaking changes without notice, including changes to UI, configuration, persisted preferences and the integration contract with the underlying CLI.
>
> Do not use Clawix in production. Do not connect it to sensitive systems, real user data, paid APIs, security-critical services, or important integrations.
>
> Use it only for local evaluation, ideally on an isolated machine, VM, or sandboxed environment. Assume things can fail, data can break, and migrations may not exist yet.

Clawix is a native macOS client (SwiftUI) for the [`codex`](https://github.com/openai/codex) CLI. It reads `~/.codex/auth.json`, drives `codex login` / `logout`, and connects to the JSON-RPC app-server the CLI exposes for threads, messages, and events.

This repository is a monorepo. Apps live under `apps/`:

- `apps/macos/` — macOS client (this is what currently exists).
- `apps/ios/` — iOS client (placeholder for a future port).

## Download

Signed and notarized DMG builds are published on the [GitHub Releases page](https://github.com/clawic/clawix/releases). The app self-updates via [Sparkle](https://sparkle-project.org); when a new release is available a small "Update" chip appears in the top bar.

## Build

Requirements: macOS 14+, Swift 5.9+, Xcode Command Line Tools.

```
bash apps/macos/scripts/dev.sh
```

Compiles debug, kills the previous instance, relaunches. Window position, size and the sidebar prefs persist via `UserDefaults`. With no extra config, the build is ad-hoc-signed and bundled as `com.example.clawix.desktop` (a placeholder); macOS will re-prompt for permissions (Desktop folder, microphone, etc.) on every relaunch.

### Stable signing (recommended for daily dev)

Create a `.signing.env` file at the repo root (or any parent directory) with your values:

```
SIGN_IDENTITY="<codesign identity>"
BUNDLE_ID="com.yourdomain.clawix"
```

Both `dev.sh` and `build_app.sh` source it automatically. With a stable identity + bundle id, macOS remembers the TCC grants between rebuilds and stops re-prompting. The file is in `.gitignore`.

List your codesign identities with `security find-identity -v -p codesigning`. Any valid macOS codesign identity works.

Environment variables also work and override the file:

```
SIGN_IDENTITY="..." BUNDLE_ID="..." bash apps/macos/scripts/dev.sh
```

### Release

```
bash apps/macos/scripts/build_app.sh
```

Builds `apps/macos/build/Clawix.app`. Uses the same `SIGN_IDENTITY` / `BUNDLE_ID` resolution as `dev.sh`.

For notarized DMG distribution use `apps/macos/scripts/build_release_app.sh`, which reads `DEVELOPER_ID_IDENTITY` from the environment and applies hardened-runtime per-component signing in the order Sparkle requires. The full release pipeline (notarization, DMG, appcast generation, GitHub release upload) is private to the maintainer and not part of this public tree.

The marketing version lives in [`apps/macos/VERSION`](./apps/macos/VERSION). It is the single source of truth: build scripts read it at compile time and inject it into `CFBundleShortVersionString`.

## Privacy guarantee for contributors

This repository never contains the maintainer's real codesign identity, Apple Team ID, or bundle id. They live in a `.signing.env` file kept outside the public tree. The hygiene gate (`apps/macos/scripts/public_hygiene_check.sh`) blocks publishing if any of those values, or a `.signing.env`, leak into the public source. See [`CLAUDE.md`](./CLAUDE.md) for the full set of rules contributors are expected to follow.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). The repository conventions (corner-radius canon, dropdown style, hygiene gate, signing rules) live in [`CLAUDE.md`](./CLAUDE.md).

## License

[MIT](./LICENSE).
