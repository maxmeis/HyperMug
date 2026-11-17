cask "hypermug@canary" do
  version "0.0.10"
  sha256 "90e0c46600680c0ad5279985e79d8e0670dffa973081588ccd206e9747957fd8"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.0.0-canary.10/HyperMug-0.0.0-canary.10.zip"
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
