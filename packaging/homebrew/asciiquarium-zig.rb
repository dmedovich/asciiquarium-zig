class AsciiquariumZig < Formula
  desc "Zig port of Asciiquarium with configurable fish names"
  homepage "https://github.com/dmedovich/asciiquarium-zig"
  url "https://github.com/dmedovich/asciiquarium-zig/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_SOURCE_SHA256"
  license "GPL-2.0-or-later"

  depends_on "zig" => :build

  def install
    system "zig", "build", *std_zig_args(release_mode: :safe)
    bin.install "zig-out/bin/asciiquarium-zig"
    pkgshare.install "fish.conf"
  end

  test do
    output = shell_output("#{bin}/asciiquarium-zig 2>&1")
    assert_match "Run asciiquarium-zig in a terminal.", output
  end
end
