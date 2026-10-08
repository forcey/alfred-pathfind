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
  if ! hash node 2>/dev/null; then
    echo "PathFind FFF: node was not found on PATH" >&2
    exit 1
  fi
  exec node "$ROOT/fff-client.mjs" search "$query" "${TYPE_OVERRIDE:-}"
fi

if [[ "$backend" != "fsearch" ]]; then
  echo "Unknown PathFind experimental backend: $backend" >&2
  exit 2
fi

if ! hash fsearch 2>/dev/null; then
  echo "PathFind fsearch: install the fsearch CLI first" >&2
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

for root in "${paths[@]}"; do
  [[ -n "$root" ]] || continue
  [[ "$root" == "~" ]] && root="$HOME"
  [[ "$root" == "~/"* ]] && root="$HOME/${root#~/}"
  if [[ ! -d "$root" ]]; then
    echo "PathFind fsearch: skipping missing root $root" >&2
    continue
  fi
  scope="$(cd -P "$root" && pwd)"
  # Quoting the entire in: value keeps spaces in Google Drive paths intact.
  # fsearch parses query words; the quote characters must reach that parser.
  fsearch "$query" "in:\"$scope\"" "${kind[@]}" "limit:500" --json |
    jq -r 'if .ok == true then (.hits // [] | .[] | .path) else empty end'
done | awk '!seen[$0]++'
