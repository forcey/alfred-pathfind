![](./icon_s.png)

# PathFind

**PathFind** is a workflow that aims to quickly and thoroughly search your filesystem for files and folders matching keyword(s) in *any part* of the filename or enclosing path.

This means that if you search for “annual report 2026”, both of the files below would appear in the results:

- /Users/joe/Downloads/Annual **Report**s/for review/**2026**-version1.pdf
- /Users/joe/Desktop/Shareholder **report** (**Annual**) - **2026**.docx

Searches are case-insensitive, and the order in which you enter your search terms is not important. The search terms can be plain strings or [regular expressions](https://regex101.com/r/QmVP21/1). The workflow **does not rely on Spotlight** to provide its results.

You can pass *quoted strings* to be more explicit with your queries, e.g. "annual report" will NOT match a file named "annual sales report". Only **double-quotes** are considered—single-quotes are parsed as normal punctuation. Non-quoted strings will be split on spaces (which has always been the case).

## Search backends and keywords

This fork adds two indexed search backends alongside the original
[fd](https://github.com/sharkdp/fd) backend. All three feed paths to the same
Alfred result formatter and **path-aware ranking**: an exact path such as
`Tax/2025` is preferred to loosely related descendants, and generated
directories such as `__pycache__` and `node_modules` are heavily demoted
unless explicitly requested.

| Files and folders | Folders only | Backend | How it searches |
| --- | --- | --- | --- |
| `pf` | `pfd` | [fd](https://github.com/sharkdp/fd) (original) | Walks the selected search roots on each query; no separate index. |
| `fd` | `fdd` | [fd](https://github.com/sharkdp/fd) (comparison alias) | Same implementation as `pf` / `pfd`. |
| `fs` | `fsd` | [fsearch](https://github.com/noahdunnagan/fsearch) | Uses a persistent macOS-wide name index and a background daemon. |
| `ff` | `ffd` | [fff](https://github.com/dmtrKovalenko/fff) | Uses an in-memory index via the [Node SDK](https://github.com/dmtrKovalenko/fff/tree/main/packages/fff-node) and a small persistent local process. |

Examples: `pfd tax/2025`, `fsd tax/2025`, or `ffd tax/2025`.
The original `pff` (files only), `pfc` (active Finder folder), and
auxiliary triggers remain available; the normal `pf` keyword is configurable.

**The engines are not semantically identical.** Their fuzzy matching,
ignore rules, symlink handling, and candidate limits can differ. For example,
`fsearch` may omit a result when none of the search words matches its own
filename, even though the words appear in ancestor directories. The shared
ranking only orders candidates each backend actually returns. Queries using
PathFind's `in:` *Spotlight content* syntax fall back to the original fd
implementation with Spotlight content filtering, not indexed content search
from fsearch or fff. Regex and quoting behavior described below principally
refer to the original fd backend.

### Install the workflow and required tools (macOS)

Requirements: **Alfred 5.6.1+**, [Homebrew](https://brew.sh/), and (for
`ff` / `ffd`) **Node.js 18+** with npm. Rust/Cargo is needed only to
build `fsearch` from source.

```sh
git clone https://github.com/forcey/alfred-pathfind.git
cd alfred-pathfind

# Mandatory for the original workflow and its shared result formatter:
brew install fd gawk jq

# For fff: install the pinned Node SDK and native platform dependency.
npm install --prefix experimental

# Build an installable Alfred workflow with the FFF SDK bundled.
./build.sh
open dist/PathFind.alfredworkflow
```

`fsearch` is installed separately (see below), while the `fff` SDK must be
installed **before building** so `build.sh` can include
`experimental/node_modules` in the `.alfredworkflow` package. You can omit
the optional FFF npm install if you only use fd/fsearch; the `ff` triggers
will not work without that SDK.

The package has the **original PathFind bundle ID**
(`com.luckman212.pathfind`), so importing it updates your existing PathFind
workflow. If you installed an older, separately named *PathFind Search Engine
Experiment* workflow, remove/disable it in Alfred to avoid duplicate triggers.

In **Alfred Preferences → Workflows → PathFind → Configure Workflow**, set
the **Include paths** (one per line), for example:

```text
~/Documents
~/Downloads
~/Google Drive
~/Library/Mobile Documents/com~apple~CloudDocs
```

A symlinked `~/Google Drive` pointing to
`~/Library/CloudStorage/...` is supported: the indexed backend adapters
resolve configured search roots to their physical paths. Alfred's workflow
configuration is independent of any `PATHFIND_PATHS` variable exported in
your Terminal.

### fd: install and update

**Upstream:** [sharkdp/fd](https://github.com/sharkdp/fd)

```sh
brew install fd          # first installation
brew upgrade fd          # later upgrades
fd --version
```

The existing `pf` / `pfd` and new `fd` / `fdd` keywords use the same
fd installation. There is no fd index to initialize or restart. `gawk` and
`jq` are shared dependencies; update them with `brew upgrade gawk jq`
when desired.

### fsearch: install and update

**Upstream:** [noahdunnagan/fsearch](https://github.com/noahdunnagan/fsearch)

`fsearch` is a separate Rust binary plus a macOS LaunchAgent named
`mt.nd.fsearch`. Install [Rust/Cargo](https://rustup.rs/) if needed, then:

```sh
git clone https://github.com/noahdunnagan/fsearch.git
cd fsearch
cargo build --release
./target/release/fsearch install --login
~/.local/bin/fsearch status
```

The `install --login` command copies the binary to
`~/.local/bin/fsearch`, registers it to run at login, and restarts the
LaunchAgent. In **System Settings → Privacy & Security → Full Disk Access**,
add and enable the **installed** `~/.local/bin/fsearch` executable (not just
Terminal) if you need results from Google Drive, Documents, etc.
Verify `"full_disk_access": true` in `fsearch status`.

To **update fsearch**, run these commands from your existing *fsearch* source
checkout (not the PathFind checkout):

```sh
git pull --ff-only
cargo build --release
./target/release/fsearch install --login
~/.local/bin/fsearch status
```

**Check Full Disk Access again after updating.** The install command replaces
the executable rather than modifying it in place, so macOS might not retain
its existing permission. A restarted daemon normally reuses its saved index.

If Google Drive is missing even after granting Full Disk Access, the saved
index may have been created when that directory was inaccessible. After
confirming Full Disk Access, you can force a one-time rebuild (keeping a
backup):

```sh
launchctl bootout "gui/$(id -u)/mt.nd.fsearch"
INDEX="$HOME/Library/Application Support/FSearch/index.bin"
if [ -f "$INDEX" ]; then
  mv "$INDEX" "$INDEX.bak.$(date +%Y%m%d-%H%M%S)"
fi
launchctl bootstrap "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/mt.nd.fsearch.plist"
~/.local/bin/fsearch status
```

Wait for the initial scan to finish, then confirm scoped results:

```sh
ROOT="$(cd -P "$HOME/Google Drive" && pwd)"
~/.local/bin/fsearch "tax kind:dir in:\"$ROOT\" limit:100" --json |
  jq -r '.hits[].path'
```

**An fsearch update does not require rebuilding PathFind's Alfred package**
unless the adapter/scripts in this repository have changed.

### fff: install and update

**Upstream:** [dmtrKovalenko/fff](https://github.com/dmtrKovalenko/fff)
and [the `@ff-labs/fff-node` SDK](https://github.com/dmtrKovalenko/fff/tree/main/packages/fff-node)

PathFind uses `@ff-labs/fff-node`, **not** the separate `fff-mcp`
executable or Neovim plugin. Our `experimental/fff-client.mjs` starts a
persistent local Node process that maintains the index for the configured
roots across Alfred queries.

Install the **version pinned in `experimental/package.json`** from your
PathFind checkout:

```sh
npm install --prefix experimental
```

To deliberately **upgrade the FFF SDK to the newest published version**:

```sh
# From the PathFind checkout:
npm install --prefix experimental --save-exact @ff-labs/fff-node@latest
node experimental/fff-client.mjs stop

# Rebuild so Alfred gets the new native SDK bundle:
./build.sh
open dist/PathFind.alfredworkflow
```

The first command updates the SDK dependency in
`experimental/package.json` as well as local `node_modules`. Commit that
dependency change to your fork if you want future builds to use it.
For routine workflow rebuilds, plain `npm install --prefix experimental`
uses the pinned version; it **does not** automatically upgrade that version.
The background FFF process automatically restarts on the next search after
being stopped.

If `ff` says **Node not accessible**, run `command -v node` in Terminal
and paste the absolute executable path into Alfred's **Configure Workflow →
Node executable (FFF)** setting. GUI apps often do not inherit shell-managed
Node paths. To prime or reset a local FFF index, see
[the development and benchmark guide](experimental/README.md).

### Update PathFind itself

From the **PathFind** checkout, pull the latest workflow scripts, re-install
the pinned FFF SDK if necessary, rebuild, and import:

```sh
git switch main
git pull --ff-only
npm install --prefix experimental
./build.sh
open dist/PathFind.alfredworkflow
```

Unlike `fsearch`, PathFind itself is updated by importing a new
`.alfredworkflow` package; simply pulling GitHub changes does **not**
modify the workflow currently installed in Alfred. Check your saved Include
paths after reimporting, and remove the retired experimental workflow if
it is still installed.

For engine-specific performance tests and diagnostics, see
[experimental/README.md](experimental/README.md).

## Configuration

You can customize various options via the Configure Workflow button, or by activating the `:pf` keyword. Most are self-explanatory, I will attempt to better document them in the near future.

The most important thing to configure are the **Paths** (include, exclude, etc). Enter one path per line. Trailing slashes are not required. For example:

```
~/Downloads
~/Desktop
~/Documents
~/Library/CloudStorage
/Volumes/development/area51
```

Another potentially useful section is **Path substitutions**. Here, you can specify a list of pathnames or partial pathnames to be translated (typically _shortened_) so that deeply-nested filenames will be more visible in the subtitles. You specify the "real" path substring on the left, and the shortened "display" name on the right, separated by the pipe character `|`.

For example, you might want to shorten a path like **~/Documents/Book Reports/2025/Biology 201** to just **📕BR2025**. To do that, you would configure that area as:

```
~/Documents/Book Reports/2025/Biology 201|📕2025
```

## 🐞 Bug with Exclude (but not _our_ bug)

Due to a bug in `fd`, the **Exclude** feature does not always work as expected. You may want to read and subscribe to https://github.com/sharkdp/fd/issues/851 for updates on that. The main issue is that absolute paths (e.g. `/Users/joe/test/foo`) are not handled properly. There are 2 ways to work around this:

1. Use relative paths: e.g. instead of `/Users/joe/test/foo` use just `test/foo`
2. Use a `.gitignore` file and enable the **Respect .gitignore** checkbox

## Usage

Activate one of the trigger keywords. The [backend keyword table](#search-backends-and-keywords) above lists all eight engine selectors:
- `pf` for normal mode
- `pfd` to search Folders (directories) only
- `pff` to search Files only
- `pfc` to search exclusively in the current active (frontmost) Finder window (its path does NOT need to be included in your workflow config search scope ahead of time)

You can also leverage Spotlight **in addition to** the filename-based search capabilities! To use Spotlight to query for files based on their *contents*, prefix your search term(s) with `in:`. For example, to find PDF files with the word "contract" in the filename, and the words "agreed" and "November" in the *contents*, use Alfred query `contract pdf in:agreed in:november` (the Spotlight terms are also case-insensitive).

## CLI

The workflow comes with a commandline tool that can be run outside of Alfred, if you ever find the need search from a Terminal. The script name is `pathfind.sh` and you can conveniently create a symlink to it at `/usr/local/bin` by running this workflow with the trigger keyword `:pfcli`.

During the installation, you may be prompted for your password so the workflow can create the `/usr/local/bin` directory and create the symlink so the command is available in your shell. You may also be prompted to allow Alfred to "control Terminal.app" — you should allow this so that the final Terminal Command step can complete.

After it's installed, you can type `pathfind <word1> [word2...]` from any shell to get the results in text format.

![](./enable_automation.png)

## ⚠️Potential Gotchas

- Make sure your defined trigger keywords don't conflict with any from Alfred's native Features > File Search area!
- Enabling the **Follow symlinks** option can significantly slow down searches. If you need this option but experience poor performance, try adjusting **Max depth**, or use a smaller search scope (fewer folders, or more specific query)

## Inspiration

The workflow was inspired by [this post](https://www.alfredforum.com/topic/22886-locating-a-document-by-searching-for-words-that-are-in-the-documents-filepath/). Thank you @achieve927 for the idea!
