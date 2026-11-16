# Homebrew casks

This repository is the public Homebrew tap `maxmeis/hypermug`. Stable currently has no compiled app or `Casks/hypermug.rb`. Install the signed Canary app with:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/hypermug
brew install maxmeis/hypermug/hypermug@canary
```

Homebrew follows the tap's default branch; there is no branch argument to `brew tap`. Each compiled release prepares an internal metadata branch, runs required CI, and publishes its verified cask automatically without a release pull request. A future compiled Stable release and successful automatic cask publication are required for `hypermug`. There is no placeholder cask or invented checksum.

Stable and Canary share an app identity, so uninstall one before installing the other. Only Stable (`hypermug`) and Canary (`hypermug@canary`) are offered. The obsolete Nightly cask is removed; historical releases remain immutable. Neither channel requires the archived external `maxmeis/homebrew-formulae` tap: external publication is disabled by default and only runs when an owner explicitly sets `PUBLISH_EXTERNAL_TAP=true` for a writable destination.

The tap remains at the repository root, with app packages in `Casks/` as required by [Homebrew’s tap layout](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap#casks). `Formula/` is for formula packages; this signed macOS `.app` is a cask. Homebrew detects it in the fully qualified `brew install` command above, so `--cask` is optional. To inspect or fetch before installing, trust just that package with `brew trust --cask maxmeis/hypermug/hypermug@canary`.
