# Homebrew formula for the `inlay` CLI.
#
# This lives in the tap repo github.com/AbhinavAnand241201/homebrew-tap as
# Formula/inlay.rb. Users then run:  brew install AbhinavAnand241201/tap/inlay
#
# Build-from-source so the bundled registry.json is compiled in (no notarization
# needed). Bump `url` + `sha256` on each tagged release.
class Inlay < Formula
  desc "Copy-paste UIKit components for iOS — shadcn/ui for iOS"
  homepage "https://github.com/AbhinavAnand241201/inLAY"
  url "https://github.com/AbhinavAnand241201/inLAY/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "b6748a7ccef09e3f1e0801c313366cd80e8439693125be70d7b026b43f9a047a"
  license "MIT"
  head "https://github.com/AbhinavAnand241201/inLAY.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    cd "cli" do
      system "swift", "build", "--disable-sandbox", "-c", "release"
      # Keep the binary beside its SwiftPM resource bundle (registry.json), then
      # expose it on PATH via a symlink. (The CLI also has a CDN fallback.)
      libexec.install ".build/release/inlay"
      libexec.install ".build/release/inlay_inlay.bundle"
      bin.install_symlink libexec/"inlay"
    end
  end

  test do
    assert_match "floating-toolbar", shell_output("#{bin}/inlay list")
  end
end
