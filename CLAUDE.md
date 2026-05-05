# Clawix

Monorepo for the Clawix project. Native clients for the [`codex`](https://github.com/openai/codex) CLI. The repo is designed to host several apps (macOS, iOS, …), each in its own subdirectory under `apps/`.

## Repository layout

```
apps/
  macos/        # macOS client (SwiftUI), exists.
  ios/          # iOS client (placeholder, not implemented yet).
```

Each app is autonomous: its own `Package.swift` (or Xcode project), its own scripts, its own bundle id. The only repo-wide assets are the brand, this `CLAUDE.md`, and the hygiene gate run before publishing.

## Build (macOS app)

Requirements: macOS 14+, Swift 5.9+, Xcode Command Line Tools.

### Dev loop

```
bash apps/macos/scripts/dev.sh
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
bash apps/macos/scripts/build_app.sh
```

Produces `apps/macos/build/Clawix.app`. Same `SIGN_IDENTITY` / `BUNDLE_ID` resolution as `dev.sh`.

## Hygiene gate (publication)

Before publishing anything, this must pass:

```
bash apps/macos/scripts/public_hygiene_check.sh
```

It scans the entire repo (root + `apps/*/Sources` + `apps/*/scripts` + `apps/*/Resources`) for: developer-machine paths, secret-looking literals, hex digests, hard-coded codesign material, Apple Team IDs and committed `.signing.env` files. When new apps are added under `apps/`, their tree is picked up automatically because the gate iterates `apps/*/`.

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
- **Do not commit** the file `.signing.env`. It is in `.gitignore` and `apps/macos/scripts/public_hygiene_check.sh` fails the build if a copy is detected inside the public tree.
- **Do not introduce** an `Info.plist` with a literal bundle id. The plist is generated in `build_app.sh` interpolating `${BUNDLE_ID}`.
- **Do not add** an Xcode project with a concrete development team value. Leave the field empty; the script supplies it from the environment.

If you need to expose a new piece of local config (another identifier, another flag), add the variable to the scripts and document it in `.signing.env.example`. Never the other way around.

---

# macOS app · `apps/macos/`

Native macOS client (SwiftUI) for the `codex` CLI. The visible app is a frontend. Runtime ownership is split by mode:

- Normal in-process mode: the app reads `~/.codex/auth.json`, runs the `codex` binary for login/logout, and connects to the JSON-RPC app-server the CLI exposes for threads, messages and events.
- Background bridge mode: a bundled `clawix-bridged` helper owns the Codex app-server connection and the local bridge. The Mac app connects back to that daemon over loopback instead of starting its own backend/bridge. iOS scans the daemon QR/token and talks to the same daemon, so Mac and iOS share one runtime owner.

Do not reintroduce a second GUI-owned bridge/backend when background bridge mode is enabled. Any iOS-visible runtime feature should be implemented on the daemon bridge surface first, then consumed by the Mac app and iOS clients.

## Layout

- `apps/macos/Package.swift`: Swift Package, target `Clawix`, macOS 14+. One external dependency: [Sparkle 2](https://sparkle-project.org) for in-app updates.
- `apps/macos/VERSION`: single source of truth for the marketing version. `dev.sh` and the release scripts read it via `_emit_version.sh` and inject it into the generated Info.plist.
- `apps/macos/Sources/Clawix/`: SwiftUI source.
- `apps/macos/Sources/Clawix/AppVersion.swift`: reads `CFBundleShortVersionString` / `CFBundleVersion` at runtime so the app reports the version it was actually compiled with.
- `apps/macos/Sources/Clawix/Updater/UpdaterController.swift`: thin wrapper around `SPUStandardUpdaterController`. Drives the "Update" chip in the top bar.
- `apps/macos/Sources/Clawix/DaemonBridgeClient.swift`: loopback client used by the Mac app when the background bridge daemon is active.
- `apps/macos/Helpers/Bridged/`: Swift helper executable that runs as the background bridge daemon and owns the Codex runtime connection in background bridge mode.
- `apps/shared/ClawixCore/`: shared bridge wire protocol.
- `apps/shared/ClawixEngine/`: shared bridge server/session/pairing runtime.
- `apps/macos/scripts/dev.sh`: dev launcher (build + relaunch). Copies Sparkle.framework into the bundle and signs deep.
- `apps/macos/scripts/build_app.sh`: release-only `.app` builder (single identity, deep sign).
- `apps/macos/scripts/build_release_app.sh`: notarization-ready builder. Reads `DEVELOPER_ID_IDENTITY` from env and applies per-component hardened-runtime signing in the order Sparkle requires.
- `apps/macos/scripts/public_hygiene_check.sh`: hygiene gate scanned across the whole repo.

The full release orchestration (notarytool, DMG packaging, Sparkle EdDSA signing, appcast regeneration, GitHub Release upload) is intentionally NOT in this public tree. It lives in the maintainer's private workspace and consumes `build_release_app.sh` plus credentials from `.signing.env`.

## Background bridge daemon architecture

The bridge daemon is the canonical host for cross-device runtime work. It starts the Codex app-server over stdio, keeps the bridge listening on its configured port, and publishes the same wire protocol used by iOS. In daemon mode, the Mac app is just another authenticated desktop client over `127.0.0.1`.

Required invariants:

- One runtime owner. When background bridge mode is active, the Mac app must not also bootstrap its own Codex backend or publish another `BridgeServer`.
- Shared pairing. The QR payload, bearer token and port must point to the daemon, not to a GUI-local server.
- Shared state. Chat list, history hydration, new chat creation, prompt sending, streaming updates and archive state flow through the daemon so iOS and Mac observe the same source of truth.
- Daemon-first expansion. If a new bridge feature needs to work on iOS, add daemon support and E2E coverage for that frame before wiring UI clients to it.
- No real-cost validation by default. E2E tests should use isolated fake backends unless the user explicitly approves a real prompt. Real host validation may authenticate and list chats, but must not send real prompts without confirmation.

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

## Custom icons (project canon)

The app ships its own hand-drawn icons (Canvas / Path / Shape) for every glyph that has a strong identity in the UI: documents, folders, terminal, globe, mic, search, branch, pin, archive, copy, pencil, branch-arrows, sidebar toggle, etc. They live in `apps/macos/Sources/Clawix/` next to the rest of the views and are exported as plain `View` types (e.g. `FileChipIcon`, `TerminalIcon`, `GlobeIcon`, `FolderOpenIcon`, `MicIcon`, `SearchIcon`, `CursorIcon`).

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

Hard rules:

- **One file per icon, named after it.** New icons go in their own `XxxIcon.swift` file. Do not paste a Canvas / Path icon body into a feature view file. Existing icons that live in feature files (the "legacy spot" rows above) are pending extraction; treat them as an exception, not a precedent.
- **Never duplicate a custom icon's body across files.** If you need the same glyph in a new place, import the existing struct. If two places need slightly different sizes / colors, parametrize the existing struct with `var size: CGFloat`, `var color: Color`, etc., do NOT copy/paste.
- **Before reaching for `Image(systemName: "…")`, check the table above and grep the project for `<concept>Icon`.** Only fall back to SF Symbols when the glyph genuinely has no identity (caret chevrons, generic placeholders, OS-level concepts like `arrow.up.right.square`). When you do use SF Symbols, keep them tonally aligned with the surrounding custom icons (`Color(white: 0.55)`-`0.86`, hairline weights).
- **The model behind this rule**: a custom icon is the project's design DNA. If you swap one for an SF Symbol the screen feels "off" even if you can't pinpoint why. The user notices.
- When in doubt about whether a glyph deserves a custom icon, **ask before drawing**. Hand-drawing an icon that already has a system equivalent and lives nowhere else in the app is wasted work.

## Dropdowns / popups / context menus (project canon)

The composer's model selector (`ModelMenuPopup` in `ComposerView.swift`) is the **visual reference** for any dropdown, popover-style menu, edit menu or context menu. Anything new and anything retroactive should match it.

Chrome:

- Background: `RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.135))`.
- Border: `.stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)` (0.10 alpha, 0.5 px). Hairline, almost invisible.
- Shadow: `.shadow(color: .black.opacity(0.40), radius: 18, x: 0, y: 10)`.
- Container vertical padding: `6 pt`.
- Canonical helper: `.menuStandardBackground()` in `ContentView.swift`. **Use it always**, do not re-create the rectangle by hand.

Rows:

- Padding: `.padding(.horizontal, 14).padding(.vertical, 7)`. Compact, NOT 10/8 nor 10/10.
- Text: `font(.system(size: 13.5))`, color `Color(white: 0.94)`.
- Icons: `font(.system(size: 13))` (14 if the row is heavy), color `Color(white: 0.86)`, fixed width `frame(width: 18, alignment: .center)` so columns align.
- Subtitles, shortcuts, trailing chevrons: `Color(white: 0.55)`, sizes 11–12.
- Hover: NOT a full-bleed background. Use the `MenuRowHover(active: hovered)` helper. It is a `RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)).padding(.horizontal, 5)` that breathes towards the menu's edges. For rows highlighted because their submenu is open, raise to `0.08`.
- Selection check: `font(.system(size: 11, weight: .semibold))`, color `Color(white: 0.94)`.

Opening + animation:

- Anchoring: `anchorPreference` + `overlayPreferenceValue` (NOT SwiftUI `.popover`). `.popover` adds the system arrow chrome and breaks the look. Canonical pattern in `ComposerView.swift` for the model selector.
- Position: anchored from above just below the trigger. `alignmentGuide(.top) { d in d[.bottom] - buttonFrame.minY + 6 }` to hang 6 pt below; `alignmentGuide(.leading)` to align to the trigger (or to the right edge if the menu is wider).
- Entry transition: `.transition(.softNudge(y: 4))` (defined in `ComposerView.swift`). Side submenus: `.transition(.softNudge(x: -4))`. Do NOT use `.opacity.combined(with: .scale)`.
- Easing: `.animation(.easeOut(duration: 0.20), value: <openState>)` on the container.
- Outside click: `.background(MenuOutsideClickWatcher(isPresented: $isOpen))` inside the menu so it closes on outside click.

What to avoid:

- `.popover(isPresented:arrowEdge:)` with system chrome.
- Full-bleed hover backgrounds (highlights must inset from the menu edge).
- Heavy borders `lineWidth: 1` with `Color.white.opacity(0.08)` or similar; always `Palette.popupStroke` with `Palette.popupStrokeWidth`.
- `cornerRadius` 14/16; the standard is 12.
- Tall rows (vertical 10+); compact at 7.

Constants and helpers already available (in `ContentView.swift`):

- `enum MenuStyle` with all sizes, colors and animation.
- `extension View { func menuStandardBackground() }` for the container.
- `struct MenuRowHover` for the hover highlight.
- `extension AnyTransition { static func softNudge(x:y:) }` (in `ComposerView.swift`).

Before adding a new dropdown, look at `ModelMenuPopup` and replicate its structure. If the behavior differs (side submenu, sectioned with header, divider), copy the building blocks `ModelMenuHeader`, `ModelMenuDivider`, `ModelMenuCheckRow`, `ModelMenuChevronRow`, `ModelMenuDescriptionRow` or build a new one with the same paddings and `MenuRowHover`.

# iOS app · `apps/ios/`

## Design language: iOS 26 Liquid Glass

Default visual identity for every screen, view, modifier and reusable widget on iOS is **iOS 26 Liquid Glass**. Floating chrome (top-bar pills, composer, action buttons, sheets, badges, scroll-to-bottom dots, etc.) is built on `glassEffect(_:in:)` and grouped with `GlassEffectContainer` so adjacent shapes morph together when they animate.

Hard rules:

- **Always** prefer the native iOS 26 APIs over manual translucency. `.ultraThinMaterial`, custom blur views, opaque dark fills with low alpha, hand-rolled "fake glass" gradient stacks: NO. `.glassEffect(.regular, in: Capsule(style: .continuous))`, `.glassEffect(.regular, in: Circle())`, `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))`, `GlassEffectContainer`: YES.
- **Always** keep deployment target at iOS 26 so the call sites can use `.glassEffect()` directly without `if #available` ladders. If a view ever has to ship to an older iOS, gate it with availability and fall back, but the code path used by default is the iOS 26 one.
- **Pure black canvas** (`Color.black`) is the substrate beneath glass capsules: refraction reads cleanest against full black, not stacked dark grays.
- **Pill heights ≈ 50pt** for top-bar chrome, **composer ≈ 64pt**: glass needs vertical room for the highlight + refraction to read, thinner pills look like flat capsules.
- **No solid stroke borders on glass shapes**. The system glass effect already supplies the rim highlight; layering `.strokeBorder(Color.white.opacity(0.10))` on top kills the refraction.
- **Squircle rule still applies**: any RoundedRectangle passed as the shape to `.glassEffect(in:)` must use `style: .continuous`. Capsule and Circle are fine as-is.

Canonical helpers live in `Theme/GlassPill.swift` (`glassCapsule()`, `glassCircle()`, `glassRounded(radius:)`, `GlassIconButton`). Reuse them; do not re-derive the modifier chain by hand. Color and size tokens live in `Theme/DesignTokens.swift` (`Palette`, `AppLayout`, `Typography`); add to those files instead of inlining magic numbers.

Reference for layout, hierarchy and motion: ChatGPT iOS. The chat detail surface (light bubble for user messages, bare text for assistant, floating glass composer, two glass clusters in the top bar) is the visual baseline; copy paddings, radii and weights from there before inventing.
