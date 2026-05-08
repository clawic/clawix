# ClawixArgon2

Vendored Argon2id reference implementation with a thin Swift facade.

Used by Clawix to derive the master key of the secrets vault from the user's
master password (and the recovery key from the BIP39 phrase). Argon2id is the
2015 PHC competition winner and the recommended password-hashing function for
new applications.

## Layout

```
Sources/
  CArgon2/                 vendored phc-winner-argon2 (commit f57e61e)
    include/argon2.h       public header surfaced by the modulemap
    blake2/                blake2b dependency of the reference impl
    *.c, *.h               reference computation
  ClawixArgon2/Argon2.swift Swift wrapper around argon2_*_hash_raw
Tests/ClawixArgon2Tests/   determinism and variant tests
```

## Provenance

- Upstream: https://github.com/P-H-C/phc-winner-argon2
- Commit pinned: `f57e61e19229e23c4445b85494dbf7c07de721cb`
- License: dual CC0 1.0 Universal / Apache 2.0 (see `LICENSE.argon2`)
- Threading is disabled (`ARGON2_NO_THREADS`) to keep the build self-contained;
  parallelism > 1 still works because the reference fallback path covers it.

## Usage

```swift
import ClawixArgon2

let params = Argon2.Params(memoryKB: 65_536, iterations: 3, parallelism: 1)
let key = try Argon2.deriveKey(
    password: Data("master pwd".utf8),
    salt: salt,
    params: params,
    outputLength: 32,
    variant: .id
)
```

Calibrate `params` once on the user's device so a single call lands around 250 ms.

## Why we vendor instead of depending on a third party

Critical cryptography on the user's machine should not depend on a third-party
SwiftPM package whose maintenance and provenance we do not control. The vendored
reference implementation is small, stable, and well-audited; we keep the
upstream commit pinned and the license file alongside.
