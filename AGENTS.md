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

## Feature flags: experimental hidden in release builds

Two opt-in tiers gate in-development surfaces: **Beta** and **Experimental**. The toggles live in Settings → General. Both default to OFF. The toggles, the underlying persistence and the user-visible card are **dev-only** — release builds (`swift build -c release`, i.e. anything `dev.sh` did not produce) ship without them.

Hard rules:

- The "Feature previews" card in Settings → General is wrapped in `#if DEBUG`. In a notarized binary the card does not render and the toggles are not user-controllable.
- `FeatureFlags.beta` and `FeatureFlags.experimental` are `@Published var` only inside `#if DEBUG`. Under `#else`, they are `let beta = false` / `let experimental = false` with no UserDefaults backing. A stale value persisted by an earlier dev build cannot leak into a release build because the persistence code does not exist there.
- `isVisible(_:)` keeps the same signature in both configurations. Call sites (`SidebarView`, `App`, `QuickAskController`, `AppState`, etc.) need no `#if DEBUG` of their own — in release the function returns `false` for any beta or experimental tier.
- This must stay **compile-time** enforced, not runtime config. Do not introduce a `UserDefaults` override, an Info.plist key, an environment variable or a launch argument that re-enables either flag in a release build. The contract is: notarized = stable surface only, no escape hatch.
- When promoting a feature out of beta/experimental, change its `tier` in `AppFeature.tier` to `.stable`. Do not "ship it via the experimental toggle" by flipping a default — the toggle is gone in release.

Auto-enforced via the `#if DEBUG` guards in `FeatureFlags.swift` and `SettingsView.swift`. If a contributor introduces a new toggle that should also be dev-only, follow the same pattern (compile-time guard around both the storage and the UI).

## Corner radius: always squircle (`.continuous`)

