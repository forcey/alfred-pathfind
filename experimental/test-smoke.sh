#!/bin/bash
set -euxo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v zsh >/dev/null
command -v fd >/dev/null
command -v gawk >/dev/null
command -v jq >/dev/null

plutil -lint info.plist
# Verify the installed workflow contains every requested trigger, the correct
# backend, and action connections. This also catches duplicate Alfred keywords.
python3 - <<'PY'
import plistlib
with open("info.plist", "rb") as fp:
    data = plistlib.load(fp)
assert data["bundleid"] == "com.luckman212.pathfind"
assert data["name"] == "PathFind"
settings = {field["variable"]: field["config"] for field in data["userconfigurationconfig"]}
assert settings["KW_TRIGGER"]["default"] == "pf"
by_keyword = {}
for obj in data["objects"]:
    if obj["type"] != "alfred.workflow.input.scriptfilter":
        continue
    keyword = obj["config"].get("keyword")
    if not keyword:
        continue
    for token in keyword.split("||"):
        assert token not in by_keyword, f"duplicate keyword {token}"
        by_keyword[token] = obj
expected = {
    "{var:KW_TRIGGER}": (None, None),
    "pfd": (None, "directory"),
    "fd": (None, None),
    "fdd": (None, "directory"),
    "ff": ("fff", None),
    "ffd": ("fff", "directory"),
}
for key, (backend, mode) in expected.items():
    obj = by_keyword[key]
    uid = obj["uid"]
    assert uid in data["connections"] and data["connections"][uid], f"no output action for {key}"
    script = obj["config"].get("script", "")
    if key == "{var:KW_TRIGGER}":
        assert obj["config"].get("scriptfile") == "pathfind-alfred.sh"
    else:
        if backend:
            assert f"export PATHFIND_BACKEND={backend}" in script, (key, script)
        else:
            assert "PATHFIND_BACKEND" not in script, (key, script)
        assert f"export TYPE_OVERRIDE={'directory' if mode else ''}" in script, (key, script)
for retired in ("fs", "fsd"):
    assert retired not in by_keyword, f"retired fsearch keyword {retired} still present"
print("PASS: pf/pfd, fd/fdd, ff/ffd routing and output connections")
PY
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

# Backend failures surface as an Alfred error item rather than "Nothing found".
PATHFIND_PATHS="$scratch"
PATHFIND_BACKEND=fff
PATHFIND_FFF_NODE_BIN="$scratch/missing-node"
export PATHFIND_PATHS PATHFIND_BACKEND PATHFIND_FFF_NODE_BIN
result="$(./pathfind-alfred.sh 'tax')"
jq -e '.items[0].title == "Search engine error (fff)"' <<<"$result" >/dev/null
echo "PASS: backend failure is shown as an actionable Alfred item"

unset PATHFIND_FFF_NODE_BIN
PATHFIND_PATHS="$scratch"
PATHFIND_BACKEND=""

./build.sh
unzip -t dist/PathFind.alfredworkflow >/dev/null
echo "PASS: workflow package validates"
