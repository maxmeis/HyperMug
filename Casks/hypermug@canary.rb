cask "hypermug@canary" do
  version "0.0.13"
  sha256 "3a27a8d5e6543adf05d96f88bd366dcb85b4581e9cc136c81a53d1f49f24e55f"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.0.0-canary.13/HyperMug-0.0.0-canary.13.zip"
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
