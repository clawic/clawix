# Bridge protocol fixtures

JSON dumps generated from the Swift test suite. Each file is one
encoded `BridgeFrame` on the wire.

To regenerate:

```bash
cd ../../packages/ClawixCore
swift test --filter BridgeProtocolFixturesTests
# fixtures land in /tmp/clawix-bridge-fixtures, copy into this folder
```

The C# tests deserialize each fixture, re-serialize it, and assert
byte-for-byte equality with the original JSON. Any drift means the
ports diverged and the wire is broken.
