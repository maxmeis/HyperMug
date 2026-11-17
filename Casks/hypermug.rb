cask "hypermug" do
  version "0.3.0"
  sha256 "4ef2393571495f88b148abae6b3987a495ba4fdc6d8d67ab13d6aa50e2c8eaa0"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.3.0/HyperMug-0.3.0.zip"
  name "HyperMug"
  desc "Caps Lock remapping, caffeine, and mouse controls for macOS"
  homepage "https://github.com/maxmeis/hypermug"

  livecheck do
    skip "GitHub release assets are published by production automation"
  end

  auto_updates true
  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64
  conflicts_with cask: "hypermug@canary"
  conflicts_with cask: "hypermug@nightly"
  app "HyperMug.app"
end
