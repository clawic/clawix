<p align="center">
  <img src="./media/readme-banner.webp" alt="Clawix, the open-source interface for agents">
</p>

# Clawix

> [!WARNING]
> Clawix is currently experimental, pre-beta software. Expect severe breaking changes without notice, including changes to UI, configuration, persisted preferences and the integration contract with the underlying CLI.
>
> Do not use Clawix in production. Do not connect it to sensitive systems, real user data, paid APIs, security-critical services, or important integrations.
>
> Use it only for local evaluation, ideally on an isolated machine, VM, or sandboxed environment. Assume things can fail, data can break, and migrations may not exist yet.

Clawix is the native human interface and embedded signed host for ClawJS/Claw. It owns the app UI, visual projections, approvals, and host identity, while ClawJS/Claw owns canonical framework contracts, storage, domain APIs, and the public `claw` CLI. Codex data can be mirrored as an external read-only source, but it is not Clawix's canonical storage model. The macOS app ships today, with an iOS companion on the way.

This repository is a monorepo. Platform clients live at the root under `macos/` and `ios/`, with shared Swift packages under `packages/`.

## macOS app

<p align="center">
  <img src="./media/readme-mac-mockup.webp" alt="Clawix on macOS, chat with file references and composer">
</p>

Native SwiftUI client. Project sidebar with chat history and inline search, file references for `apply_patch` operations, model picker, native chrome, signed and notarized builds with [Sparkle](https://sparkle-project.org) self-updates. Source under [`macos/`](./macos).

## iOS app

<p align="center">
  <img src="./media/readme-mobile-mockup.webp" alt="Clawix iOS companion, projects sidebar and chat detail" width="640">
</p>

A native iOS companion is on the way. It pairs with the Mac over a local bridge so projects, chats and streaming history stay in sync. Pick up a thread on the phone, keep typing on the Mac. Source under [`ios/`](./ios).

## Download

Signed and notarized DMG builds are published on the [GitHub Releases page](https://github.com/clawic/clawix/releases). The app self-updates via [Sparkle](https://sparkle-project.org); when a new release is available a small "Update" chip appears in the top bar.

## Build

Requirements: macOS 14+, Swift 5.9+, Xcode Command Line Tools.

```
bash macos/scripts/dev.sh
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
SIGN_IDENTITY="..." BUNDLE_ID="..." bash macos/scripts/dev.sh
```

### Release

```
bash macos/scripts/build_app.sh
```

Builds `macos/build/Clawix.app`. Uses the same `SIGN_IDENTITY` / `BUNDLE_ID` resolution as `dev.sh`.

For notarized DMG distribution use `macos/scripts/build_release_app.sh`, which reads `DEVELOPER_ID_IDENTITY` from the environment and applies hardened-runtime per-component signing in the order Sparkle requires. The full release pipeline (notarization, DMG, appcast generation, GitHub release upload) is private to the maintainer and not part of this public tree.

The marketing version lives in [`macos/VERSION`](./macos/VERSION). It is the single source of truth: build scripts read it at compile time and inject it into `CFBundleShortVersionString`.

## Privacy guarantee for contributors

This repository never contains the maintainer's real codesign identity, Apple Team ID, or bundle id. They live in a `.signing.env` file kept outside the public tree. The hygiene gate (`macos/scripts/public_hygiene_check.sh`) blocks publishing if any of those values, or a `.signing.env`, leak into the public source. See [`AGENTS.md`](./AGENTS.md) and [`docs/host-ownership.md`](./docs/host-ownership.md) for the full set of rules contributors are expected to follow.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). The repository conventions (corner-radius canon, dropdown style, hygiene gate, signing rules) live in [`AGENTS.md`](./AGENTS.md), with framework/host ownership in [`docs/host-ownership.md`](./docs/host-ownership.md).

## License

The source code and documentation are licensed under [MIT](./LICENSE).

The Clawix name, logo, app icon, custom icons, custom typefaces, SVG marks,
brand assets, screenshots, marketing assets, and visual identity are reserved
and are not licensed under MIT. See [NOTICE](./NOTICE) and
[TRADEMARKS.md](./TRADEMARKS.md).

## Star History

<a href="https://www.star-history.com/?repos=clawic%2Fclawix&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=clawic/clawix&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=clawic/clawix&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=clawic/clawix&type=date&legend=top-left" />
 </picture>
</a>
