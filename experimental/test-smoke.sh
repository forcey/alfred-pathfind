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
    "fs": ("fsearch", None),
    "fsd": ("fsearch", "directory"),
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
print("PASS: pf/pfd, fd/fdd, fs/fsd, ff/ffd routing and output connections")
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
gated="$HOME/Documents/pathfind-privacy-smoke"
mkdir -p "$gated"
PATHFIND_PATHS="$gated"
PATHFIND_BACKEND=fsearch
PATHFIND_FSEARCH_BIN="$scratch/mock-fsearch"
export PATHFIND_PATHS PATHFIND_BACKEND PATHFIND_FSEARCH_BIN
result="$(./pathfind-alfred.sh 'tax')"
jq -e '.items[0].title == "Search engine error (fsearch)" and (.items[0].subtitle | contains("Full Disk Access"))' <<<"$result" >/dev/null
# The user may configure a shortcut pointing into a privacy-gated directory.
ln -s "$gated" "$scratch/Google Drive"
PATHFIND_PATHS="$scratch/Google Drive"
export PATHFIND_PATHS
result="$(./pathfind-alfred.sh 'tax')"
jq -e '.items[0].title == "Search engine error (fsearch)"' <<<"$result" >/dev/null
rm "$scratch/Google Drive"
rmdir "$gated"
echo "PASS: Full Disk Access warning covers gated directories and symlink aliases"

# Reproduce an Alfred-only configuration that includes a tilde symlink root.
# The old adapter could skip these while succeeding with absolute CLI roots.
mkdir -p "$scratch/GoogleDrive-real/My Drive/Tax/2025"
link="$HOME/PathFind Google Drive CI ${RANDOM}"
ln -s "$scratch/GoogleDrive-real" "$link"
cat > "$scratch/mock-fsearch-ok" <<'EOS'
#!/bin/sh
if [ "$1" = status ]; then
  printf '%s\n' '{"ok":true,"full_disk_access":true}'
else
  printf '%s\n' "$@" > "$PATHFIND_FSEARCH_LOG"
  printf '{"ok":true,"hits":[{"path":"%s"}]}\n' "$PATHFIND_FSEARCH_EXPECTED"
fi
EOS
chmod +x "$scratch/mock-fsearch-ok"
export PATHFIND_PATHS="~/${link##*/}"
export PATHFIND_FSEARCH_BIN="$scratch/mock-fsearch-ok"
export PATHFIND_FSEARCH_LOG="$scratch/fsearch-args.txt"
export PATHFIND_FSEARCH_EXPECTED="$scratch/GoogleDrive-real/My Drive/Tax/2025"
result="$(./pathfind-alfred.sh 'tax/2025')"
jq -e --arg expected "$PATHFIND_FSEARCH_EXPECTED" '.items[0].arg == $expected' <<<"$result" >/dev/null
grep -Fx "in:\"$scratch/GoogleDrive-real\"" "$PATHFIND_FSEARCH_LOG" >/dev/null
rm "$link"
echo "PASS: Alfred tilde + Google Drive symlink root resolves to canonical fsearch scope"

unset PATHFIND_FSEARCH_BIN
PATHFIND_PATHS="$scratch"
PATHFIND_BACKEND=""

./build.sh
unzip -t dist/PathFind.alfredworkflow >/dev/null
echo "PASS: workflow package validates"
