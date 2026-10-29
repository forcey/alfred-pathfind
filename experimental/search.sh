#!/bin/zsh --no-rcs
# Candidate retrieval only. Ranking and Alfred JSON remain in pathfind-alfred.sh.
setopt pipefail

ROOT="${0:A:h}"
backend="$1"
query="$2"

# Preserve the original Spotlight-content syntax via the fd implementation.
# The fff backend only does path/name searching.
if [[ "$query" == *"in:"* ]]; then
  source "$ROOT/../helper_functions.sh"
  _argparse "$query"
  exec "$ROOT/../pathfind.sh" "${args[@]}"
fi

if [[ "$backend" != "fff" ]]; then
  echo "Unknown PathFind experimental backend: $backend" >&2
  exit 2
fi

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
