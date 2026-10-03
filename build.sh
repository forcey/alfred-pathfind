#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ ! -f info.plist ]]; then
  echo "error: info.plist not found at repository root" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required" >&2
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "error: zip is required" >&2
  exit 1
fi

OUT="${1:-$ROOT/dist/PathFind.alfredworkflow}"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

# Package exactly the files tracked by git. This avoids .git/, dist/, editor
# files, and other untracked build artifacts. zip preserves executable bits,
# which Alfred workflow scripts rely on.
git ls-files -z | xargs -0 zip -q -X "$OUT"

# Alfred expects info.plist at the root of the archive, not inside a parent
# directory.
if ! unzip -Z1 "$OUT" | grep -qx 'info.plist'; then
  echo "error: built archive does not contain info.plist at its root" >&2
  rm -f "$OUT"
  exit 1
fi

echo "Built: $OUT"
