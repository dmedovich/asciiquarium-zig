// SPDX-License-Identifier: GPL-2.0-or-later
// Zig port of Asciiquarium 1.1 by Kirk Baucom. Original ASCII art by Joan Stark and others.
const std = @import("std");
const art = @import("art.zig");
const c = @cImport({
    @cDefine("_DEFAULT_SOURCE", "1");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("unistd.h");
    @cInclude("termios.h");
    @cInclude("sys/ioctl.h");
    @cInclude("time.h");
    @cInclude("locale.h");
});

const MaxWidth = 320;
const MaxHeight = 120;
const MaxFish = 128;
const MaxBubbles = 256;
const MaxWeeds = 64;
const MaxSplats = 24;
const MaxNames = 64;
const NoFish = MaxFish;

const Dimensions = struct { w: i32, h: i32 };
const Cell = struct { ch: u8 = ' ', color: u8 = 34, layer: u8 = 0 };
const Fish = struct {
    x: f32 = 0,
    y: i32 = 9,
    speed: f32 = 0,
    species: usize = 0,
    depth: u8 = 4,
    colors: [7]u8 = [_]u8{36} ** 7,
    name: usize = 0,
    hooked: bool = false,
};
const Bubble = struct { x: i32 = 0, y: i32 = 0, age: u8 = 0, active: bool = false };
const Weed = struct { x: i32 = 0, size: i32 = 3, phase: u8 = 0, expires: u32 = 0 };
const Splat = struct { x: i32 = 0, y: i32 = 0, age: u8 = 0, active: bool = false };
const EventKind = enum(u8) { ship, whale, monster, big_fish, shark, hook, swan, ducks, dolphins };
const Event = struct {
    kind: EventKind = .ship,
    x: f32 = 0,
    y: f32 = 0,
    speed: f32 = 1,
    dir: usize = 0,
    age: u32 = 0,
    hook_up: bool = false,
    caught: usize = NoFish,
};

var screen: [MaxWidth * MaxHeight]Cell = undefined;
var fish: [MaxFish]Fish = undefined;
var bubbles: [MaxBubbles]Bubble = [_]Bubble{.{}} ** MaxBubbles;
var weeds: [MaxWeeds]Weed = [_]Weed{.{}} ** MaxWeeds;
var splats: [MaxSplats]Splat = [_]Splat{.{}} ** MaxSplats;
var names: [MaxNames][96]u8 = [_][96]u8{[_]u8{0} ** 96} ** MaxNames;
var fish_count: usize = 0;
var weed_count: usize = 0;
var name_count: usize = 0;
var width: i32 = 80;
var height: i32 = 24;
var seed: u64 = 1;
var frame: u32 = 0;
var event: Event = .{};

fn random() u32 {
    seed ^= seed << 13;
    seed ^= seed >> 7;
    seed ^= seed << 17;
    return @truncate(seed >> 16);
}
fn rand(n: u32) u32 {
    return if (n == 0) 0 else random() % n;
}
fn positive(n: i32) u32 {
    return @intCast(@max(n, 1));
}
fn irand(n: i32) i32 {
    return @intCast(rand(positive(n)));
}
fn ix(value: f32) i32 {
    return @intFromFloat(value);
}
fn fx(value: i32) f32 {
    return @floatFromInt(value);
}

var config_path: [4096]u8 = [_]u8{0} ** 4096;

fn resolveConfigPath() [*c]const u8 {
    const explicit = c.getenv("ASCIQUARIUM_CONFIG");
    if (explicit != null and explicit[0] != 0) return explicit;

    const xdg = c.getenv("XDG_CONFIG_HOME");
    if (xdg != null and xdg[0] != 0) {
        if (c.snprintf(@ptrCast(&config_path), config_path.len, "%s/asciiquarium/fish.conf", xdg) > 0) {
            const candidate: [*c]const u8 = @ptrCast(&config_path);
            if (c.access(candidate, c.R_OK) == 0) return candidate;
        }
    }

    const home = c.getenv("HOME");
    if (home != null and home[0] != 0) {
        if (c.snprintf(@ptrCast(&config_path), config_path.len, "%s/.config/asciiquarium/fish.conf", home) > 0) {
            const candidate: [*c]const u8 = @ptrCast(&config_path);
            if (c.access(candidate, c.R_OK) == 0) return candidate;
        }
    }

    return "fish.conf";
}

