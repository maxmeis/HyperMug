cask "hypermug@canary" do
  version "0.0.8"
  sha256 "00198c631703f288cc5150cf461f2bc7df454e94b92e72f3c5ebe9dedc4d474f"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.0.0-canary.8/HyperMug-0.0.0-canary.8.zip"
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