App-wide standard. Every corner radius is rendered with `style: .continuous` (Apple's superellipse). Never `.circular`, never the default style. The difference vs. `.circular` is subtle but cumulative: a `.continuous` app feels "pro", a `.circular` one feels amateur.

**Auto-enforced**: `dev.sh` runs a lint that fails the build if any of the following appear. If the lint fires, the build does not compile and the app is not relaunched.

The lint covers four rules:

- `RoundedRectangle(cornerRadius: X)` → always `RoundedRectangle(cornerRadius: X, style: .continuous)`. Lint A.
- `UnevenRoundedRectangle(...)` → always with `style: .continuous`. Lint D scans for `.continuous` within the 6 lines following the opening, so multi-line declarations work as long as `.continuous` shows up.
- `Path(roundedRect: r, cornerSize: s)` and `Path(roundedRect: r, cornerRadius: x)` default to `.circular`; pass `style: .continuous` explicitly. Lint D.
- `.clipShape(RoundedRectangle(...))` → same `.continuous` standard (lint A covers it because the underlying pattern is the same).
- **Forbidden**: SwiftUI's `.cornerRadius(X)` modifier. It clips circular by default. Replace with `.clipShape(RoundedRectangle(cornerRadius: X, style: .continuous))`. Lint B.
- **Forbidden**: `style: .circular` and `RoundedCornerStyle.circular` literals. Lint C.
- `Capsule()` and `Circle()` are out of scope (fully rounded by construction, no configurable radius).

Edge cases the lint does not cover, watch by hand:

- `NSBezierPath(roundedRect: rect, xRadius:, yRadius:)` (AppKit) has no squircle variant; it always draws circular. Allowed only when the radius is ≥ ~40% of the shorter side (effectively a capsule/pill, the visual delta is nil — e.g. the custom scrollbar thumb). For anything else, draw the shape with `Path` (SwiftUI) or `CGPath` with squircle, or replace with SwiftUI `RoundedRectangle`.
- `Image` with rounded corners via `.clipShape(...)` → the `clipShape` carries `RoundedRectangle(cornerRadius:style: .continuous)`. Lint A catches it.

When a new component draws its own radius (canvas, hand-painting in a `GeometryReader`, etc.) route it through `RoundedRectangle` or `Path(roundedRect:cornerSize:style: .continuous)`. Do not invent circular Bézier curves by hand.

## Segmented selectors: always `SlidingSegmented`

App-wide standard for any 2-N mutually-exclusive choice picker (e.g. "Used / Remaining", "Queue / Drive", "Inline / Detached", "STDIO / HTTP streaming", merge methods, transport modes). The canonical component lives in `macos/Sources/Clawix/SettingsView.swift` as `SlidingSegmented<T>` and is the only correct way to render this pattern.

What `SlidingSegmented` looks like:

- Outer container: `RoundedRectangle(cornerRadius: 13, style: .continuous)` with `Color.black.opacity(0.30)` fill and a 0.5pt `Color.white.opacity(0.10)` stroke.
- Indicator: a single `RoundedRectangle(cornerRadius: 10, style: .continuous)` filled `Color.white.opacity(0.10)`. There is exactly ONE indicator in the tree, positioned by `.offset` based on the selected index. There is no per-chip background that fades in/out.
- Inner radius is concentric to the outer (outer 13 − padding 3 = 10), so the highlight squircle nests visually inside the track squircle.
- Selected text: `Palette.textPrimary` weight `.medium`. Unselected: `Palette.textSecondary` weight `.regular`. Same font size across both.

Animation:

- The indicator slides between options with `.snappy(duration: 0.32, extraBounce: 0)` applied as `.animation(animation, value: selection)` directly on the indicator's offset modifier. Quick, no bounce, no overshoot.
- **Forbidden**: `matchedGeometryEffect` for the indicator. It's unreliable when the binding writes through `@AppStorage` on macOS (the indicator stops sliding and snaps). The "single indicator with `.offset`" pattern is the only reliable approach.
- **Forbidden**: `withAnimation` inside the chip Button action. The animation lives on the indicator view, driven by `value: selection`, so the curve fires whether the change comes from a tap, a hotkey, or a `@AppStorage` round-trip.

Sizing:

- Height fixed (default 30, override via `height:`); width comes from the parent. In a row layout (label + Spacer + segmented) pin it with `.frame(width: 190)` (or any width that fits the longest label without truncating). When the selector should fill its container — full-width form fields like MCP transport — leave the width unset and the inner `GeometryReader` handles the math.
- All chips have equal width by construction. If labels differ in length, size the segmented to the longest one — never let one chip be visibly wider than another.

Persistence:

- Whenever a segmented choice should survive across app launches (display modes, view filters, preferred transports, anything the user has expressed a preference for), back the binding with `@AppStorage` and a stable key prefixed `clawix.<area>.<setting>` (e.g. `"clawix.settings.usage.displayMode"`). Use a `RawRepresentable<String>` enum so SwiftUI serializes it directly. **Default**: pick the option a first-time user is most likely to want — usually the more informative or less destructive one.

When migrating existing selectors:

- `SegmentedRow<T>` (settings row pattern with label + detail on the left, segmented on the right) already wraps `SlidingSegmented` internally. New rows of this shape should use `SegmentedRow`, not roll their own.
- Any custom segmented control that uses `Capsule()` for the indicator, multiple per-chip backgrounds with `if isOn { ... }`, or `matchedGeometryEffect` — replace it with `SlidingSegmented`. Don't keep the old shape "for now".
- Multi-option pickers that need decorative icons per option (e.g. theme switcher: sun/moon/laptop) are not yet first-class in `SlidingSegmented`. When you need that, extend `SlidingSegmented` with optional icon support rather than reintroducing the per-chip-capsule pattern.

`Picker(selection:)` with `.pickerStyle(.segmented)` is forbidden anywhere in the app — it ignores the squircle convention and the curve doesn't match. Always `SlidingSegmented`.

## Custom icons (project canon)

The app ships its own hand-drawn icons (Canvas / Path / Shape) for every glyph that has a strong identity in the UI: documents, folders, terminal, globe, mic, search, branch, pin, archive, copy, pencil, branch-arrows, sidebar toggle, etc. They live in `macos/Sources/Clawix/` next to the rest of the views and are exported as plain `View` types (e.g. `FileChipIcon`, `TerminalIcon`, `GlobeIcon`, `FolderOpenIcon`, `MicIcon`, `SearchIcon`, `CursorIcon`).

**Before adding any `Image(systemName:)`, check whether a custom equivalent already exists.** SF Symbols look generic next to the rest of the chrome and break visual consistency. The canonical map (extend it as new icons are added):

| Concept            | Custom view                          | File                          |
|--------------------|--------------------------------------|-------------------------------|
| Document / file    | `FileChipIcon`                       | `FileChipIcon.swift`          |
| Folder (open)      | `FolderOpenIcon`                     | `FolderOpenIcon.swift`        |
| Folder (closed)    | `FolderClosedIcon`                   | `FolderOpenIcon.swift`        |
| Folder add         | `FolderAddIcon`                      | `FolderOpenIcon.swift`        |
| Folder stack       | `FolderStackIcon`                    | `FolderStackIcon.swift`       |
| Branch (git)       | `BranchIcon`                         | `FolderOpenIcon.swift`        |
| Pin                | `PinIcon`                            | `FolderOpenIcon.swift`        |
| Archive / unarchive| `ArchiveIcon` / `UnarchiveIcon`      | `FolderOpenIcon.swift`        |
| Globe / web        | `GlobeIcon`                          | `GlobeIcon.swift`             |
| Search             | `SearchIcon`                         | `SearchIcon.swift`            |
| Mic                | `MicIcon`                            | `MicIcon.swift`               |
| Terminal           | `TerminalIcon`                       | `TerminalIcon.swift`          |
| Cursor (text)      | `CursorIcon`                         | `CursorIcon.swift`            |
| Copy               | `CopyIconView`, `CopyIconViewSquircle` | `ChatView.swift` (legacy spot, ideally `CopyIcon.swift`) |
| Pencil / edit      | `PencilIconView`                     | `ChatView.swift` (legacy spot, ideally `PencilIcon.swift`) |
| Branch arrows      | `BranchArrowsIconView`               | `ChatView.swift` (legacy spot) |
| Sidebar toggle     | `SidebarToggleIcon`                  | `ContentView.swift` (legacy spot) |
| Compose new chat   | `ComposeIcon` (`Shape`)              | `SidebarView.swift` (legacy spot) |
| Pinned (sidebar)   | `PinnedIcon` (`Shape`)               | `SidebarView.swift` (legacy spot) |
| Funnel (filter)    | `OrganizeFunnelIcon`                 | `SidebarView.swift` (legacy spot) |
| Expand (settings)  | `ExpandIconButton` (composite)       | `SettingsView.swift` (legacy spot) |
| Collapse / expand corners | `CornerBracketsIcon`           | `CornerBracketsIcon.swift`         |
| Brand logo (app icon)     | `ClawixLogoIcon`, `ClawixLogoTemplateImage` | `ClawixLogoIcon.swift`             |

### Brand logo

The Clawix mark itself is a custom shape too. Master vector lives at `brand/clawix-logo.svg` at the repo root: a single `evenodd`-filled `<path>` in a `100x100` viewBox. Geometry: outer iOS-style continuous-corner squircle (3 cubic beziers per corner with the Apple app-icon magic numbers, corner extent `38`), visor cut out (smaller squircle, corner extent `22`), two squircle eyes filled back in. `currentColor` so the consumer decides the tint.

In code, the same path is reproduced in `macos/Sources/Clawix/ClawixLogoIcon.swift`. Two entry points:

- `ClawixLogoIcon(size:)` — SwiftUI `View`, fills with `.primary`. Use anywhere inside the SwiftUI hierarchy (splash, about screen, empty states, settings).
- `ClawixLogoTemplateImage.make(size:)` — flattens the shape into an `NSImage` with `isTemplate = true`. Required for `MenuBarExtra` because its label slot does not render arbitrary SwiftUI `Shape`s reliably (renders as an empty hole). AppKit applies the menu bar's foreground tint automatically when the image is template.

Hard rules:

- The brand mark is `ClawixLogoIcon` / `ClawixLogoTemplateImage`. Never re-derive the path inline somewhere else, never use `Image(systemName:)` as a stand-in.
- When the SVG master changes (`brand/clawix-logo.svg`), update the path in `ClawixLogoIcon.swift` to match. The two are intentionally redundant: the SVG is the human-editable source, the Swift path is the runtime rendering. If the iOS app eventually ships, it imports `brand/clawix-logo.svg` (or replicates the same path natively); the master in `brand/` stays canonical.
- For places that need the `.icns` / iOS asset catalog renders, those are produced from the same master (currently the `.icns` lives in `macos/Sources/Clawix/Resources/Clawix.icns`). When updating the brand, regenerate both the in-code path and the rasterized asset; do not let them drift.

Hard rules:

- **One file per icon, named after it.** New icons go in their own `XxxIcon.swift` file. Do not paste a Canvas / Path icon body into a feature view file. Existing icons that live in feature files (the "legacy spot" rows above) are pending extraction; treat them as an exception, not a precedent.
- **Never duplicate a custom icon's body across files.** If you need the same glyph in a new place, import the existing struct. If two places need slightly different sizes / colors, parametrize the existing struct with `var size: CGFloat`, `var color: Color`, etc., do NOT copy/paste.
- **Before reaching for any system icon, check the table above and grep the project for `<concept>Icon`.** When the glyph genuinely has no project-custom equivalent, the canonical fallback is a **Lucide-sourced icon** (see "Lucide-sourced icons" below), NOT an SF Symbol.
- **The model behind this rule**: a custom icon is the project's design DNA. If you swap one for a generic icon the screen feels "off" even if you can't pinpoint why. The user notices.
- When in doubt about whether a glyph deserves a custom icon, **ask before drawing**. Hand-drawing an icon that already has a system equivalent and lives nowhere else in the app is wasted work.

## Lucide-sourced icons (project canon, fallback for non-custom glyphs)

When a glyph has no project-custom icon (the table above), the fallback is **Lucide** (https://lucide.dev), not SF Symbols. Lucide has a clean, restrained outline language that sits next to the custom Path-based icons without breaking visual consistency; SF Symbols feel generic next to the rest of the chrome.

Hard rules:

