# Naming shape audit

Status: initial report

Date: 2026-05-15

This is the living Clawix host audit report for ADR 0009. The
machine-readable source is `node scripts/naming-shape-check.mjs --json`;
source-shape signals come from `node scripts/source-size-check.mjs --json`.

## Current gate status

- Critical naming failures: 0.
- Naming warnings: 64.
- Source-size warnings: 35.
- Source-structure signals: 27.

The current gate is intentionally critical-only. Warnings are cleanup inventory
for staged rename/split work and must not be hidden by compressing code.

## Largest current files

- `packages/SecretsCrypto/Sources/SecretsCrypto/BIP39Wordlist.swift` - 2066 lines.
- `macos/Sources/Clawix/AppState.swift` - 1986 lines.
- `macos/Sources/Clawix/SidebarView.swift` - 1897 lines.
- `macos/Sources/Clawix/DictationSettingsPage.swift` - 1844 lines.
- `macos/Sources/Clawix/Sidebar/SidebarView+DragDrop.swift` - 1500 lines.
- `web/src/screens/pomodoro/pomodoro-view.tsx` - 1403 lines.
- `macos/Sources/Clawix/ScreenTools/ScreenToolService.swift` - 1365 lines.
- `macos/Sources/Clawix/QuickAsk/QuickAskView.swift` - 1338 lines.
- `macos/Sources/Clawix/Dictation/DictationCoordinator.swift` - 1323 lines.
- `macos/Helpers/Bridged/Sources/clawix-bridge/main.swift` - 1310 lines.

## Cleanup families

- Bridge/session vocabulary: audit `chat`, `sessionId`, and `threadId` by
  UI-local, bridge-protocol, and external-runtime boundary.
- App state and sidebar: split root state, route selection, persistence,
  project/session projections, and UI interactions by responsibility.
- Dictation and screen tools: split settings UI, runtime orchestration,
  provider adapters, and persistence.
- Web bridge exports: review `web/src/bridge/frames.ts` and `wire.ts` as large
  export surfaces.
- Design builtins and persistent registry: expand compressed lists only when
  the next edit touches that area.
- Broad Swift symbols: review `Manager`, `Helper`, `Data`, and `Info` only when
  a clearer domain + role name exists.
- Naming check scope: generated output, vendored code, and local variable-only
  `Data`/`Info`/`Manager` noise are excluded so the warning inventory stays
  focused on source files, types, functions, and exported values.
- IoT device vocabulary: initial host cleanup completed. Clawix UI and local
  symbols now use `Device` (`IoTDeviceRecord`, `IoTDeviceKind`, `DeviceCard`,
  `IoTDevicesView`, `IoTDeviceDetailView`, `addDevice`, `removeDevice`).
  Daemon wire keys and event names keep `thing` only where required by the
  current ClawJS IoT contract.
- Backend initialize vocabulary: `InitializeClientInfo` was narrowed to
  `InitializeClientIdentity` in the app and bridge protocol wrappers. The wire
  field remains `clientInfo` because it belongs to the runtime schema.
- Backend runtime vocabulary: `BackendAuthInfo` is now
  `BackendAccountProfile`, and `ClawixBinaryInfo` is now
  `ClawixBinaryResolution`. These are local app concepts: a parsed account
  profile and the resolved runtime executable path/version.
- Secrets service vocabulary: `SecretsStateInfo` is now
  `SecretsServiceState`, and the loader uses `serviceState` locally instead of
  generic `info`.

## Validation snapshot

- `bash scripts/test.sh fast` passed after adding the new checks.
- `node scripts/naming-shape-check.mjs` passed with warnings only.
- `node scripts/source-size-check.mjs` passed with warnings/signals only.
- `node scripts/codebase-manifest.mjs --check` passed.
- `bash scripts/doc_alignment_check.sh` passed.

This report is not final completion evidence for the full goal. It is the
baseline for the later broad cleanup and rename phases.
