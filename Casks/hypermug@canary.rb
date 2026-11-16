cask "hypermug@canary" do
  version "0.0.5"
  sha256 "35ee58469c84e099ab18b482d9314725897cb1cc6a509abad46b6476e4177662"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.0.0-canary.5/HyperMug-0.0.0-canary.5.zip"
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
