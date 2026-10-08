class AsciiquariumZig < Formula
  desc "Zig port of Asciiquarium with configurable fish names"
  homepage "https://github.com/dmedovich/asciiquarium-zig"
  url "https://github.com/dmedovich/asciiquarium-zig/releases/download/v@VERSION@/asciiquarium-zig-@VERSION@-source.tar.gz"
  sha256 "@SHA256@"
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
