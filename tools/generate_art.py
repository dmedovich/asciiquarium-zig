"""Regenerate art.zig from the GPLv2+ upstream Perl source."""
from pathlib import Path
import json

source = Path(__file__).resolve().parents[1] / 'upstream/asciiquarium.pl'
text = source.read_text()


def literals(function):
    body = text.split(f'\nsub {function} {{', 1)[1].split('\nsub ', 1)[0]
    result = []
    i = 0
    while i < len(body) - 2:
        if body[i] != 'q' or body[i + 1] not in '{#' or (i and body[i - 1].isalnum()):
            i += 1
            continue
        opening = body[i + 1]
        closing = '}' if opening == '{' else '#'
        depth = 1
        i += 2
        chars = []
        while i < len(body):
            ch = body[i]
            if ch == '\\' and i + 1 < len(body):
                next_ch = body[i + 1]
                if next_ch in ('\\', opening, closing):
                    chars.append(next_ch)
                else:
                    chars.extend((ch, next_ch))
                i += 2
                continue
            if ch == opening and opening == '{':
                depth += 1
            elif ch == closing:
                depth -= 1
                if depth == 0:
                    i += 1
                    break
            chars.append(ch)
            i += 1
        result.append(''.join(chars))
    return result


names = {
    'water': ('add_environment', slice(0, 4)),
    'castle': ('add_castle', slice(0, 2)),
    'fish': ('add_fish', slice(0, 32)),
    'splat': ('add_splat', slice(0, 4)),
    'shark': ('add_shark', slice(0, 4)),
    'hook': ('add_fishhook', slice(0, 2)),
    'ship': ('add_ship', slice(0, 4)),
    'whale': ('add_whale', slice(0, 11)),
    'monster': ('add_monster', slice(0, 10)),
    'big_fish': ('add_big_fish', slice(0, 4)),
    'ducks': ('add_ducks', slice(0, 8)),
    'dolphins': ('add_dolphins', slice(0, 6)),
    'swan': ('add_swan', slice(0, 4)),
}

lines = [
    '// Generated from upstream/asciiquarium.pl (GPL-2.0-or-later).',
    '// Run python3 tools/generate_art.py to regenerate.',
]
for name, (function, selection) in names.items():
    values = literals(function)[selection]
    lines.append(f'pub const {name} = [_][]const u8{{')
    for value in values:
        # Zig and JSON share these escapes for ASCII string literals.
        lines.append('    ' + json.dumps(value, ensure_ascii=True) + ',')
    lines.append('};')
Path(__file__).resolve().parents[1].joinpath('art.zig').write_text('\n'.join(lines) + '\n')
