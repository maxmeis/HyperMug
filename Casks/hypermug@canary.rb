cask "hypermug@canary" do
  version "0.0.11"
  sha256 "856c12d5c24c72838040ce531d6b52fe75c16bca1d656c225e670fd9864ba5f5"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.0.0-canary.11/HyperMug-0.0.0-canary.11.zip"
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
