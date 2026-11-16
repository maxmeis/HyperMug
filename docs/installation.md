# Installation

## Homebrew

HyperMug offers Stable and opt-in Canary Homebrew casks. Each becomes installable only after its first compiled release and generated cask pull request is merged into this repository's default branch. A source-only Stable release has no app ZIP or new cask; use [Development](development.md) to build it locally.

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/HyperMug
brew install --cask maxmeis/hypermug/hypermug
```

For Canary, use `brew install --cask maxmeis/hypermug/hypermug@canary` after that cask is available. The channels use separate signed Sparkle feeds and keys. Stable installations follow Stable; Canary installations follow Canary. They share the same bundle identity and config file, so uninstall the current channel before installing the other. Existing `hypermug@nightly` users can migrate manually by uninstalling the old cask, then installing Canary; the historical beta feed remains separate.

Homebrew installs the signed application. Set `"autoUpdate": false` in `~/.config/hypermug.json` to disable scheduled checks; **Check for Updates…** remains available in the menu. Homebrew casks declare `auto_updates true`, so ordinary upgrades leave updates to Sparkle. To explicitly upgrade Stable with Homebrew, run:

```sh
brew upgrade --cask --greedy maxmeis/hypermug/hypermug
```

## First run and permissions

HyperMug creates `~/.config/hypermug.json` with defaults at first launch. No settings are imported from other apps. The app requests Accessibility permission and prompts for Input Monitoring when needed. Review or grant them from **Doctor… → Permissions** in the menu. Relaunch HyperMug after granting Input Monitoring; the privileges window has a restart button.

- **Accessibility** enables the keyboard and mouse event tap used by Caps Lock Meh/Hyper, side-button mappings, and scroll inversion.
- **Input Monitoring** enables raw Caps Lock detection and access to the MX Master 3S thumb button.

Permission grants are tied to the app's code signature. Release builds use Developer ID signing. Local `make build` uses the persistent local signing identity; see [Development](development.md) for a persistent local signing identity when permission continuity matters.

## Trackpad setup

macOS's native swipe actions can conflict with custom bindings. Open **Doctor… → Conflicts** from the HyperMug menu and follow its instructions. Disable conflicting full-screen app, Mission Control, and App Exposé swipes in **System Settings → Trackpad → More Gestures**. If three-finger dragging is enabled, turn it off under **Accessibility → Pointer Control → Trackpad Options**. HyperMug does not change these macOS settings for you.

## Other input tools

Quit Hyperkey or other Caps Lock remappers while HyperMug is using Meh/Hyper mode. Do not run OpenLogi or Logi Options+ while using MX Master 3S thumb-button remapping; both tools may compete for the same button. See [Troubleshooting](troubleshooting.md) for behavior and recovery details.

## Moving from MyMug

HyperMug does not import MyMug settings. To move manually:

1. Disable MyMug's login item, then quit MyMug.
2. Move `~/.config/mymug.json` to `~/.config/hypermug.json` and change `$schema` to `./hypermug.schema.json`.
3. Review the file for settings you no longer want. HyperMug ignores unknown keys.
4. Launch HyperMug and grant Accessibility and Input Monitoring again; macOS permission grants belong to the app identity and signature.

The current HyperMug app creates `hypermug.schema.json` itself. Do not run MyMug and HyperMug together while they could both handle the same input.
