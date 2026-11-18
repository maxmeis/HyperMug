cask "hypermug" do
  version "0.3.3"
  sha256 "7827a149301066ecd82300b9682c11d6dea271940dbdf3e41e14a99f9c7b3147"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.3.3/HyperMug-0.3.3.zip"
  name "HyperMug"
  desc "Caps Lock remapping, caffeine, and mouse controls for macOS"
  homepage "https://github.com/maxmeis/hypermug"

  livecheck do
    skip "Cask versions follow the published production artifacts"
  end

  auto_updates true
  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64
  conflicts_with cask: "hypermug@canary"
  conflicts_with cask: "hypermug@nightly"
  app "HyperMug.app"
end
