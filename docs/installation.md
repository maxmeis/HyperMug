# Installation

## Homebrew

Requires macOS 14 Sonoma or later on Apple Silicon. Install the signed, notarized Production app with:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/hypermug
brew install --cask maxmeis/hypermug/hypermug
```

The tap is this repository. HyperMug is a macOS `.app`, so its package lives in `Casks/`, not `Formula/`. The fully qualified install command selects this cask. For pre-install inspection on Homebrew versions with [tap trust](https://docs.brew.sh/Tap-Trust), use `brew trust --cask maxmeis/hypermug/hypermug` before `brew info` or `brew fetch`.

## Updates

HyperMug Production checks for updates once a day and asks before installing one. Choose **Check for Updates…** in the menu to check now. Set `autoUpdate = false` in the [configuration](configuration.md) to stop the daily check; manual checks still work. Because the cask declares `auto_updates true`, a bare `brew upgrade` skips HyperMug; to update through Homebrew, name the cask as shown below.

Releases after 0.3.1 are signed with a new update key. They are published in a new feed. HyperMug 0.3.0 reads the old feed, which stays at 0.3.0, so it reports no update; 0.3.1 has no updater. If you have 0.3.0 or 0.3.1, run this once; later updates arrive in the app:

```sh
brew upgrade --cask maxmeis/hypermug/hypermug
```

Quit and reopen HyperMug after a Homebrew upgrade. Existing Canary users should uninstall `maxmeis/hypermug/hypermug@canary` before installing Production; historical release assets remain available. Local **HyperMug Dev** is a separate app with its own settings and permissions and can be installed beside Production. Build it with `make dev`; see [Development](development.md).

## First run and permissions

HyperMug creates `~/.config/hypermug.toml` with defaults at first launch; an existing `~/.config/hypermug.json` from an earlier version is [migrated](configuration.md#migrating-from-hypermugjson) instead. No settings are imported from other apps. The app requests Accessibility permission and prompts for Input Monitoring when needed. Review or grant them from **Doctor… → Permissions** in the menu. Relaunch HyperMug after granting Input Monitoring; the privileges window has a restart button.

- **Accessibility** enables the keyboard and mouse event tap used by Caps Lock Meh/Hyper, side-button and wheel mappings, and scroll inversion.
- **Input Monitoring** enables raw Caps Lock detection and access to the MX Master 3S thumb button.

Permission grants are tied to the app's code signature. Production uses Developer ID signing. Local builds are ad-hoc signed and can need permission grants again after a rebuild; see [Development](development.md).

## Trackpad setup

macOS's native swipe actions can conflict with custom bindings. Open **Doctor… → Conflicts** from the HyperMug menu and follow its instructions. Disable conflicting full-screen app, Mission Control, and App Exposé swipes in **System Settings → Trackpad → More Gestures**. If three-finger dragging is enabled, turn it off under **Accessibility → Pointer Control → Trackpad Options**. HyperMug does not change these macOS settings for you.

## Other input tools

Quit Hyperkey or other Caps Lock remappers while HyperMug is using Meh/Hyper mode. Do not run OpenLogi or Logi Options+ while using MX Master 3S thumb-button remapping; both tools may compete for the same button. See [Troubleshooting](troubleshooting.md) for behavior and recovery details.

## Moving from MyMug

HyperMug does not import MyMug settings. To move manually:

1. Disable MyMug's login item, then quit MyMug.
2. Move `~/.config/mymug.json` to `~/.config/hypermug.json` and remove an obsolete `$schema` reference. HyperMug migrates it to `~/.config/hypermug.toml` on launch.
3. Review the file for settings you no longer want. Remove unknown keys and omit unmapped actions; invalid settings are reported while the last valid configuration remains active.
4. Launch HyperMug and grant Accessibility and Input Monitoring again; macOS permission grants belong to the app identity and signature.

HyperMug links `$schema` to its signed app resource on a valid load; it does not create a schema beside your configuration. Do not run MyMug and HyperMug together while they could both handle the same input.
