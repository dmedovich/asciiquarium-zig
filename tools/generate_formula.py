"""Generate a tap formula for the exact source archive uploaded to a release."""
import argparse
import hashlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=Path)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
version = (root / 'VERSION').read_text().strip()
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    parser.error('VERSION must contain a numeric semantic version')
if args.archive.name != f'asciiquarium-zig-{version}-source.tar.gz':
    parser.error('source archive filename must match VERSION')
template = (root / 'packaging/homebrew/asciiquarium-zig.rb').read_text()
formula = template.replace('@VERSION@', version).replace(
    '@SHA256@', hashlib.sha256(args.archive.read_bytes()).hexdigest())
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(formula)
print(args.output)