fn loadNames() void {
    const path = resolveConfigPath();
    const file = c.fopen(path, "r");
    if (file == null) return;
    defer _ = c.fclose(file);
    var line: [512]u8 = undefined;
    while (name_count < MaxNames and c.fgets(@ptrCast(&line), @intCast(line.len), file) != null) {
        const length: usize = @intCast(c.strlen(@ptrCast(&line)));
        if (length == line.len - 1 and line[length - 1] != '\n') {
            var extra: c_int = 0;
            while (true) {
                extra = c.fgetc(file);
                if (extra == c.EOF or extra == '\n') break;
            }
            continue;
        }
        var first: usize = 0;
        while (first < length and (line[first] == ' ' or line[first] == '\t')) : (first += 1) {}
        var last = length;
        while (last > first and (line[last - 1] == ' ' or line[last - 1] == '\t' or line[last - 1] == '\r' or line[last - 1] == '\n')) : (last -= 1) {}
        if (first == last or line[first] == '#' or last - first >= names[0].len) continue;
        var valid = true;
        for (line[first..last]) |byte| {
            if (byte < 32 or byte == 127) valid = false;
        }
        if (!valid) continue;
        for (line[first..last], 0..) |byte, i| names[name_count][i] = byte;
        names[name_count][last - first] = 0;
        name_count += 1;
    }
}

fn terminalSize() void {
    var size: c.struct_winsize = undefined;
    if (c.ioctl(1, c.TIOCGWINSZ, &size) == 0 and size.ws_col > 0 and size.ws_row > 0) {
        width = @min(@as(i32, @intCast(size.ws_col)), MaxWidth);
        height = @min(@as(i32, @intCast(size.ws_row)), MaxHeight);
    }
}

fn dimensions(shape: []const u8) Dimensions {
    var w: i32 = 0;
    var column: i32 = 0;
    var h: i32 = 1;
    for (shape) |ch| {
        if (ch == '\n') {
            w = @max(w, column);
            column = 0;
            h += 1;
        } else column += 1;
    }
    return .{ .w = @max(w, column), .h = h };
}

fn rowChar(shape: []const u8, row: i32, column: i32) u8 {
    var y: i32 = 0;
    var x: i32 = 0;
    for (shape) |ch| {
        if (y == row and x == column) return ch;
        if (ch == '\n') {
            y += 1;
            x = 0;
        } else x += 1;
        if (y > row) break;
    }
    return ' ';
}
fn maskColor(mask: u8, fallback: u8, colors: [7]u8) u8 {
    return switch (mask) {
        '1'...'7' => colors[mask - '1'],
        'w' => 37,
        'W' => 97,
        'r' => 31,
        'R' => 91,
        'g' => 32,
        'G' => 92,
        'y' => 33,
        'Y' => 93,
        'b' => 34,
        'B' => 94,
        'm' => 35,
        'M' => 95,
        'c' => 36,
        'C' => 96,
        else => fallback,
    };
}
fn put(x: i32, y: i32, ch: u8, color: u8, layer: u8) void {
    if (x < 0 or y < 0 or x >= width - 1 or y >= height) return;
    const index: usize = @intCast(y * MaxWidth + x);
    if (screen[index].layer <= layer) screen[index] = .{ .ch = ch, .color = color, .layer = layer };
}
fn sprite(x0: i32, y0: i32, shape: []const u8, mask: []const u8, color: u8, layer: u8, colors: [7]u8) void {
    var x: i32 = 0;
    var y: i32 = 0;
    for (shape) |ch| {
        if (ch == '\n') {
            y += 1;
            x = 0;
            continue;
        }
        if (ch != ' ' and ch != '?') {
            const tint = maskColor(rowChar(mask, y, x), color, colors);
            put(x0 + x, y0 + y, ch, tint, layer);
        }
        x += 1;
    }
}
const blank_colors = [_]u8{37} ** 7;
fn simple(x: i32, y: i32, shape: []const u8, color: u8, layer: u8) void {
    sprite(x, y, shape, "", color, layer, blank_colors);
}

