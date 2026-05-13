# External Pending Scenario

Status: ACTIVE

Boundary: host, device, live integrations

## Purpose

Record validation that cannot be completed because it needs physical hardware,
signed host identity, real accounts, paid APIs, or production-like external
state.

## Required Evidence

- The local hermetic test that covers the contract.
- The exact missing prerequisite.
- The lane that reported `EXTERNAL PENDING`.
- Confirmation that no real prompt, paid API call, production write, private
  token, signing identity, Team ID, or bundle id was used.

## Expected Result

The item is tracked as `EXTERNAL PENDING`, not `PASS`. It becomes `PASS` only
after the physical or external prerequisite is available and the matching lane
is rerun with explicit operator approval.
