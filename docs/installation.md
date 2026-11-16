# Installation

## Homebrew

Stable currently has no compiled app or `Casks/hypermug.rb`; use [Development](development.md) to build it locally. Canary has signed, notarized app releases. Install Canary with:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/hypermug
brew install maxmeis/hypermug/hypermug@canary
```

The fully qualified `brew install maxmeis/hypermug/hypermug@canary` command detects and trusts only this cask. The optional `--cask` flag gives the same app installation; this app belongs in the root `Casks/` directory, not `Formula/`. To inspect or fetch it before installing on Homebrew versions with [tap trust](https://docs.brew.sh/Tap-Trust), first run `brew trust --cask maxmeis/hypermug/hypermug@canary`; `brew info` and `brew fetch` do not grant that trust automatically. Trusting the whole tap is unnecessary.

Stable Homebrew installation requires a future compiled Stable release and successful automatic cask publication. The channels use separate signed Sparkle feeds and keys. Stable installations follow Stable; Canary installations follow Canary. They share the same bundle identity and config file, so uninstall the current channel before installing the other. Only Stable and Canary are offered. Users of the retired Nightly/beta packages can uninstall their old cask, then install Canary; historical releases are preserved.

Homebrew installs the signed application. Set `"autoUpdate": false` in `~/.config/hypermug.json` to disable scheduled checks; **Check for Updates…** remains available in the menu. Homebrew casks declare `auto_updates true`, so ordinary upgrades leave updates to Sparkle. Once a Stable cask is available, explicitly upgrade it with Homebrew using:

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
2. Move `~/.config/mymug.json` to `~/.config/hypermug.json`; remove an obsolete `$schema` reference.
3. Review the file for settings you no longer want. Remove unknown keys and omit unmapped actions; invalid settings are reported while the last valid configuration remains active.
4. Launch HyperMug and grant Accessibility and Input Monitoring again; macOS permission grants belong to the app identity and signature.

HyperMug links `$schema` to its signed app resource on a valid load; it does not create a schema beside your configuration. Do not run MyMug and HyperMug together while they could both handle the same input.
