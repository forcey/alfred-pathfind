#!/bin/bash
set -euxo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v zsh >/dev/null
command -v fd >/dev/null
command -v gawk >/dev/null
command -v jq >/dev/null

plutil -lint info.plist
zsh -n pathfind-alfred.sh
zsh -n experimental/search.sh
node --check experimental/fff-client.mjs
python3 -m py_compile experimental/benchmark.py

scratch="$(mktemp -d)"
scratch="$(cd -P "$scratch" && pwd)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/Tax/2025/Zhihong" "$scratch/Tax/2025/Donations"
mkdir -p "$scratch/Forbes Lake Capital/Tax 2025/work_2025/__pycache__"

export DEPS="fd gawk jq"
export alfred_workflow_uid="pathfind-experiment-smoke"
export PATHFIND_PATHS="$scratch"
export PATHFIND_BACKEND=""
export TYPE_OVERRIDE=directory
export INCLUDE_HIDDEN=false
export PATH_DISPLAY_DEPTH=0

result="$(./pathfind-alfred.sh 'tax/2025')"
jq --exit-status --arg expected "$scratch/Tax/2025" '.items[0].arg | rtrimstr("/") == $expected' <<<"$result" >/dev/null
echo "PASS: exact Tax/2025 directory ranks first"

result="$(./pathfind-alfred.sh 'tax 2025')"
jq --exit-status --arg expected "$scratch/Tax/2025"   '[.items[].arg | rtrimstr("/")] | index($expected) != null' <<<"$result" >/dev/null
echo "PASS: ordinary multi-term search retains correct matches"

# Indexed backends must not silently default to the workflow directory.
unset PATHFIND_PATHS
PATHFIND_BACKEND=fff
result="$(./pathfind-alfred.sh 'tax')"
jq -e '.items[0].title | startswith("Configure Include paths")' <<<"$result" >/dev/null
echo "PASS: missing Alfred Include paths have an actionable error"

# Privacy protection is observable without crawling the real home directory.
# This mock simulates the fsearch status JSON that excludes CloudStorage.
cat > "$scratch/mock-fsearch" <<'EOS'
#!/bin/sh
if [ "$1" = status ]; then
  printf '%s\n' '{"ok":true,"full_disk_access":false}'
else
  printf '%s\n' '{"ok":true,"hits":[]}'
fi
EOS
chmod +x "$scratch/mock-fsearch"
gated="$HOME/Documents/pathfind-privacy-smoke-$"
mkdir -p "$gated"
PATHFIND_PATHS="$gated"
PATHFIND_BACKEND=fsearch
PATHFIND_FSEARCH_BIN="$scratch/mock-fsearch"
export PATHFIND_PATHS PATHFIND_BACKEND PATHFIND_FSEARCH_BIN
result="$(./pathfind-alfred.sh 'tax')"
jq -e '.items[0].title == "Search engine error (fsearch)" and (.items[0].subtitle | contains("Full Disk Access"))' <<<"$result" >/dev/null
rmdir "$gated"
echo "PASS: missing Full Disk Access appears as an Alfred error"

unset PATHFIND_FSEARCH_BIN
PATHFIND_PATHS="$scratch"
PATHFIND_BACKEND=""

./build.sh
unzip -t dist/PathFind.alfredworkflow >/dev/null
echo "PASS: workflow package validates"
