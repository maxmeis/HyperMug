# Homebrew casks

This repository is the public Homebrew tap `maxmeis/hypermug`. Stable currently has no compiled app or `Casks/hypermug.rb`. After a compiled Canary release and its automatic cask publication complete, install Canary with:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/hypermug
brew install --cask maxmeis/hypermug/hypermug@canary
```

Homebrew follows the tap's default branch; there is no branch argument to `brew tap`. Each compiled release prepares an internal metadata branch, runs required CI, and publishes its verified cask automatically without a release pull request. A future compiled Stable release and successful automatic cask publication are required for `hypermug`. There is no placeholder cask or invented checksum.

Stable and Canary share an app identity, so uninstall one before installing the other. The older `hypermug@nightly.rb` remains historical and is not updated by the new pipeline. Neither channel requires the archived external `maxmeis/homebrew-formulae` tap: external publication is disabled by default and only runs when an owner explicitly sets `PUBLISH_EXTERNAL_TAP=true` for a writable destination.
