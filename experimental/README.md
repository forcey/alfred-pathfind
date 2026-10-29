# PathFind search-engine implementations and benchmarking

The `experimental/` source directory contains the optional indexed fff search
backend used by the **main PathFind workflow**. It remains optional even
though the Alfred keywords ship together.

| Keywords | Backend | Mode |
|---|---|---|
| `pf` / `pfd` | original fd | mixed / folders |
| `fd` / `fdd` | fd baseline | mixed / folders |
| `ff` / `ffd` | fff | mixed / folders |

The workflow bundle ID is `com.luckman212.pathfind` (the original), so
installing the package **updates the existing PathFind workflow**.
Uninstall the obsolete `PathFind Search Engine Experiment` workflow if it
is still installed alongside it.

## Installation on macOS

For complete initial installation and backend **upgrade instructions**,
see the [main README](../README.md#search-backends-and-keywords). The steps
below are for developing or benchmarking the indexed adapter.

1. Install Node.js 18+ and the FFF SDK into the **experiment directory**:

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

2. Build the Alfred workflow **after** `npm install`:

   ```sh
   ./build.sh
   open dist/PathFind.alfredworkflow
   ```

   If `experimental/node_modules` exists during packaging, the build includes
   it so the imported workflow has the native Node dependencies. If absent,
   `ff` / `ffd` will not work until the dependencies are installed inside
   the imported PathFind workflow directory.

3. Open the imported PathFind workflow's Configuration in Alfred.
   Verify the Include paths, excludes, hidden-file and max-depth settings
   in your existing PathFind workflow. **A `PATHFIND_PATHS` export in Terminal does not
   configure Alfred**. If you see zero hits in Alfred despite successful
   command-line tests, check the imported PathFind workflow configuration.
   The `~/Google Drive` symlink is supported: the adapter resolves it to
   its canonical CloudStorage target before searching.
   Bear in mind that fff has **different** support for these flags;
   this is a comparison, not drop-in parity.

   If Alfred cannot find Node on its restricted GUI PATH, paste the output
   of `command -v node` in **Configure Workflow → Node executable (FFF)**.

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
- **fff**: an SDK, not a direct CLI replacement. This branch adds a local
  Node socket daemon and keeps the scan and watcher resident, so warm queries
  can be compared fairly. It can differ in gitignore, symlink, hidden-file
  and query semantics. FFF's filename/path matching and its native sorting
  determine which 500 candidates reach PathFind's common scorer.
- The fff adapter falls back to `fd` for the original PathFind `in:`
  **Spotlight content** syntax.
- The experiment does not yet verify all search-engine corner cases for
  configured exclusions, multiple scopes, or symlinked cloud folders.

## Troubleshooting

Run the Script Filter debugger in Alfred. Errors from the native backends
appear on stderr. A missing FFF Node library cannot be fixed by the JSON
scorer; install/resolve that backend.

For command-line troubleshooting from this repo (using its own paths):

```sh
export PATHFIND_PATHS="$HOME/Documents"
TYPE_OVERRIDE=directory ./experimental/search.sh fff 'tax/2025'
```

## Diagnosing an empty Alfred search

The indexed Script Filter shows an error item if a backend fails,
such as a missing Node executable. If it simply says
"Nothing found", the subtitle shows which Include paths Alfred actually used.

Try `ffd tax/2025` and `fdd tax/2025` with identical Include paths. The
Terminal `export PATHFIND_PATHS=...` only influences terminal commands;
Alfred has its own workflow configuration.

After pulling changes from `main`, run `npm install --prefix experimental`
(if needed) followed by `./build.sh`, then double-click
`dist/PathFind.alfredworkflow` to update the installed PathFind workflow.
The running FFF service can be restarted with
`node experimental/fff-client.mjs stop` before warming the index again.
