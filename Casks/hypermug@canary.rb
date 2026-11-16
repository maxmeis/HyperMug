cask "hypermug@canary" do
  version "0.0.7"
  sha256 "6ce7ac64f713ba3646349e40a203d06b2a45ab4d27aea592524ecb2cde3ecd5f"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.0.0-canary.7/HyperMug-0.0.0-canary.7.zip"
  name "HyperMug"
  desc "Caps Lock remapping, caffeine, and mouse controls for macOS"
  homepage "https://github.com/maxmeis/hypermug"

  livecheck do
    skip "GitHub release assets are published by production automation"
  end

  auto_updates true
  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64
  conflicts_with cask: "hypermug"
  conflicts_with cask: "hypermug@nightly"
  app "HyperMug.app"
end
