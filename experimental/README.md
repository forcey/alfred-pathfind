# Experimental search engines for PathFind

This branch is deliberately **not** merged into main. The Alfred bundle ID is
`com.forcey.pathfind.search-experiment`, so it can coexist with the normal
PathFind workflow. Configure the **same Include paths** in both workflows.

| Keyword | Engine | Type |
|---|---|---|
| `pfd` (your existing installed workflow) | fd | folders |
| `pf0`, `pf0d`, `pf0f` | fd | mixed, folders, files |
| `pfs`, `pfsd` | [fsearch](https://github.com/noahdunnagan/fsearch) | mixed, folders |
| `pfx`, `pfxd` | [fff](https://github.com/dmtrKovalenko/fff) | mixed, folders |

All backends send paths to the same `pathfind-alfred.sh` renderer, so the
experimental backends inherit the `tax/2025` path ranking and junk-dir
deprioritization from main. The **candidate sets differ** (and are capped to
500 candidates per configured root for each experimental backend).

## Installation on macOS

1. Build the [fsearch](https://github.com/noahdunnagan/fsearch) CLI:

   ```sh
   git clone https://github.com/noahdunnagan/fsearch.git
   cd fsearch
   cargo build --release
   ./target/release/fsearch install --login
   fsearch status
   ```

   The install command copies `fsearch` to `~/.local/bin/fsearch`. Its
   full-disk daemon indexes once and maintains its index with FSEvents.
   Grant Full Disk Access to that installed binary to cover protected paths.
   First indexing may take tens of seconds. A Unix-socket daemon stays alive.
   No administrator privileges should be needed for the per-user installation.

2. Install Node.js 18+ and the FFF SDK into the **experiment directory**:

   ```sh
   cd /path/to/alfred-pathfind
   npm install --prefix experimental
   node experimental/fff-client.mjs warm
   ```

   The Node package uses a native shared library. FFF upstream releases may
   require installing the matching platform-specific binary too; if the
   `warm` command complains about a missing native binary, follow the
   [FFF Node SDK documentation](https://github.com/dmtrKovalenko/fff/tree/main/packages/fff-node)
   and resolve the installation before benchmarking. The persistent Node
   process keeps one FFF index per configured Include path in memory and
   watches for changes. Avoid indexing the entire HOME in many simultaneous
   FFF instances; a few precise roots is more representative.

3. Build the Alfred workflow **after** `npm install`:

   ```sh
   ./build.sh
   open dist/PathFind.alfredworkflow
   ```

   If `experimental/node_modules` exists during packaging, the build includes
   it so the imported workflow has the native Node dependencies. If absent,
   `pfx` / `pfxd` will not work until the dependencies are installed inside
   the imported experimental workflow directory.

4. Open the imported experimental workflow's Configuration in Alfred.
   Copy the same Include paths, excludes, hidden-file and max-depth settings
   as the main workflow. Bear in mind that each indexer has **different**
   support for these flags; this is a comparison, not drop-in parity.

   If Alfred cannot locate Node or fsearch from its constrained launch
   environment, install Node in /opt/homebrew/bin or /usr/local/bin and
   fsearch in ~/.local/bin (or set PATHFIND_FFF_NODE_BIN and
   PATHFIND_FSEARCH_BIN as workflow environment variables).

## Benchmark

Before benchmarking FFF, prime its index **using the same Include paths**
as the Alfred experimental workflow:

```sh
export PATHFIND_PATHS="$HOME/Documents
$HOME/Library/CloudStorage"
node experimental/fff-client.mjs warm

python3 experimental/benchmark.py 'tax/2025' --mode directory \
  --runs 15 --expected "$HOME/Google Drive/Tax/2025"
```

The Python script measures the **entire Alfred Script Filter** invocation,
including process startup, search, path scoring, and JSON generation. It
prints first-call, median and p95 timings, result counts and the expected
item's final rank. For fair comparisons, use matching search roots and
several queries. Match **relevance and recall**, not just response time.

The FFF daemon can be stopped with:

```sh
node experimental/fff-client.mjs stop
```

## Important semantic differences

- **fd**: enumerates files on each keystroke; no persistent index. Search
  roots, max depth, symlink and .gitignore options are honored as before.
- **fsearch**: system-wide index, accessed through the CLI's JSON output.
  An `in:` scope is applied to each configured root. Its search requires
  a query word to match the result basename; some ancestor-only matches are
  omitted. It supports directory filtering but not all of fd's traversal
  options. The fsearch CLI auto-starts its daemon.
- **fff**: an SDK, not a direct CLI replacement. This branch adds a local
  Node socket daemon and keeps the scan and watcher resident, so warm queries
  can be compared fairly. It can differ in gitignore, symlink, hidden-file
  and query semantics. FFF's filename/path matching and its native sorting
  determine which 500 candidates reach PathFind's common scorer.
- All experimental adapters currently fall back to `fd` for the original
  PathFind `in:` **Spotlight content** syntax (a different feature from
  fsearch's `in:` directory-scope filter).
- The experiment does not yet verify all search-engine corner cases for
  configured exclusions, multiple scopes, or symlinked cloud folders.

## Troubleshooting

Run the Script Filter debugger in Alfred. Errors from the native backends
appear on stderr. An absent `fsearch` executable or a missing FFF Node
library cannot be fixed by the JSON scorer; install/resolve that backend.

For command-line troubleshooting from this repo (using its own paths):

```sh
export PATHFIND_PATHS="$HOME/Documents"
TYPE_OVERRIDE=directory ./experimental/search.sh fsearch 'tax/2025'
TYPE_OVERRIDE=directory ./experimental/search.sh fff 'tax/2025'
```
