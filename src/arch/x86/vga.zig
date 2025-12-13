const Serial = @import("serial.zig").Serial;
const Modifier = @import("Keyboard.zig").Modifier;
const arch = @import("arch.zig");

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const VGA_SIZE = VGA_WIDTH * VGA_HEIGHT;

const std = @import("std");
const IOWriter = std.io.Writer;

const Writer = @import("writer.zig").Writer;
const VGAError = error{};

pub const Vga = struct {
    const WriterType = Writer(void, VGAError, putln);

    // private instance
    var writer_instance: WriterType = undefined;

    pub fn init() void {
        writer_instance = WriterType.init({});
    }

    pub fn printf(comptime fmt: []const u8, args: anytype) void {
        writer_instance.printf(fmt, args);
    }

    pub fn write(msg: []const u8) void {
        printf("{s}", .{msg});
    }

    pub fn writeln(msg: []const u8) void {
        printf("{s}\n", .{msg});
    }
};

fn putln(_: void, msg: []const u8) error{}!usize {
    for (msg) |ch| {
        putChar(ch);
    }

    return msg.len;
}

pub const VgaColors = enum(u8) {
    black,
    blue,
    green,
    cyan,
    red,
    magenta,
    brown,
    light_gray,
    dark_gray,
    light_blue,
    light_green,
    light_cyan,
    light_red,
    light_magenta,
    light_brown,
    white,
};

var row: usize = 0;
var column: usize = 0;
var color = vgaEntryColor(VgaColors.white, VgaColors.light_blue);
// TODO: parse initial memory map from GRUB and identity map those
// (which will return this to 0xB8000)
var buffer = @as(*volatile [2000]u16, @ptrFromInt(0xC00B8000));

fn vgaEntryColor(fg: VgaColors, bg: VgaColors) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

fn vgaEntry(uc: u8, new_color: u8) u16 {
    const c: u16 = new_color;

    return uc | (c << 8);
}

pub fn init() void {
    Serial.writeln("beginning VGA initialization");
    defer Serial.writeln("finished VGA initialization");

    clear();
    moveCursor();
}

pub fn setColor(new_color: u8) void {
    color = new_color;
}

pub fn clear() void {
    @memset(buffer, vgaEntry(' ', color));
}

fn putCharAt(c: u8, new_color: u8, x: usize, y: usize) void {
    if (c == '\n') {
        linebreak();
        return;
    }

    const index = y * VGA_WIDTH + x;
    buffer[index] = vgaEntry(c, new_color);
}

fn putChar(c: u8) void {
    putCharAt(c, color, column, row);
    if (c != '\n') {
        column += 1;
        if (column == VGA_WIDTH) {
            column = 0;
            row += 1;
            if (row == VGA_HEIGHT)
                row = 0;
        }
    }

    moveCursor();
}

fn linebreak() void {
    if (row < VGA_HEIGHT - 1) {
        row += 1;
        column = 0;
    } else {
        scroll();
    }
}

fn scroll() void {
    var y: usize = 4;
    while (y < VGA_HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < VGA_WIDTH) : (x += 1) {
            const index = y * VGA_WIDTH + x;
            putCharAt(@truncate(buffer[index]), color, x, y - 1);
        }
    }

    var x: usize = 0;
    while (x < VGA_WIDTH) : (x += 1) {
        putCharAt(' ', color, x, VGA_HEIGHT - 1);
    }

    row = VGA_HEIGHT - 1;
    column = 0;
    moveCursor();
}

fn moveCursor() void {
    const location: u16 = @intCast(row * VGA_WIDTH + column);

    const high_byte: u8 = @truncate(location >> 8);
    const low_byte: u8 = @truncate(location);

    arch.outb(0x3D4, 0xE);
    arch.outb(0x3D5, high_byte);
    arch.outb(0x3D4, 0xF);
    arch.outb(0x3D5, low_byte);
}

pub fn handleModifierKey(key: Modifier) void {
    switch (key) {
        Modifier.enter => putChar('\n'),
        Modifier.backspace => {
            if (column > 0) {
                column -= 1;
            } else if (row > 3) { // For now, we know that the splash screen takes up the first three lines
                row -= 1;
            }

            putCharAt(' ', color, column, row);
            moveCursor();
        },
        else => {},
    }
}
