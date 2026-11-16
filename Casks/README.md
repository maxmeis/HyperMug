# Homebrew casks

This repository is the public Homebrew tap `maxmeis/hypermug`. Stable and Canary casks become installable after their first compiled release and generated cask pull request are reviewed and merged into the default branch. Source-only Stable releases do not change either cask:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/HyperMug
brew install --cask maxmeis/hypermug/hypermug
```

Homebrew follows the tap's default branch; there is no branch argument to `brew tap`. Each compiled release proposes a cask update for review. Merge that pull request to make the new version available from this tap. There is no placeholder cask or invented checksum.
Opt in to Canary with `brew install --cask maxmeis/hypermug/hypermug@canary` once its cask is merged. Stable and Canary share an app identity, so uninstall one before installing the other. The older `hypermug@nightly.rb` remains historical and is not updated by the new pipeline. Neither channel requires the archived external `maxmeis/homebrew-formulae` tap: external publication is disabled by default and only runs when an owner explicitly sets `PUBLISH_EXTERNAL_TAP=true` for a writable destination.