fn spawnFish(index: usize, initial: bool) void {
    const species: usize = @intCast(rand(16));
    const size = dimensions(art.fish[species * 2]);
    const dir_right = species % 2 == 0;
    const speed = (@as(f32, @floatFromInt(rand(200))) / 100.0 + 0.25) * (if (dir_right) @as(f32, 1) else @as(f32, -1));
    const available = @max(1, height - size.h - 9);
    var palette: [7]u8 = undefined;
    const choices = [_]u8{ 31, 91, 32, 92, 33, 93, 34, 94, 35, 95, 36, 96 };
    for (&palette) |*color| color.* = choices[rand(@intCast(choices.len))];
    palette[3] = 97;
    fish[index] = .{
        .x = if (dir_right) fx(-size.w) else fx(width - 2),
        .y = 9 + irand(available),
        .speed = speed,
        .species = species,
        .depth = @intCast(3 + rand(18)),
        .colors = palette,
        .name = if (name_count > 0) index % name_count else 0,
    };
    if (initial) fish[index].x = fx(irand(width + size.w) - size.w);
}
fn spawnWeed(index: usize) void {
    weeds[index] = .{ .x = 1 + irand(width - 2), .size = 3 + irand(4), .phase = @intCast(rand(2)), .expires = frame + 4800 + rand(2400) };
}
fn eventShape(kind: EventKind, dir: usize, phase: usize) []const u8 {
    return switch (kind) {
        .ship => art.ship[dir],
        .whale => art.whale[dir],
        .monster => art.monster[dir * 4 + phase % 4],
        .big_fish => art.big_fish[dir],
        .shark => art.shark[dir],
        .hook => art.hook[0],
        .swan => art.swan[dir],
        .ducks => art.ducks[dir * 3 + phase % 3],
        .dolphins => art.dolphins[dir * 2 + phase % 2],
    };
}
fn spawnEvent() void {
    const kind: EventKind = @enumFromInt(@as(u8, @intCast(rand(9))));
    const dir: usize = @intCast(rand(2));
    const shape = eventShape(kind, dir, 0);
    const size = dimensions(shape);
    event = .{ .kind = kind, .dir = dir };
    event.speed = if (dir == 0) 1 else -1;
    event.x = if (dir == 0) fx(-size.w) else fx(width - 2);
    event.y = switch (kind) {
        .ship => -1, // Keep the hull on the waterline at row 5.
        .whale => 1,
        .monster => 2,
        .big_fish => fx(9 + irand(height - 24)),
        .shark => fx(9 + irand(height - 19)),
        .hook => -4,
        .swan => 1,
        .ducks => 5,
        .dolphins => 5,
    };
    if (kind == .shark or kind == .monster) event.speed *= 2;
    if (kind == .big_fish) event.speed *= 3;
    if (kind == .hook) event.x = fx(10 + irand(width - 20));
}
fn resetScene() void {
    fish_count = @intCast(@min(MaxFish, @max(0, @divTrunc((height - 9) * width, 350))));
    weed_count = @intCast(@min(MaxWeeds, @max(0, @divTrunc(width, 15))));
    for (0..fish_count) |i| spawnFish(i, true);
    for (0..weed_count) |i| spawnWeed(i);
    for (&bubbles) |*bubble| bubble.active = false;
    for (&splats) |*splat| splat.active = false;
    spawnEvent();
}

