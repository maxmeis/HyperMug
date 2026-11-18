cask "hypermug" do
  version "0.3.1"
  sha256 "1a48009f683f45e24d51730acdf6194c360327d6bc813f8658397d75a8b7914b"

  url "https://github.com/maxmeis/hypermug/releases/download/v0.3.1/HyperMug-0.3.1.zip"
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
