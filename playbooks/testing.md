# Testing

Clawix uses boundary-based test lanes. The canonical policy is
[ADR 0003](../docs/adr/0003-testing-architecture.md), synchronized with the
ClawJS testing ADR.

## Lanes

Run the public-safe lane runner from the repo root:

```bash
bash scripts/test.sh changed
```

- `fast`: public hygiene, small Swift logic/package tests, and web unit tests
  when dependencies are installed.
- `changed`: normal blocking gate for a focused change.
- `integration`: heavier Swift packages, macOS package tests, daemon, bridge,
  and fixture checks that remain local.
- `e2e`: local app/bridge fixture E2E checks that do not require private
  signing values.
- `host`: signed-host validation. Uses private hooks only when configured.
- `device`: Android/iOS device or simulator checks.
- `live`: opt-in external checks. Requires `CLAWIX_TEST_LIVE=1`.
- `release`: hygiene plus every non-live lane required before publishing.

The runner also enforces the policy guard during `fast`: synced ADR, matrix,
scenario files, ignored artifact paths, and non-expired quarantine entries.

## Privacy

The public runner must not embed or print private signing identities, Team IDs,
bundle IDs, local machine paths, tokens, or secrets. When a signed host or real
device is required but not available, record the result as `EXTERNAL PENDING`
with the missing prerequisite and the hermetic test that covers the local
contract.

## Quarantine

Quarantines live in `qa/quarantine.json`. Each entry needs `id`, `owner`,
`reason`, `repair`, and `expires`. Expired entries fail the public runner.
