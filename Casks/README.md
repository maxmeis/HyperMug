# Homebrew casks

This repository is the public stable Homebrew tap `maxmeis/hypermug`. The cask becomes installable after the first production release has been published and its generated cask pull request has been reviewed and merged into the default branch:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/HyperMug
brew install --cask maxmeis/hypermug/hypermug
```

Homebrew follows the tap's default branch; there is no branch argument to `brew tap`. Each stable release proposes a cask update for review. Merge that pull request to make the new version available from this tap. This directory intentionally contains no placeholder cask or invented checksum.
