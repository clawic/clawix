#!/usr/bin/env python3
"""In-place patcher: rewrite absolute build paths inside a Mach-O binary
so the shipped artifact does not leak the maintainer's $HOME, username
or project layout.

Why this exists. Swift's `-file-prefix-map` only affects DWARF /
coverage / index info. It does NOT rewrite `#file` literals embedded by
the compiler into `__TEXT,__cstring`. Those are baked-in C strings that
GRDB and other libraries reach for at runtime in preconditions and
fatalError messages, and they hold the absolute build path verbatim.

Strategy. Find each occurrence of a user-supplied byte prefix and
overwrite the bytes IN PLACE with the anonymised replacement, padded
with NUL bytes so the original byte count is preserved. C strings are
NUL-terminated, so any reader that pointed at the original offset now
sees the shorter, anonymised string and offsets to other strings stay
valid.

Usage:
    strip_user_paths.py <binary> --replace OLD=NEW [--replace OLD=NEW]...

The script holds NO hardcoded paths. The caller (build_release_app.sh)
expands `$HOME` / `$PROJECT_DIR` at runtime and passes them in via
`--replace`. This keeps personal paths out of the public source tree.

Idempotent. Replacements with `len(NEW) > len(OLD)` are rejected
because the byte count must stay constant.
"""
import argparse
import sys
from pathlib import Path

def parse_replacement(spec: str) -> tuple[bytes, bytes]:
    if "=" not in spec:
        raise SystemExit(f"--replace value must be OLD=NEW, got {spec!r}")
    old, new = spec.split("=", 1)
    if old == "":
        raise SystemExit("--replace OLD half cannot be empty")
    old_b, new_b = old.encode(), new.encode()
    if len(new_b) > len(old_b):
        raise SystemExit(
            f"--replace replacement longer than original, would shift offsets: "
            f"{old!r} -> {new!r}"
        )
    return old_b, new_b

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("binary", help="Path to the Mach-O binary to patch in place")
    ap.add_argument(
        "--replace", action="append", metavar="OLD=NEW", required=True,
        help="Byte-prefix replacement, repeatable. NEW must be no longer than OLD."
    )
    args = ap.parse_args()

    pairs = [parse_replacement(r) for r in args.replace]
    # Longest OLD first so the most specific replacement wins before any
    # shorter prefix swallows part of it.
    pairs.sort(key=lambda p: -len(p[0]))

    target = Path(args.binary)
    if not target.is_file():
        print(f"ERROR: {target} not a file", file=sys.stderr)
        return 1

    raw = target.read_bytes()
    total = 0
    for needle, anon in pairs:
        if needle not in raw:
            continue
        pad = b"\x00" * (len(needle) - len(anon))
        replacement = anon + pad
        before = raw.count(needle)
        raw = raw.replace(needle, replacement)
        total += before
    target.write_bytes(raw)
    print(f"Patched {total} prefix occurrence(s) in {target.name} ({len(raw)} bytes)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
