cask "hypermug" do
  version "0.3.2"
  sha256 "b8cf33b3fbdc7f53e9ea15e22f9c4dfd01d798247f97e0ed357fe36f90cd4df3"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.3.2/HyperMug-0.3.2.zip"
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
