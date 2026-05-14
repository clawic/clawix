# Localization Backlog

State: `QUARANTINED`

Quarantine: `clawix-macos-localization-unregistered-ui-strings`

## Scope

The macOS release E2E localization check enforces complete translations for
registered `Localizable.xcstrings` keys and generated `.lproj` resources. A
separate scanner also detects SwiftUI literals that are not yet registered in
the catalog.

## Current Constraint

The unregistered-literal backlog is too large to repair safely in one automated
batch without creating low-quality translations. Missing registered
localizations and missing generated resources still fail the E2E lane.

## Repair Path

1. Group unregistered literals by product area.
2. Deduplicate repeated labels and remove false positives from the scanner.
3. Register source English keys in `Localizable.xcstrings`.
4. Add reviewed translations for every supported locale.
5. Run `bash scripts/test.sh e2e`.
6. Remove the quarantine entry.
