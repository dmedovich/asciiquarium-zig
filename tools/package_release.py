"""Build deterministic source and local-platform release archives from reviewed files."""
from pathlib import Path
import gzip
import hashlib
import io
import platform
import shutil
import subprocess
import tarfile

root = Path(__file__).resolve().parents[1]
version = (root / "VERSION").read_text().strip()
dist = root / "dist"
dist.mkdir(exist_ok=True)

source_files = [
    "VERSION", "README.md", "LICENSE", "fish.conf", "main.zig", "art.zig",
    "build.zig", "build.zig.zon", ".gitignore",
    "upstream/README", "upstream/asciiquarium.pl",
    "tools/generate_art.py", "tools/package_release.py",
    ".github/workflows/ci.yml", ".github/workflows/release.yml",
    "packaging/homebrew/asciiquarium-zig.rb",
]


def archive(name: str, files: list[str]) -> Path:
    path = dist / name
    with path.open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as tar:
            for relative in files:
                source = root / relative
                if not source.is_file():
                    raise FileNotFoundError(source)
                payload = source.read_bytes()
                info = tarfile.TarInfo(f"asciiquarium-zig-{version}/{relative}")
                info.size = len(payload)
                info.mode = 0o755 if relative == "asciiquarium-zig" else 0o644
                info.mtime = 0
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                tar.addfile(info, io.BytesIO(payload))
    return path


subprocess.run(["zig", "build", "-Doptimize=ReleaseSafe"], cwd=root, check=True)
binary = root / "zig-out" / "bin" / "asciiquarium-zig"
shutil.copy2(binary, root / "asciiquarium-zig")

system = {"Linux": "linux", "Darwin": "macos"}.get(platform.system(), platform.system().lower())
machine = {"x86_64": "x86_64", "AMD64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}.get(platform.machine(), platform.machine())

source = archive(f"asciiquarium-zig-{version}-source.tar.gz", source_files)
release = archive(f"asciiquarium-zig-{version}-{system}-{machine}.tar.gz", ["asciiquarium-zig", "README.md", "LICENSE", "fish.conf"])
(root / "asciiquarium-zig").unlink(missing_ok=True)

paths = (source, release)
(dist / "SHA256SUMS").write_text("".join(
    f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in paths
))
for path in paths:
    print(path)
