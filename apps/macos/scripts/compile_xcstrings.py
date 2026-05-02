#!/usr/bin/env python3
"""Compile Localizable.xcstrings into per-locale Localizable.strings files.

Swift Package Manager (as of 6.x) does NOT process `.xcstrings` files into
the per-locale `.lproj/Localizable.strings` format that `Bundle` reads
at runtime. The xcstrings drop-in just sits in the resource bundle and
`bundle.localizations` reports only the source language.

This script translates the xcstrings JSON into `<locale>.lproj/Localizable.strings`
files alongside it, so `String(localized:bundle:locale:)` and SwiftUI's
`Text(\"literal\")` resolve the right translation when the user picks a
language at runtime.

Run from `scripts/dev.sh` before `swift build` (or any time the xcstrings
file changes).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from plistlib import dump


def escape_strings_value(s: str) -> str:
    """Escape a value for the .strings file format."""
    # Backslash first, then the characters that need escaping.
    s = s.replace("\\", "\\\\")
    s = s.replace("\"", "\\\"")
    s = s.replace("\n", "\\n")
    s = s.replace("\r", "\\r")
    s = s.replace("\t", "\\t")
    return s


def escape_strings_key(s: str) -> str:
    return escape_strings_value(s)


def compile_xcstrings(src: Path, resources_dir: Path) -> None:
    data = json.loads(src.read_text(encoding="utf-8"))
    source_lang = data.get("sourceLanguage", "es")
    strings = data.get("strings", {})

    # Collect every locale that appears anywhere in the file.
    locales: set[str] = {source_lang}
    for entry in strings.values():
        for loc in entry.get("localizations", {}).keys():
            locales.add(loc)

    # For each locale, write a Localizable.strings file with all fixed keys
    # and a Localizable.stringsdict file for plural variants. Keys missing
    # from a locale fall back to the source value (so SwiftUI's
    # `Text(\"literal\")` always has SOMETHING to show even mid-translation).
    written = []
    for loc in sorted(locales):
        lproj = resources_dir / f"{loc}.lproj"
        lproj.mkdir(parents=True, exist_ok=True)
        out = lproj / "Localizable.strings"
        stringsdict_out = lproj / "Localizable.stringsdict"
        lines = ["/* Auto-generated from Localizable.xcstrings. Do not edit by hand. */", ""]
        stringsdict: dict[str, dict[str, object]] = {}
        for key in sorted(strings.keys()):
            entry = strings[key]
            locs = entry.get("localizations", {})
            loc_entry = locs.get(loc, {})
            source_entry = locs.get(source_lang, {})
            variations = loc_entry.get("variations") or source_entry.get("variations")
            plural = variations.get("plural") if variations else None
            if plural:
                spec: dict[str, object] = {
                    "NSStringLocalizedFormatKey": "%#@value@",
                    "value": {
                        "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                        "NSStringFormatValueTypeKey": "lld",
                    },
                }
                for category, variant in plural.items():
                    unit = variant.get("stringUnit", {})
                    spec["value"][category] = unit.get("value", key)
                stringsdict[key] = spec
                continue

            unit = loc_entry.get("stringUnit")
            if unit is None:
                # Fall back to source language value (or the key itself
                # when even the source has no value).
                src_unit = source_entry.get("stringUnit")
                value = src_unit.get("value", key) if src_unit else key
            else:
                value = unit.get("value", key)
            # Skip empty internal sentinels (key like "_zzz_endmarker").
            if not key.strip() or key.startswith("_zzz_"):
                continue
            lines.append(f'"{escape_strings_key(key)}" = "{escape_strings_value(value)}";')
        out.write_text("\n".join(lines) + "\n", encoding="utf-8")
        written.append(str(out.relative_to(resources_dir.parent)))
        if stringsdict:
            with stringsdict_out.open("wb") as f:
                dump(stringsdict, f, sort_keys=True)
            written.append(str(stringsdict_out.relative_to(resources_dir.parent)))
        elif stringsdict_out.exists():
            stringsdict_out.unlink()

    print(f"Compiled xcstrings into {len(written)} .lproj bundles:")
    for w in written:
        print(f"  {w}")


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    project_dir = script_dir.parent
    src = project_dir / "Sources/Clawix/Resources/Localizable.xcstrings"
    resources_dir = project_dir / "Sources/Clawix/Resources"
    if not src.exists():
        print(f"ERROR: {src} not found", file=sys.stderr)
        return 1
    compile_xcstrings(src, resources_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
