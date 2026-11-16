# HyperMug

HyperMug is a macOS menu bar utility that combines a Hyperkey, Caffeine, trackpad swipe shortcuts, and mouse-button remapping.

## Install

Stable currently has no compiled app or cask. Canary has signed, notarized app releases. Install Canary with:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/hypermug
brew install maxmeis/hypermug/hypermug@canary
```

Stable Homebrew installation requires a future compiled Stable release and successful automatic cask publication. See [Installation](docs/installation.md) for channel choice, updates, permissions, and first-run setup. For a source build, see [Development](docs/development.md).

## Features

- **Caps Lock as Meh or Hyper:** hold for ⌃⌥⌘ or ⌃⌥⇧⌘; tap for Escape.
- **Stay Awake:** open the mug menu with a left or right click and use its checked **Stay Awake** item for this session; the next launch uses your saved preference.
- **Trackpad swipes:** bind three- and four-finger swipes to shortcuts, shell commands, or shared named helpers.
- **Mouse remapping:** map back/forward buttons and the MX Master 3S thumb button to the same actions, and invert wheel scrolling.
- **Secure Input status:** see when macOS blocks keyboard monitoring and which app holds Secure Input.
- **File-based settings:** **Settings…** (⌘,) opens your JSON configuration; saved edits reload automatically, with native notifications for invalid settings or failed shell actions.

HyperMug requires macOS Accessibility and Input Monitoring permissions for its input features. The app explains each permission in **Doctor… → Permissions**. See [Permissions and troubleshooting](docs/troubleshooting.md).

## Configuration

Settings are stored in `~/.config/hypermug.json`. The file links to the JSON Schema inside the signed app bundle. See [Configuration](docs/configuration.md) for defaults, shared helpers, validation and the default 10-second shell deadline.

## Development and contributions

Swift app sources and tests live under `Source/HyperMug/`; repository commit hooks use the root npm tooling. See [Development](docs/development.md) to build, test, and check layer rules, and [CONTRIBUTING.md](CONTRIBUTING.md) for reports and pull requests.

## Releases

Stable releases use owner-selected `vX.Y.Z` tags and can ship a signed, notarized app or source only. Canary builds automatically from app changes on `main` with its own immutable prerelease tags and binary feed. See [Release process](docs/releases.md).
