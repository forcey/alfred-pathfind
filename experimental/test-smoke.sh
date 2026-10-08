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
jq --exit-status --arg expected "$scratch/Tax/2025" '.items[0].arg == $expected' <<<"$result" >/dev/null
echo "PASS: exact Tax/2025 directory ranks first"

result="$(./pathfind-alfred.sh 'tax 2025')"
jq --exit-status --arg expected "$scratch/Tax/2025"   '[.items[].arg] | index($expected) != null' <<<"$result" >/dev/null
echo "PASS: ordinary multi-term search retains correct matches"

./build.sh
unzip -t dist/PathFind.alfredworkflow >/dev/null
echo "PASS: workflow package validates"
