cask "hypermug" do
  version "0.2.0"
  sha256 "5053e5f98832fe1349eaa155f00c488a044f44289244b6bf7f6dc480069b33f2"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.2.0/HyperMug-0.2.0.zip"
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
