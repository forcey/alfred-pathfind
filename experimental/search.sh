#!/bin/zsh --no-rcs
# Candidate retrieval only. Ranking and Alfred JSON remain in pathfind-alfred.sh.
setopt pipefail

ROOT="${0:A:h}"
backend="$1"
query="$2"

# Preserve the original Spotlight-content syntax via the fd implementation.
# These backends only compare path/name searching.
if [[ "$query" == *"in:"* ]]; then
  source "$ROOT/../helper_functions.sh"
  _argparse "$query"
  exec "$ROOT/../pathfind.sh" "${args[@]}"
fi

if [[ "$backend" == "fff" ]]; then
  node_bin="${PATHFIND_FFF_NODE_BIN:-}"
  if [[ -z "$node_bin" ]]; then
    if hash node 2>/dev/null; then
      node_bin="$(command -v node)"
    elif [[ -x /opt/homebrew/bin/node ]]; then
      node_bin=/opt/homebrew/bin/node
    elif [[ -x /usr/local/bin/node ]]; then
      node_bin=/usr/local/bin/node
    fi
  fi
  if [[ -z "$node_bin" ]]; then
    # GUI applications normally do not inherit the PATH set by shell startup
    # scripts. Probe common user-managed Node installations as a convenience.
    for candidate in \
      "$HOME"/.nvm/versions/node/*/bin/node(N) \
      "$HOME"/.fnm/node-versions/*/installation/bin/node(N) \
      "$HOME"/.local/share/mise/installs/node/*/bin/node(N) \
      "$HOME"/.volta/bin/node \
      "$HOME"/.local/share/mise/shims/node \
      "$HOME"/.asdf/shims/node; do
      if [[ -x "$candidate" ]]; then
        node_bin="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$node_bin" || ! -x "$node_bin" ]]; then
    echo "PathFind FFF: Node not found. Run 'command -v node' in Terminal, then paste its absolute path into Configure Workflow > Node executable (FFF)." >&2
    exit 1
  fi
  exec "$node_bin" "$ROOT/fff-client.mjs" search "$query" "${TYPE_OVERRIDE:-}"
fi

if [[ "$backend" != "fsearch" ]]; then
  echo "Unknown PathFind experimental backend: $backend" >&2
  exit 2
fi

fsearch_bin="${PATHFIND_FSEARCH_BIN:-}"
if [[ -z "$fsearch_bin" ]]; then
  if hash fsearch 2>/dev/null; then
    fsearch_bin="$(command -v fsearch)"
  elif [[ -x "$HOME/.local/bin/fsearch" ]]; then
    fsearch_bin="$HOME/.local/bin/fsearch"
  elif [[ -x /opt/homebrew/bin/fsearch ]]; then
    fsearch_bin=/opt/homebrew/bin/fsearch
  fi
fi
if [[ -z "$fsearch_bin" || ! -x "$fsearch_bin" ]]; then
  echo "PathFind fsearch: CLI unavailable; set PATHFIND_FSEARCH_BIN" >&2
  exit 1
fi

# Use the original configured search roots, one at a time, as scoped indexed
# queries. Unlike fd, fsearch indexes the whole volume before the query.
# Separate per-root limits prevent an unrelated directory crowding out results.
paths=("${(@f)PATHFIND_PATHS}")
(( ${#paths} > 0 )) || paths=("$PWD")
kind=()
case "${TYPE_OVERRIDE:-}" in
  directory) kind=("kind:dir");;
  file) kind=("kind:file");;
esac

# fsearch intentionally omits consent-gated directories without Full Disk
# Access. Surface the missing coverage instead of silently reporting no hits.
status_json="$("$fsearch_bin" status 2>/dev/null)"
access="$(print -r -- "$status_json" | jq -r 'if has("full_disk_access") then .full_disk_access else empty end' 2>/dev/null)"
for root in "${paths[@]}"; do
  [[ -n "$root" ]] || continue
  [[ "$root" == "~" ]] && root="$HOME"
  [[ "$root" == "~/"* ]] && root="$HOME/${root#~/}"
  if [[ ! -d "$root" ]]; then
    echo "PathFind fsearch: skipping missing root $root" >&2
    continue
  fi
  scope="$(cd -P "$root" && pwd)"
  # Under macOS privacy rules, the fsearch daemon skips these locations when
  # full_disk_access is false, even though fd may traverse them successfully.
  case "$scope" in
    "$HOME"/Library/CloudStorage|"$HOME"/Library/CloudStorage/*|"$HOME"/Library/Mobile\ Documents|"$HOME"/Library/Mobile\ Documents/*|"$HOME"/Documents|"$HOME"/Documents/*|"$HOME"/Desktop|"$HOME"/Desktop/*|"$HOME"/Downloads|"$HOME"/Downloads/*)
      if [[ "$access" == "false" ]]; then
        echo "fsearch lacks Full Disk Access, so it does not index $scope. Grant it to ~/.local/bin/fsearch in System Settings, then rebuild the fsearch index." >&2
        exit 3
      fi
      ;;
  esac
  # Quoting the entire in: value keeps spaces in Google Drive paths intact.
  # fsearch parses query words; the quote characters must reach that parser.
  "$fsearch_bin" "$query" "in:\"$scope\"" "${kind[@]}" "limit:500" --json |
    jq -r 'if .ok == true then (.hits // [] | .[] | .path) else error(.error // "fsearch query failed") end'
done | awk '!seen[$0]++'