fn addBubble(item: Fish) void {
    for (&bubbles) |*bubble| {
        if (!bubble.active) {
            const size = dimensions(art.fish[item.species * 2]);
            bubble.* = .{ .x = ix(item.x) + (if (item.speed > 0) size.w else 0), .y = item.y + @divTrunc(size.h, 2), .active = true };
            break;
        }
    }
}
fn addSplat(x: i32, y: i32) void {
    for (&splats) |*splat| {
        if (!splat.active) {
            splat.* = .{ .x = x - 4, .y = y - 2, .active = true };
            break;
        }
    }
}
fn collides(item: Fish, px: i32, py: i32) bool {
    const shape = art.fish[item.species * 2];
    const local_x = px - ix(item.x);
    const local_y = py - item.y;
    if (local_x < 0 or local_y < 0) return false;
    const ch = rowChar(shape, local_y, local_x);
    return ch != ' ' and ch != '?' and ch != '\n';
}
fn updateFish() void {
    for (fish[0..fish_count], 0..) |*item, i| {
        if (item.hooked) {
            item.y -= 1;
            if (item.y + dimensions(art.fish[item.species * 2]).h < 0) spawnFish(i, false);
            continue;
        }
        item.x += item.speed;
        const size = dimensions(art.fish[item.species * 2]);
        if (item.x > fx(width) or item.x < fx(-size.w)) {
            spawnFish(i, false);
            continue;
        }
        if (rand(100) > 97) addBubble(item.*);
        if (event.kind == .shark) {
            const tooth_x = ix(event.x) + (if (event.dir == 0) sizeForEvent(.shark, event.dir).w - 9 else 9);
            const tooth_y = ix(event.y) + 7;
            if (collides(item.*, tooth_x, tooth_y)) {
                addSplat(tooth_x, tooth_y);
                spawnFish(i, false);
            }
        } else if (event.kind == .hook and !event.hook_up) {
            const point_x = ix(event.x) + 1;
            const point_y = ix(event.y) + 2;
            if (collides(item.*, point_x, point_y)) {
                item.hooked = true;
                event.hook_up = true;
                event.caught = i;
            }
        }
    }
}
fn sizeForEvent(kind: EventKind, dir: usize) Dimensions {
    return dimensions(eventShape(kind, dir, 0));
}
fn updateEvent() void {
    event.age +%= 1;
    if (event.kind == .hook) {
        if (event.hook_up) {
            event.y -= 1;
            if (event.y < -10) {
                if (event.caught < fish_count) spawnFish(event.caught, false);
                spawnEvent();
            }
        } else if (event.y + 6 < fx(@divTrunc(height * 3, 4))) {
            event.y += 1;
        } else if (event.age > 120) event.hook_up = true;
        return;
    }
    event.x += event.speed;
    const size = sizeForEvent(event.kind, event.dir);
    const tail: i32 = if (event.kind == .dolphins) 30 else 0;
    if (event.x > fx(width + tail) or event.x < fx(-size.w - tail)) spawnEvent();
}
fn update() void {
    frame +%= 1;
    for (weeds[0..weed_count], 0..) |weed, i| {
        if (frame >= weed.expires) spawnWeed(i);
    }
    for (&bubbles) |*bubble| {
        if (!bubble.active) continue;
        bubble.age +%= 1;
        if (bubble.age % 2 == 0) bubble.y -= 1;
        if (bubble.y <= 8) bubble.active = false;
    }
    for (&splats) |*splat| {
        if (!splat.active) continue;
        splat.age +%= 1;
        if (splat.age >= 15) splat.active = false;
    }
    updateEvent();
    updateFish();
}

