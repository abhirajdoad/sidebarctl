# sidebarctl

Manage the macOS **Finder sidebar Favorites** from the command line: list, add, remove and check folders. It's useful for dotfiles, new-Mac setup scripts and provisioning, where dragging folders into Finder by hand isn't practical.

```console
$ sidebarctl add ~/Projects
added: Projects (/Users/you/Projects)

$ sidebarctl add ~/Projects
already in sidebar: /Users/you/Projects

$ sidebarctl list
Applications	/Applications
Desktop	/Users/you/Desktop
Documents	/Users/you/Documents
Downloads	/Users/you/Downloads
Projects	/Users/you/Projects

$ sidebarctl contains ~/Projects && echo yes
yes

$ sidebarctl remove Projects
removed: Projects
```

`list` prints one item per line as `NAME<TAB>PATH`, so it's easy to `cut -f2` or `awk -F'\t'`. For structured output, use `list --json`.

## Requirements

- macOS 11 Big Sur or later. **Tested on macOS 26.3 Tahoe** on Apple Silicon. The binary is universal, so it also runs on Intel Macs.
- To build from source: the Xcode Command Line Tools (`xcode-select --install`).

## Install

### Prebuilt binary

Download `sidebarctl-<version>-macos-universal.tar.gz` and its `.sha256` file from the [latest release](https://github.com/abhirajdoad/sidebarctl/releases/latest), then:

```sh
shasum -a 256 -c sidebarctl-*-macos-universal.tar.gz.sha256   # verify the download
tar -xzf sidebarctl-*-macos-universal.tar.gz
sudo install -m 0755 sidebarctl /usr/local/bin/
```

The binary is ad-hoc signed, not notarized. If you downloaded it with a **web browser** and macOS refuses to run it, remove the quarantine flag (`xattr -d com.apple.quarantine sidebarctl`) or build from source. Downloads made with `curl` aren't quarantined.

### From source

```sh
git clone https://github.com/abhirajdoad/sidebarctl.git
cd sidebarctl
make                 # universal (arm64 + x86_64), ad-hoc signed
make test            # optional: adds and removes a temporary folder in your real sidebar
sudo make install    # → /usr/local/bin/sidebarctl   (or: make install PREFIX=$HOME/.local)
```

### Uninstall

```sh
sudo make uninstall          # or: sudo rm /usr/local/bin/sidebarctl
```

## Commands

| Command | What it does |
|---|---|
| `sidebarctl list [--json]` | Print each Favorite's name and path. `--json` gives an array of `{name, path, url}`; `path` and `url` are `null` for items that can't be resolved. |
| `sidebarctl add <folder> [--name NAME] [--top] [--force]` | Add a folder to the end of Favorites, or to the top with `--top`. If the folder is already there, it does nothing and exits 0; `--force` adds it anyway. The path must be an existing **folder**. |
| `sidebarctl remove <name\|path>` | Remove the first item matching a display name, or failing that, a path. |
| `sidebarctl contains <path>` | Exit 0 if the path is in Favorites, otherwise exit 1. |
| `sidebarctl version` / `help` | — |

A `<path>` can be:
- a normal path: `~` and relative paths are expanded, and `..` and trailing slashes are normalised.
- a `file://` URL, encoded (`%20`) or not. `file://localhost/…` also works.

Paths are compared after normalisation, and `/private/tmp` and `/tmp` are treated as the same. A symlink is stored as the link's own path, not its target.

**Exit codes:**

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Not found (`remove`, `contains`) |
| `2` | Usage error, including a path that doesn't exist or isn't a folder |
| `3` | macOS refused the change, or it didn't take effect |

### Example: a setup script

```sh
set -e
for d in ~/Projects ~/Documents/School ~/Pictures/Screenshots; do
  [ -d "$d" ] && sidebarctl add "$d"     # skips folders that are missing or already present
done
```

## Migrating from mysides

`sidebarctl` started as a rewrite of [mysides](https://github.com/mosen/mysides), but its command line is **not compatible**:

| mysides | sidebarctl |
|---|---|
| `mysides add <name> file:///path/` | `sidebarctl add /path [--name NAME]` |
| `mysides insert <name> <uri>` | `sidebarctl add /path --top` |
| `mysides remove <name>` | `sidebarctl remove <name or path>` |
| `mysides remove all` | Not supported, on purpose |
| `mysides list` prints `name -> file:///…` | `sidebarctl list` prints `name<TAB>/path`, or use `--json` |

## Caveats

- It uses Apple's `LSSharedFileList` API. Apple **deprecated** it in macOS 10.11 and has no public replacement for editing the sidebar. It still works on macOS 26 Tahoe, but a future macOS release could break it. `add` checks its own result and exits 3 if the change didn't take effect.
- Finder usually shows the folder's own name, so `--name` may not change what you see.
- It only manages **Favorites**. It doesn't touch iCloud, Locations or Tags.

## Credits

`sidebarctl` is a rewrite of [mosen/mysides](https://github.com/mosen/mysides) (MIT, © 2016 Mosen), which includes portions by [Adam Strzelecki](https://github.com/nanoant). See [CHANGELOG.md](CHANGELOG.md) for what changed.

## License

MIT. See [LICENSE](LICENSE).
