# Asciiquarium Zig

A Zig port of [Asciiquarium 1.1](https://robobunny.com/projects/asciiquarium/html/) by Kirk Baucom, with configurable fish names. It includes the original 16 fish sprites, water, castle, seaweed, bubbles, shark and hook interactions, ship, whale, sea monster, giant fish, swans, ducks, and dolphins.

## Install

### Homebrew (coming soon)

```sh
brew install dmedovich/tap/asciiquarium-zig
```

Run:

```sh
asciiquarium-zig
```

### Linux and macOS — GitHub Releases

Download the archive for your platform from [GitHub Releases](https://github.com/dmedovich/asciiquarium-zig/releases/latest):

| Platform | Archive suffix |
| --- | --- |
| Linux x86_64 | `linux-x86_64.tar.gz` |
| Linux ARM64 | `linux-aarch64.tar.gz` |
| macOS Intel | `macos-x86_64.tar.gz` |
| macOS Apple Silicon | `macos-aarch64.tar.gz` |

Extract it and run:

```sh
./asciiquarium-zig
```

The release binaries do not require Perl, ncurses, or Zig.

`asciiquarium-zig --help` shows usage; `--version` prints the installed version.

## Controls

- `q` or Ctrl+C — quit
- `p` — pause/resume
- `r` — reload fish names and regenerate the scene

The scene adapts to terminal resizing. Minimum terminal size: 20×12; rendering is capped at 320×120 cells.

## Fish names

The config lookup order is:

1. `ASCIQUARIUM_CONFIG` if set.
2. `$XDG_CONFIG_HOME/asciiquarium/fish.conf`.
3. `~/.config/asciiquarium/fish.conf`.
4. `fish.conf` in the current directory.

A sample `fish.conf` is included with releases. The file contains one UTF-8 name per line. Blank lines and comments beginning with `#` are ignored. Up to 64 names of at most 95 bytes each are loaded. If no config file is found, fish swim without labels.

To use the sample from a downloaded archive:

```sh
mkdir -p ~/.config/asciiquarium
cp fish.conf ~/.config/asciiquarium/fish.conf
```

For a Homebrew installation, copy the sample with:

```sh
mkdir -p ~/.config/asciiquarium
cp "$(brew --prefix asciiquarium-zig)/share/asciiquarium-zig/fish.conf" ~/.config/asciiquarium/fish.conf
```

Edit that file to set your fish names, then press `r` in the aquarium to reload it.

Or use an explicit file:

```sh
ASCIQUARIUM_CONFIG=/path/to/my-fish.conf asciiquarium-zig
```

Cyrillic labels work in a UTF-8 terminal locale. Each Unicode code point is counted as one terminal cell, so wide East Asian characters and combining marks may not align exactly.

## Credits and license

Based on Asciiquarium by Kirk Baucom, with ASCII art by Joan Stark and other contributors.
Licensed under [GPL-2.0-or-later](LICENSE).
