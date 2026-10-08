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

if ! command -v zsh >/dev/null 2>&1; then
  echo "error: zsh is required" >&2
  exit 1
fi

# Catch shell quoting/syntax errors before creating an installable package.
for script in pathfind-alfred.sh pathfind.sh helper_functions.sh install_cli.sh install_deps.sh link.sh experimental/search.sh; do
  if [[ -f "$script" ]]; then
    zsh -n "$script"
  fi
done

OUT="${1:-$ROOT/dist/PathFind.alfredworkflow}"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

# The experimental Alfred metadata adds input objects and connections.
# Fail the build rather than shipping an invalid plist.
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$ROOT/info.plist" >/dev/null
fi

# Package exactly the files tracked by git. This avoids .git/, dist/, editor
# files, and other untracked build artifacts. zip preserves executable bits,
# which Alfred workflow scripts rely on.
git ls-files -z | xargs -0 zip -q -X "$OUT"

# Optionally bundle the FFF Node SDK and its platform-specific native library.
# This is deliberate for the experiment; do not vendor dependencies to main.
if [[ -d "$ROOT/experimental/node_modules/@ff-labs/fff-node" ]]; then
  zip -q -r -X "$OUT" experimental/node_modules
  echo "Bundled installed FFF dependencies from experimental/node_modules"
else
  echo "Note: FFF dependencies not bundled (run npm install --prefix experimental)" >&2
fi

# Alfred expects info.plist at the root of the archive, not inside a parent
# directory.
if ! unzip -Z1 "$OUT" | grep -x 'info.plist' >/dev/null; then
  echo "error: built archive does not contain info.plist at its root" >&2
  rm -f "$OUT"
  exit 1
fi

echo "Built: $OUT"
