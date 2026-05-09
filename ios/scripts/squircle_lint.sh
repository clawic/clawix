#!/usr/bin/env bash
# Mirror of the macOS squircle lint, scoped to the iOS Sources tree.
# Every corner radius must use `style: .continuous`. Fails the build
# if any disallowed pattern shows up.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

SQ_BAD=""

# A) Single-line RoundedRectangle without .continuous.
A=$(grep -rn "RoundedRectangle(cornerRadius:" --include="*.swift" Sources/ \
    | grep -v "\.continuous" || true)
[[ -n "$A" ]] && SQ_BAD+=$'\n[A] RoundedRectangle without style: .continuous:\n'"$A"

# B) The .cornerRadius(N) modifier always clips with circular corners.
B=$(grep -rn "\.cornerRadius(" --include="*.swift" Sources/ || true)
[[ -n "$B" ]] && SQ_BAD+=$'\n[B] forbidden .cornerRadius() modifier:\n'"$B"

# C) Explicit circular style.
C=$(grep -rn "style: \.circular\|RoundedCornerStyle\.circular" --include="*.swift" Sources/ || true)
[[ -n "$C" ]] && SQ_BAD+=$'\n[C] explicit style: .circular forbidden:\n'"$C"

# D) Multi-line UnevenRoundedRectangle / Path(roundedRect:...) without
#    .continuous within 6 lines of the opening.
D=$(awk '
  FNR==1 { needs=0; start=0; buf="" }
  needs {
    buf = buf "\n" $0
    if ($0 ~ /\.continuous/) { needs=0; buf="" }
    else if (FNR - start >= 6) {
      printf "%s:%d:\n%s\n---\n", FILENAME, start, buf
      needs=0; buf=""
    }
  }
  (/UnevenRoundedRectangle\(/ || /Path\(roundedRect:/) {
    start=FNR; needs=1; buf=$0
    if ($0 ~ /\.continuous/) { needs=0; buf="" }
  }
' $(find Sources -name "*.swift") || true)
[[ -n "$D" ]] && SQ_BAD+=$'\n[D] UnevenRoundedRectangle / Path(roundedRect:) without style: .continuous nearby:\n'"$D"

if [[ -n "$SQ_BAD" ]]; then
    echo "ERROR: squircle rule violated. Every corner radius must use style: .continuous." >&2
    echo "$SQ_BAD" >&2
    exit 1
fi

echo "squircle lint passed"