fn clearScreen() void {
    for (0..@as(usize, @intCast(height))) |row| {
        for (0..@as(usize, @intCast(width))) |column| {
            screen[row * MaxWidth + column] = .{};
        }
    }
}
fn drawBackground() void {
    for (0..4) |row| {
        const y: i32 = @intCast(row + 5);
        var x: i32 = 0;
        const pattern = art.water[row];
        while (x < width - 1) : (x += 1) {
            const ch = pattern[@as(usize, @intCast(x)) % pattern.len];
            if (ch != ' ') put(x, y, ch, 36, 1);
        }
    }
    sprite(width - 32, height - 13, art.castle[0], art.castle[1], 34, 2, blank_colors);
    for (weeds[0..weed_count]) |weed| {
        var n: i32 = 0;
        while (n < weed.size) : (n += 1) {
            const left = @mod(n + @as(i32, weed.phase) + @as(i32, @intCast((frame / 4) % 2)), 2) == 0;
            put(weed.x + (if (left) @as(i32, 0) else 1), height - 1 - n, if (left) '(' else ')', 32, 3);
        }
    }
}
fn drawShip(x: i32, y: i32, dir: usize) void {
    const shape = art.ship[dir];
    const hull_row: i32 = 6;
    const ship_width = dimensions(shape).w;
    var first: i32 = ship_width;
    var last: i32 = -1;
    var column: i32 = 0;
    while (column < ship_width) : (column += 1) {
        const ch = rowChar(shape, hull_row, column);
        if (ch != ' ' and ch != '?') {
            first = @min(first, column);
            last = column;
        }
    }
    // The hull is hollow ASCII art: cover the wave behind its interior.
    if (last >= first) {
        column = first;
        while (column <= last) : (column += 1) put(x + column, y + hull_row, ' ', 34, 31);
    }
    sprite(x, y, shape, art.ship[2 + dir], 97, 32, blank_colors);
}
fn drawEvent() void {
    const x = ix(event.x);
    const y = ix(event.y);
    const phase: usize = @intCast(event.age / 4);
    switch (event.kind) {
        .ship => drawShip(x, y, event.dir),
        .whale => {
            sprite(x, y + 3, art.whale[event.dir], art.whale[2 + event.dir], 94, 32, blank_colors);
            if (event.age % 12 >= 5) simple(x + (if (event.dir == 0) @as(i32, 11) else 1), y, art.whale[4 + @as(usize, @intCast((event.age / 2) % 7))], 96, 33);
        },
        .monster => sprite(x, y, eventShape(.monster, event.dir, phase), art.monster[8 + event.dir], 32, 32, blank_colors),
        .big_fish => {
            var palette = blank_colors;
            palette[0] = 33;
            palette[1] = 93;
            sprite(x, y, art.big_fish[event.dir], art.big_fish[2 + event.dir], 33, 28, palette);
        },
        .shark => sprite(x, y, art.shark[event.dir], art.shark[2 + event.dir], 96, 28, blank_colors),
        .hook => {
            var line_y: i32 = 0;
            while (line_y < y + 2) : (line_y += 1) put(x + 7, line_y, '|', 32, 31);
            sprite(x, y, art.hook[0], "", 32, 31, blank_colors);
            simple(x + 1, y + 2, art.hook[1], 32, 31);
        },
        .swan => sprite(x, y, art.swan[event.dir], art.swan[2 + event.dir], 97, 32, blank_colors),
        .ducks => sprite(x, y, eventShape(.ducks, event.dir, phase), art.ducks[6 + event.dir], 97, 32, blank_colors),
        .dolphins => {
            for (0..3) |i| {
                const offset: i32 = @intCast(i * 15);
                const dx = if (event.dir == 0) -offset else offset;
                const wave = @as(i32, @intCast((event.age + @as(u32, @intCast(i * 12))) % 36));
                const dy = if (wave < 14) -@divTrunc(wave, 2) else if (wave < 16) -7 else if (wave < 30) -7 + @divTrunc(wave - 16, 2) else 0;
                const color: u8 = if (i == 0) 96 else if (i == 1) 94 else 34;
                sprite(x + dx, y + dy, eventShape(.dolphins, event.dir, phase + i), art.dolphins[4 + event.dir], color, 32, blank_colors);
            }
        },
    }
}
fn drawFish() void {
    for (fish[0..fish_count]) |item| {
        const shape = art.fish[item.species * 2];
        const mask = art.fish[item.species * 2 + 1];
        sprite(ix(item.x), item.y, shape, mask, 36, if (item.hooked) 31 else 30 - item.depth, item.colors);
    }
    for (bubbles) |bubble| {
        if (!bubble.active) continue;
        const ch: u8 = if (bubble.age < 2) '.' else if (bubble.age < 5) 'o' else 'O';
        put(bubble.x, bubble.y, ch, 96, 29);
    }
    for (splats) |splat| {
        if (!splat.active) continue;
        const phase: usize = @intCast(@min(3, splat.age / 4));
        simple(splat.x, splat.y, art.splat[phase], 91, 30);
    }
}
fn nameWidth(name: [*:0]const u8) i32 {
    var cells: i32 = 0;
    var i: usize = 0;
    while (name[i] != 0) : (i += 1) {
        if ((name[i] & 0xc0) != 0x80) cells += 1;
    }
    return cells;
}
fn drawNames() void {
    if (name_count == 0) return;
    for (fish[0..fish_count]) |item| {
        const size = dimensions(art.fish[item.species * 2]);
        const name: [*:0]const u8 = @ptrCast(&names[item.name]);
        const label_width = nameWidth(name);
        const x = ix(item.x) + @divTrunc(size.w - label_width, 2);
        const y = item.y - 1;
        if (x < 0 or x + label_width >= width - 1 or y < 9 or y >= height) continue;
        _ = c.printf("\x1b[%d;%dH\x1b[97m%s", y + 1, x + 1, name);
    }
}
fn render() void {
    clearScreen();
    drawBackground();
    drawFish();
    drawEvent();
    _ = c.printf("\x1b[H");
    var last_color: u8 = 0;
    var y: i32 = 0;
    while (y < height) : (y += 1) {
        _ = c.printf("\x1b[%d;1H", y + 1);
        var x: i32 = 0;
        while (x < width - 1) : (x += 1) {
            const cell = screen[@as(usize, @intCast(y * MaxWidth + x))];
            if (cell.color != last_color) {
                _ = c.printf("\x1b[%dm", cell.color);
                last_color = cell.color;
            }
            _ = c.putchar(cell.ch);
        }
    }
    drawNames();
    _ = c.fflush(null);
}

