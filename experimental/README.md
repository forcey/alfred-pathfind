# PathFind search-engine implementations and benchmarking

The `experimental/` source directory contains the optional indexed search
backends used by the **main PathFind workflow**. These components remain
optional even though the Alfred keywords ship together.

| Keywords | Backend | Mode |
|---|---|---|
| `pf` / `pfd` | original fd | mixed / folders |
| `fd` / `fdd` | fd baseline | mixed / folders |
| `fs` / `fsd` | fsearch | mixed / folders |
| `ff` / `ffd` | fff | mixed / folders |

The workflow bundle ID is `com.luckman212.pathfind` (the original), so
installing the package **updates the existing PathFind workflow**.
Uninstall the obsolete `PathFind Search Engine Experiment` workflow if it
is still installed alongside it.

## Installation on macOS

For complete initial installation and backend **upgrade instructions**,
see the [main README](../README.md#search-backends-and-keywords). The steps
below are for developing or benchmarking the indexed adapters.

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
   **Full Disk Access matters for this test**: fsearch explicitly excludes
   ~/Library/CloudStorage, Documents, Desktop, and Downloads without it.
   In System Settings > Privacy & Security > Full Disk Access, add
   ~/.local/bin/fsearch, then restart the daemon. Its old index may still
   omit folders indexed before permissions were granted; if so, stop the
   daemon before safely moving aside
   ~/Library/Application Support/FSearch/index.bin to force a new crawl.
   Check `fsearch status` for `"full_disk_access": true`.
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
   `ff` / `ffd` will not work until the dependencies are installed inside
   the imported PathFind workflow directory.

4. Open the imported PathFind workflow's Configuration in Alfred.
   Verify the Include paths, excludes, hidden-file and max-depth settings
   in your existing PathFind workflow. **A `PATHFIND_PATHS` export in Terminal does not
   configure Alfred**. If you see zero hits in Alfred despite successful
   command-line tests, check the imported PathFind workflow configuration.
   The `~/Google Drive` symlink is supported: the adapters resolve it to
   its canonical CloudStorage target before searching.
   Bear in mind that each indexer has **different** support for these flags;
   this is a comparison, not drop-in parity.

   If Alfred cannot find Node on its restricted GUI PATH, paste the output
   of `command -v node` in **Configure Workflow → Node executable (FFF)**.
   The fsearch CLI is installed to `~/.local/bin/fsearch` by its upstream
   `install --login` command.

## Benchmark

Before benchmarking FFF, prime its index **using the same Include paths**
as the Alfred PathFind workflow:

```sh
export PATHFIND_PATHS="$HOME/Documents
$HOME/Library/CloudStorage"
node experimental/fff-client.mjs warm

python3 experimental/benchmark.py 'tax/2025' --mode directory \
  --runs 15 --expected-suffix "Tax/2025"
```

The Python script measures the **entire Alfred Script Filter** invocation,
including process startup, search, path scoring, and JSON generation. It
prints first-call, median and p95 timings, result counts and the expected
item's final rank. `--expected-suffix` uses a path-tail comparison (marked
with an asterisk) when Google Drive Finder aliases obscure filesystem identity.
For fair comparisons, use matching search roots and
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

## Diagnosing an empty Alfred search

The indexed Script Filter shows an error item if a backend fails,
including messages about missing Full Disk Access. If it simply says
"Nothing found", the subtitle shows which Include paths Alfred actually used.

Try `ffd tax/2025`, `fsd tax/2025`, and `fdd tax/2025` with identical
Include paths. The Terminal `export PATHFIND_PATHS=...` only influences
terminal commands; Alfred has its own workflow configuration. If
`fsearch status` says `full_disk_access: false`, it cannot search
Google Drive CloudStorage. When changing its permissions, restart it and
rebuild the index if those paths remain missing.

After pulling changes from `main`, run `npm install --prefix experimental`
(if needed) followed by `./build.sh`, then double-click
`dist/PathFind.alfredworkflow` to update the installed PathFind workflow.
The running FFF service can be restarted with
`node experimental/fff-client.mjs stop` before warming the index again.
