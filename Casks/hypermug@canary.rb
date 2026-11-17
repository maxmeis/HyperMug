cask "hypermug@canary" do
  version "0.0.15"
  sha256 "60ed7aa44be40ad253587d306814fbb5b77c04f445456bcdbd58fb9fad353ca6"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.0.0-canary.15/HyperMug-0.0.0-canary.15.zip"
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
