# Homebrew formula template for the `inlay` CLI.
#
# Drop this into your tap repo (github.com/<org>/homebrew-tap) once you've
# tagged a release. Fill in the TODOs: the source tarball URL and its sha256.
# Users then run:  brew install <org>/tap/inlay
#
# Build from source so the bundled registry.json is compiled in.
class Inlay < Formula
  desc "Copy-paste UIKit components for iOS — shadcn/ui for iOS"
  homepage "https://github.com/TODO-org/inlay"
  url "https://github.com/TODO-org/inlay/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "TODO-fill-in-after-tagging"
  license "MIT"
  head "https://github.com/TODO-org/inlay.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    cd "cli" do
      system "swift", "build", "--disable-sandbox", "-c", "release"
      bin.install ".build/release/inlay"
    end
  end

  test do
    assert_match "floating-toolbar", shell_output("#{bin}/inlay list")
  end
end
