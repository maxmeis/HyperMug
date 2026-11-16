cask "hypermug@nightly" do
  version "0.0.1"
  sha256 "d26895811c14a79b138267f4a41d23b46ff93831fc9e4f6b8129e5747ccf3562"

  url "https://github.com/maxmeis/HyperMug/releases/download/v0.0.0-beta.1/HyperMug-0.0.0-beta.1.zip"
  name "HyperMug"
  desc "Caps Lock remapping, caffeine, and mouse controls for macOS"
  homepage "https://github.com/maxmeis/HyperMug"

  livecheck do
    skip "GitHub release assets are published by channel automation"
  end

  auto_updates true
  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64
  conflicts_with cask: "hypermug"
  app "HyperMug.app"
end
