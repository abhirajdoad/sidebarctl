# Changelog

## 1.0.0 (2026-11-08)

First release. It's a rewrite of [mosen/mysides](https://github.com/mosen/mysides), based on its `master` branch.

**Command changes**
- `add` takes a folder path (`~` and relative paths are expanded) or a `file://` URL, encoded or not. It only accepts existing folders and skips ones that are already present (`--force` overrides that). It can add to the top with `--top`. After each add it checks the item really appears.
- `remove` works by display name or by path. There's deliberately no "remove all".
- New `contains <path>` command, which reports through its exit code.
- New `list --json` output. Plain `list` output is now `NAME<TAB>PATH`.
- Arguments are validated strictly: unknown options, empty or invalid UTF-8 paths and names, and extra arguments all exit 2.

**Fixes compared with mysides**
- A memory over-release in `list` that could crash.
- A NULL dereference in `remove` when it was given no argument.

**Build and release**
- Universal build (arm64 and x86_64), ad-hoc signed, for macOS 11 and later.
- A smoke test that runs against the real sidebar and restores it afterwards.
- GitHub Actions CI with least-privilege permissions and pinned actions. Tagged releases publish a tarball with a verifiable SHA-256 checksum.
- Tested on macOS 26.3 Tahoe.
