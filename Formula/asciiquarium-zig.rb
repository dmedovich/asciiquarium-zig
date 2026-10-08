class AsciiquariumZig < Formula
  desc "Zig port of Asciiquarium with configurable fish names"
  homepage "https://github.com/dmedovich/asciiquarium-zig"
  url "https://github.com/dmedovich/asciiquarium-zig/releases/download/v0.1.3/asciiquarium-zig-0.1.3-source.tar.gz"
  sha256 "c4a9c92ce015997ee9e5a5f39e2dc59d77a427d21e0b4366117de160099c6a2c"
  license "GPL-2.0-or-later"

  depends_on "zig@0.16" => :build

  def install
    system "zig", "build", *std_zig_args(release_mode: :safe)
    pkgshare.install "fish.conf"
  end

  test do
    assert_equal "asciiquarium-zig #{version}", shell_output("#{bin}/asciiquarium-zig --version").strip
    assert_match "Run asciiquarium-zig in a terminal.", shell_output("#{bin}/asciiquarium-zig 2>&1", 1)
  end
end
