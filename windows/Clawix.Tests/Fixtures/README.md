# Bridge protocol fixtures

JSON dumps generated from the Swift test suite. Each file is one
encoded `BridgeFrame` on the wire.

To regenerate:

```bash
bash windows/scripts/dump-fixtures.sh
```

The C# tests deserialize each fixture, re-serialize it, and assert
that Windows preserves the same frame body and schema. Any decode drift
means the ports diverged and the wire is broken.
