# MacBook Cleanup for mobile engineers

`mac-dev-cleanup` shows where developer tooling is using disk space on macOS and cleans the parts you explicitly approve.

The macOS Storage screen often groups Xcode simulator data, package-manager caches, Docker files, and Android images under **System Data**. That number is not very useful on its own. This script checks the relevant directories, estimates what can be removed, and reports the real change in free disk space afterward.

The default command is read-only.

## Quick start

```bash
git clone https://github.com/ionescuaandrei/mac-dev-cleanup.git
cd mac-dev-cleanup
chmod +x mac-dev-cleanup.sh
./mac-dev-cleanup.sh
```

The first run only scans your Mac. To remove the safe caches it finds:

```bash
./mac-dev-cleanup.sh --clean
```

You will see the planned cleanup first and must confirm it before anything is deleted.

## What `--clean` removes

The safe cleanup is limited to files that development tools and applications can recreate:

- Xcode DerivedData
- CocoaPods, npm, Yarn, and Gradle caches
- React Native, TypeScript, and Playwright caches
- Homebrew download cache
- Android Studio and JetBrains caches
- stale VS Code update and extension-package caches
- browser, Spotify, Adobe, Discord, and Claude web caches

It does not remove project folders, source code, `node_modules`, editor settings, Docker volumes, Android SDKs, or macOS system files.

The next build may be slower because some dependencies need to be downloaded again.

## Optional cleanup

Some directories can be large but should not be erased without asking. They have separate flags:

| Command | What it does |
| --- | --- |
| `./mac-dev-cleanup.sh --erase-simulators` | Resets the contents of every iOS simulator. Installed apps and simulator logins are lost. |
| `./mac-dev-cleanup.sh --device-support` | Deletes Xcode's local iOS DeviceSupport files. Xcode recreates them when a physical device is connected. |
| `./mac-dev-cleanup.sh --docker-prune` | Removes unused Docker containers, networks, dangling images, and build cache. Docker volumes are preserved. |

Flags can be combined:

```bash
./mac-dev-cleanup.sh --clean --erase-simulators --device-support --docker-prune
```

Add `--yes` to skip the confirmation prompt, which is useful for a script you have already reviewed:

```bash
./mac-dev-cleanup.sh --clean --yes
```

## What the report means

Before cleanup, the script prints:

- current free disk space
- the size of every safe cleanup target
- the estimated safely reclaimable total
- large optional directories that need manual review

After cleanup, it prints:

- every action it completed
- measured data removed
- disk space before and after
- the actual increase in available space
- anything large that remains

The measured deletion and the change reported by `df` are not always identical. APFS snapshots, sparse files, purgeable storage, and files still held open by an application can affect when space becomes available.

## What it deliberately leaves alone

The script reports these directories but does not automatically delete them:

- Android emulator images, virtual devices, and NDK versions
- Claude local VM bundles
- LM Studio models
- Bun data
- Rust toolchains

Those contain installations or user-selected environments rather than ordinary caches. Remove them using their own tools after checking what you still need.

The script also never:

- asks for `sudo`
- modifies `/System` or `/Library`
- deletes Docker volumes
- deletes source repositories or project dependencies
- performs cleanup when run without an action flag

## Requirements

- macOS
- Bash 3.2 or newer—the version included with macOS works
- Xcode command-line tools for simulator cleanup
- a running Docker Desktop instance for `--docker-prune`

## Contributing

Bug reports and small, focused pull requests are welcome. If you add a cleanup target, it should be clearly regenerable and restricted to a precise path inside the current user's home directory.

## License

MIT. See [LICENSE](LICENSE).
