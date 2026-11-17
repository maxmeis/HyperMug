# HyperMug

HyperMug is a macOS menu bar utility that combines a Hyperkey, Caffeine, trackpad swipe shortcuts, and mouse-button remapping.

## Install

Requires macOS 14 Sonoma or later on Apple Silicon. Install the signed, notarized **Stable** app with:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/hypermug
brew install maxmeis/hypermug/hypermug
```

For early builds, install `maxmeis/hypermug/hypermug@canary` instead. Stable and Canary stay on separate update feeds; uninstall one before switching to the other. See [Installation](docs/installation.md) for channel choice, updates, permissions, and first-run setup. For a source build, see [Development](docs/development.md).

## Features

- **Caps Lock as Meh or Hyper:** hold for ⌃⌥⌘ or ⌃⌥⇧⌘; tap for Escape.
- **Stay Awake:** open the mug menu with a left or right click and use its checked **Stay Awake** item for this session; the next launch uses your saved preference.
- **Trackpad swipes:** bind three- and four-finger swipes to shortcuts, shell commands, or shared named helpers.
- **Mouse remapping:** map back/forward buttons, the MX Master 3S thumb button and vertical wheel steps to the same actions, and invert wheel scrolling.
- **Secure Input status:** see when macOS blocks keyboard monitoring and which app holds Secure Input.
- **One native window:** **Settings…** (⌘,) opens the TOML editor alongside overview, permissions, conflicts and activity. Validate and save in HyperMug; the TOML file stays the single source of settings. Native notifications report invalid configuration and failed shell actions.

HyperMug requires macOS Accessibility and Input Monitoring permissions for its input features. The app explains each permission in **Doctor… → Permissions**. See [Permissions and troubleshooting](docs/troubleshooting.md).

## Configuration

Settings are stored in `~/.config/hypermug.toml`. The file links to the JSON Schema inside the signed app bundle, so TOML editors such as Taplo or Even Better TOML can validate and complete it. An existing `~/.config/hypermug.json` is migrated automatically once and kept as a backup. See [Configuration](docs/configuration.md) for defaults, shared helpers, validation, [migration](docs/configuration.md#migrating-from-hypermugjson) and the default 10-second shell deadline.

```toml
capsLock = "meh"

[helpers]
nextWorkspace = "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around next"
previousWorkspace = "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around prev"

[mouse.buttons]
back.helper = "previousWorkspace"
forward.helper = "nextWorkspace"

[trackpad.threeFingerSwipe]
left.helper = "nextWorkspace"
right.helper = "previousWorkspace"
```

## Development and contributions

Swift app sources and tests live under `Source/HyperMug/`; repository commit hooks use the root npm tooling. See [Development](docs/development.md) to build, test, and check layer rules, and [CONTRIBUTING.md](CONTRIBUTING.md) for reports and pull requests.

## Releases

Stable releases use owner-selected `vX.Y.Z` tags and can ship a signed, notarized app or source only. Canary builds automatically from app changes on `main` with its own immutable prerelease tags and binary feed. See [Release process](docs/releases.md).
