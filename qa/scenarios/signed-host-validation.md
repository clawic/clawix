# Signed Host Validation Scenario

Status: ACTIVE

Boundary: signed host, bridge, native permissions

## Purpose

Verify behavior that cannot be proven by hermetic tests alone because macOS
identity, TCC grants, app windows, or local helper ownership are involved.

## Steps

1. Build and launch the current workspace through the private Clawix launcher.
2. Confirm the open app is the current `/Applications/Clawix.app` build.
3. Run `bash scripts/test.sh host` with a private `CLAWIX_HOST_TEST_COMMAND`
   that uses the signed-host validation flow.
4. Exercise the bridge and permission path being changed.
5. Record `PASS`, `FAIL`, `PARTIAL`, or `EXTERNAL PENDING`.

## Expected Result

Host-dependent behavior is validated against the signed app identity. If the
required physical permission, device, or external account is unavailable, the
scenario is recorded as `EXTERNAL PENDING` with the missing prerequisite.
