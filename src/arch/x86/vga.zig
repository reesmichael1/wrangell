const fmt = @import("std").fmt;

const Serial = @import("serial.zig").Serial;
const Modifier = @import("Keyboard.zig").Modifier;
const arch = @import("arch.zig");

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const VGA_SIZE = VGA_WIDTH * VGA_HEIGHT;

pub const Vga = @import("writer.zig").Writer(putChar);

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

// extern var KERNEL_STACK_START: []u32;
// extern var KERNEL_STACK_END: []u32;

pub fn init() void {
    Serial.writeln("beginning VGA initialization");
    defer Serial.writeln("finished VGA initialization");

    Serial.printf("row = {*}\n", .{&row});
    Serial.printf("column = {*}\n", .{&column});

    // const kernel_stack_size = @intFromPtr(&KERNEL_STACK_END) - @intFromPtr(&KERNEL_STACK_START);
    // Serial.printf("stack size = 0x{x:08}\n", .{kernel_stack_size});

    // Serial.printf("stack start = 0x{x:08}\n", .{KERNEL_STACK_START});
    // Serial.printf("stack end = 0x{x:08}\n", .{KERNEL_STACK_END});
    // Serial.printf("column is at 0x{x:08}\n", .{@intFromPtr(&column)});

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

    if (y >= VGA_HEIGHT or x >= VGA_WIDTH) {
        Serial.printf("row = {*}, column = {*}\n", .{ &row, &column });
        Serial.printf("x = 0x{x:08}, y = 0x{x:08}\n", .{ x, y });
        clear();
        column = 0;
        row = 0;
        Vga.writeln("tried to write outside of the VGA screen");
        // @panic();
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
