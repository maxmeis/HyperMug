cask "hypermug@canary" do
  version "0.0.9"
  sha256 "5a99a70533e9996f5dcc479e1058ea8cbad82940838acf5ae81ff836aa7d602f"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.0.0-canary.9/HyperMug-0.0.0-canary.9.zip"
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
