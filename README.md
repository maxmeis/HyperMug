# HyperMug

HyperMug is a macOS menu bar utility that combines a Hyperkey, Caffeine, trackpad swipe shortcuts, and mouse-button remapping.

## Install

The stable Homebrew cask is available after the first compiled production release and its generated cask pull request is merged:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/HyperMug
brew install --cask maxmeis/hypermug/hypermug
```

See [Installation](docs/installation.md) for updates, permissions, and first-run setup. For a source build, see [Development](docs/development.md).

## Features

- **Caps Lock as Meh or Hyper:** hold for ⌃⌥⌘ or ⌃⌥⇧⌘; tap for Escape.
- **Caffeine:** keep the display awake; click the menu bar icon to toggle for the current session.
- **Trackpad swipes:** bind three- and four-finger swipes to shortcuts or shell commands.
- **Mouse remapping:** map back/forward buttons, MX Master 3S thumb button, and scroll direction.
- **Secure Input status:** see when macOS blocks keyboard monitoring and which app holds Secure Input.
- **One JSON config:** edit `~/.config/hypermug.json`; changes reload while the app runs.

HyperMug requires macOS Accessibility and Input Monitoring permissions for its input features. The app explains each permission in **Check Privileges…**. See [Permissions and troubleshooting](docs/troubleshooting.md).

## Configuration

Settings are stored in `~/.config/hypermug.json`. HyperMug creates a JSON Schema alongside it and watches for edits. See [Configuration](docs/configuration.md) for defaults, supported actions, and examples.

## Development and contributions

Swift app sources and tests live under `Source/HyperMug/`; repository commit hooks use the root npm tooling. See [Development](docs/development.md) to build, test, and check layer rules, and [CONTRIBUTING.md](CONTRIBUTING.md) for reports and pull requests.

## Releases

Production releases use stable `vX.Y.Z` tags. The owner chooses either a signed, notarized app with Sparkle updates or a source-only GitHub Release for local builds. See [Release process](docs/releases.md).