pub fn main() void {
    _ = c.setlocale(c.LC_ALL, "");
    if (c.isatty(0) == 0 or c.isatty(1) == 0) {
        std.debug.print("Run asciiquarium-zig in a terminal.\n", .{});
        return;
    }
    seed = @bitCast(@as(i64, @intCast(c.time(null))));
    loadNames();
    terminalSize();
    if (width < 20 or height < 12) {
        std.debug.print("Terminal must be at least 20x12.\n", .{});
        return;
    }
    var original: c.struct_termios = undefined;
    if (c.tcgetattr(0, &original) != 0) return;
    var raw = original;
    c.cfmakeraw(&raw);
    raw.c_cc[c.VMIN] = 0;
    raw.c_cc[c.VTIME] = 0;
    if (c.tcsetattr(0, c.TCSAFLUSH, &raw) != 0) return;
    defer {
        _ = c.tcsetattr(0, c.TCSAFLUSH, &original);
        _ = c.printf("\x1b[0m\x1b[?25h\x1b[?1049l");
        _ = c.fflush(null);
    }
    _ = c.printf("\x1b[?1049h\x1b[?25l\x1b[2J");
    _ = c.fflush(null);
    resetScene();
    var paused = false;
    while (true) {
        var key: u8 = 0;
        const count = c.read(0, &key, 1);
        if (count == 1) switch (key) {
            'q', 'Q', 3 => break,
            'p', 'P' => paused = !paused,
            'r', 'R' => {
                name_count = 0;
                loadNames();
                resetScene();
                _ = c.printf("\x1b[2J");
            },
            else => {},
        };
        const old_width = width;
        const old_height = height;
        terminalSize();
        if (width != old_width or height != old_height) {
            if (width >= 20 and height >= 12) resetScene();
            _ = c.printf("\x1b[2J");
        }
        if (width >= 20 and height >= 12) {
            if (!paused) update();
            render();
        }
        _ = c.usleep(100000);
    }
}
