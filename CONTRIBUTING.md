# Contributing to Clawix

## Ground rules

- Treat the published surface (UI, scripts, hygiene gate) as product surface.
- Do not merge changes that leave `swift build`, `bash macos/scripts/public_hygiene_check.sh`, or `bash macos/scripts/e2e_validate.sh` failing.
- Prefer additive, well-scoped changes. If a change alters public behavior, update docs in the same patch.
- For architecture, storage, naming, host, validation, release, or privacy
  decisions, start from [docs/decision-map.md](docs/decision-map.md). It points
  to the canonical source and the guardrail expected for each decision.

## Local setup

Requirements: macOS 14+, Swift 5.9+, Xcode Command Line Tools.

```
bash macos/scripts/dev.sh
```

For a stable codesigned dev build (so macOS keeps your TCC grants between rebuilds), create a `.signing.env` file at the repo root with your codesign identity and bundle id. See [README.md](./README.md#stable-signing-recommended-for-daily-dev) for the format. The file is in `.gitignore`.

## Privacy and signing rules

- Never commit a `.signing.env` file. It carries the maintainer's codesign identity and bundle id.
- Never hard-code an Apple Team ID, an `Apple Development:` / `Apple Distribution:` literal, a real bundle id, or any other maintainer-specific value in source files. Read them from environment variables resolved by the build scripts.
- Never construct `Info.plist` with a literal `CFBundleIdentifier`. The plist is generated in `build_app.sh` interpolating `${BUNDLE_ID}` from the environment.
- Do not add an Xcode project with `DEVELOPMENT_TEAM` filled in. The field stays empty and is supplied by the script.

The hygiene gate (`macos/scripts/public_hygiene_check.sh`) blocks publishing when any of the above slips through. Run it locally before opening a pull request.

## Code conventions

- Corner radius: every `RoundedRectangle`, `UnevenRoundedRectangle` and `Path(roundedRect:)` uses `style: .continuous` (the squircle). The lint inside `dev.sh` fails the build if a circular radius slips in. Full rules in [`CLAUDE.md`](./CLAUDE.md).
- Dropdowns / popups / context menus follow the `ModelMenuPopup` pattern in `ComposerView.swift`. Use the `.menuStandardBackground()` helper, the `MenuRowHover` highlight and the `softNudge` transition, never SwiftUI's native `.popover` chrome. Full rules in [`CLAUDE.md`](./CLAUDE.md).

## Pull requests

- Keep commit messages in `type(scope): description` form. Examples: `feat(mac/composer): add model menu popup`, `fix(mac/sidebar): resolve overlap on long names`, `chore(repo): update hygiene globs`.
- Update docs and the changelog if the change is user-facing.
- Run `bash macos/scripts/public_hygiene_check.sh` before pushing.
- Keep PR scope narrow. Two unrelated changes are two pull requests.

## Localization

The string catalog at `macos/Sources/Clawix/Resources/Localizable.xcstrings` covers ten locales. New strings are added with English keys and translations supplied at least for English; `scripts/compile_xcstrings.py` regenerates the per-locale `.strings` and `.stringsdict` files from the catalog.
