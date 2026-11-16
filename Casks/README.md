# Homebrew casks

This repository is the public Homebrew tap `maxmeis/hypermug`. The new Stable and Canary casks are not available yet. Stable `v0.1` is source only, with no app ZIP or `Casks/hypermug.rb`. Canary `v0.0.0-canary.3` has a compiled ZIP and cask asset, but [pull request #15](https://github.com/maxmeis/hypermug/pull/15) must be merged before its cask is on the default branch. After that merge, install Canary with:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/hypermug
brew install --cask maxmeis/hypermug/hypermug@canary
```

Homebrew follows the tap's default branch; there is no branch argument to `brew tap`. Each compiled release proposes a cask update for review. A future compiled Stable release and merged cask pull request are required for `hypermug`. There is no placeholder cask or invented checksum.

Stable and Canary share an app identity, so uninstall one before installing the other. The older `hypermug@nightly.rb` remains historical and is not updated by the new pipeline. Neither channel requires the archived external `maxmeis/homebrew-formulae` tap: external publication is disabled by default and only runs when an owner explicitly sets `PUBLISH_EXTERNAL_TAP=true` for a writable destination.
