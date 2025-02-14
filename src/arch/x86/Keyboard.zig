const arch = @import("arch.zig");
const idt = @import("idt.zig");
const pic = @import("pic.zig");
const Serial = @import("serial.zig").Serial;
const vga = @import("vga.zig");
const Vga = vga.Vga;

const PS2_DATA = 0x60;

const Keyboard = @This();

const KeyType = enum {
    modifier,
    char,
    unknown,
};

pub const Modifier = enum {
    backspace,
    enter,
    left_ctrl,
    right_ctrl,
    left_shift,
    right_shift,
    esc,
};

var modifier: ?Modifier = null;

const Key = union(KeyType) {
    modifier: Modifier,
    char: []const u8,
    unknown: []const u8,
};

const Action = enum {
    press,
    release,
};

const KeyPress = union(Action) {
    press: Key,
    release: Key,
};

fn createKey(code: u8) Key {
    if (Keyboard.modifier) |mod| {
        switch (mod) {
            Modifier.left_shift, Modifier.right_shift => return shiftKey(code),
            else => return normalKey(code),
        }
    }

    return normalKey(code);
}

fn createReleaseKey(code: u8) Key {
    return switch (code) {
        0x81 => Key{ .modifier = Modifier.esc },
        0x82 => Key{ .char = "1" },
        0x83 => Key{ .char = "2" },
        0x84 => Key{ .char = "3" },
        0x85 => Key{ .char = "4" },
        0x86 => Key{ .char = "5" },
        0x87 => Key{ .char = "6" },
        0x88 => Key{ .char = "7" },
        0x89 => Key{ .char = "8" },
        0x8A => Key{ .char = "9" },
        0x8B => Key{ .char = "0" },
        0x8C => Key{ .char = "-" },
        0x8D => Key{ .char = "=" },
        0x8E => Key{ .modifier = Modifier.backspace },
        0x8F => Key{ .char = "\t" },
        0x90 => Key{ .char = "q" },
        0x91 => Key{ .char = "w" },
        0x92 => Key{ .char = "e" },
        0x93 => Key{ .char = "r" },
        0x94 => Key{ .char = "t" },
        0x95 => Key{ .char = "y" },
        0x96 => Key{ .char = "u" },
        0x97 => Key{ .char = "i" },
        0x98 => Key{ .char = "o" },
        0x99 => Key{ .char = "p" },
        0x9A => Key{ .char = "[" },
        0x9B => Key{ .char = "]" },
        0x9C => Key{ .modifier = Modifier.enter },
        0x9D => Key{ .modifier = Modifier.left_ctrl },
        0x9E => Key{ .char = "a" },
        0x9F => Key{ .char = "s" },
        0xA0 => Key{ .char = "d" },
        0xA1 => Key{ .char = "f" },
        0xA2 => Key{ .char = "g" },
        0xA3 => Key{ .char = "h" },
        0xA4 => Key{ .char = "j" },
        0xA5 => Key{ .char = "k" },
        0xA6 => Key{ .char = "l" },
        0xA7 => Key{ .char = ";" },
        0xA8 => Key{ .char = "'" },
        0xA9 => Key{ .char = "`" },
        0xAA => Key{ .modifier = Modifier.left_shift },
        0xAB => Key{ .char = "\\" },
        0xAC => Key{ .char = "z" },
        0xAD => Key{ .char = "x" },
        0xAE => Key{ .char = "c" },
        0xAF => Key{ .char = "v" },
        0xB0 => Key{ .char = "b" },
        0xB1 => Key{ .char = "n" },
        0xB2 => Key{ .char = "m" },
        0xB3 => Key{ .char = "," },
        0xB4 => Key{ .char = "." },
        0xB5 => Key{ .char = "/" },
        0xB6 => Key{ .modifier = Modifier.right_shift },
        0xB9 => Key{ .char = " " },
        else => Key{ .unknown = "\x00\x00" },
    };
}

fn shiftKey(code: u8) Key {
    return switch (code) {
        0x2 => Key{ .char = "!" },
        0x3 => Key{ .char = "@" },
        0x4 => Key{ .char = "#" },
        0x5 => Key{ .char = "$" },
        0x6 => Key{ .char = "%" },
        0x7 => Key{ .char = "^" },
        0x8 => Key{ .char = "&" },
        0x9 => Key{ .char = "*" },
        0xA => Key{ .char = "(" },
        0xB => Key{ .char = ")" },
        0xC => Key{ .char = "-" },
        0xD => Key{ .char = "+" },
        0xE => Key{ .modifier = Modifier.backspace },
        0xF => Key{ .char = "\t" },
        0x10 => Key{ .char = "Q" },
        0x11 => Key{ .char = "W" },
        0x12 => Key{ .char = "E" },
        0x13 => Key{ .char = "R" },
        0x14 => Key{ .char = "T" },
        0x15 => Key{ .char = "Y" },
        0x16 => Key{ .char = "U" },
        0x17 => Key{ .char = "I" },
        0x18 => Key{ .char = "O" },
        0x19 => Key{ .char = "P" },
        0x1A => Key{ .char = "{" },
        0x1B => Key{ .char = "}" },
        0x1C => Key{ .modifier = Modifier.enter },
        0x1D => Key{ .modifier = Modifier.left_ctrl },
        0x1E => Key{ .char = "A" },
        0x1F => Key{ .char = "S" },
        0x20 => Key{ .char = "D" },
        0x21 => Key{ .char = "F" },
        0x22 => Key{ .char = "G" },
        0x23 => Key{ .char = "H" },
        0x24 => Key{ .char = "J" },
        0x25 => Key{ .char = "K" },
        0x26 => Key{ .char = "L" },
        0x27 => Key{ .char = ":" },
        0x28 => Key{ .char = "\"" },
        0x29 => Key{ .char = "~" },
        0x2A => Key{ .modifier = Modifier.left_shift },
        0x2B => Key{ .char = "|" },
        0x2C => Key{ .char = "Z" },
        0x2D => Key{ .char = "X" },
        0x2E => Key{ .char = "C" },
        0x2F => Key{ .char = "V" },
        0x30 => Key{ .char = "B" },
        0x31 => Key{ .char = "N" },
        0x32 => Key{ .char = "M" },
        0x33 => Key{ .char = "<" },
        0x34 => Key{ .char = ">" },
        0x35 => Key{ .char = "?" },
        0x36 => Key{ .modifier = Modifier.right_shift },
        0x39 => Key{ .char = " " },
        else => Key{ .unknown = "\x00\x00" },
    };
}

fn normalKey(code: u8) Key {
    return switch (code) {
        0x2 => Key{ .char = "1" },
        0x3 => Key{ .char = "2" },
        0x4 => Key{ .char = "3" },
        0x5 => Key{ .char = "4" },
        0x6 => Key{ .char = "5" },
        0x7 => Key{ .char = "6" },
        0x8 => Key{ .char = "7" },
        0x9 => Key{ .char = "8" },
        0xA => Key{ .char = "9" },
        0xB => Key{ .char = "0" },
        0xC => Key{ .char = "-" },
        0xD => Key{ .char = "=" },
        0xE => Key{ .modifier = Modifier.backspace },
        0xF => Key{ .char = "\t" },
        0x10 => Key{ .char = "q" },
        0x11 => Key{ .char = "w" },
        0x12 => Key{ .char = "e" },
        0x13 => Key{ .char = "r" },
        0x14 => Key{ .char = "t" },
        0x15 => Key{ .char = "y" },
        0x16 => Key{ .char = "u" },
        0x17 => Key{ .char = "i" },
        0x18 => Key{ .char = "o" },
        0x19 => Key{ .char = "p" },
        0x1A => Key{ .char = "[" },
        0x1B => Key{ .char = "]" },
        0x1C => Key{ .modifier = Modifier.enter },
        0x1D => Key{ .modifier = Modifier.left_ctrl },
        0x1E => Key{ .char = "a" },
        0x1F => Key{ .char = "s" },
        0x20 => Key{ .char = "d" },
        0x21 => Key{ .char = "f" },
        0x22 => Key{ .char = "g" },
        0x23 => Key{ .char = "h" },
        0x24 => Key{ .char = "j" },
        0x25 => Key{ .char = "k" },
        0x26 => Key{ .char = "l" },
        0x27 => Key{ .char = ";" },
        0x28 => Key{ .char = "'" },
        0x29 => Key{ .char = "`" },
        0x2A => Key{ .modifier = Modifier.left_shift },
        0x2B => Key{ .char = "\\" },
        0x2C => Key{ .char = "z" },
        0x2D => Key{ .char = "x" },
        0x2E => Key{ .char = "c" },
        0x2F => Key{ .char = "v" },
        0x30 => Key{ .char = "b" },
        0x31 => Key{ .char = "n" },
        0x32 => Key{ .char = "m" },
        0x33 => Key{ .char = "," },
        0x34 => Key{ .char = "." },
        0x35 => Key{ .char = "/" },
        0x36 => Key{ .modifier = Modifier.right_shift },
        0x39 => Key{ .char = " " },
        // My keyboard doesn't have a keypad, so I won't bother with more yet
        else => Key{ .unknown = "\x00\x00" },
    };
}

fn keyAction() KeyPress {
    const scancode = arch.inb(PS2_DATA);

    if (scancode == 0xe0) {
        // TODO: handle anything with more than one byte
        const discard = arch.inb(PS2_DATA);
        return KeyPress{ .press = Key{ .unknown = &[2]u8{ scancode, discard } } };
    }

    if (scancode <= 0x39 + 0x80 and scancode > 0x7f) {
        return KeyPress{ .release = createReleaseKey(scancode) };
    } else {
        return KeyPress{ .press = createKey(scancode) };
    }
}

fn handleKeyPress(key: Key) void {
    switch (key) {
        KeyType.modifier => |mod| {
            switch (mod) {
                Modifier.left_shift, Modifier.right_shift, Modifier.left_ctrl, Modifier.right_ctrl => modifier = mod,
                else => {
                    vga.handleModifierKey(mod);
                },
            }
        },
        KeyType.char => |ch| {
            Vga.write(ch);
        },
        KeyType.unknown => {},
    }
}

fn handleKeyRelease(key: Key) void {
    switch (key) {
        KeyType.modifier => |mod| {
            if (modifier) |current_mod| {
                if (current_mod == mod) {
                    Keyboard.modifier = null;
                }
            }
        },
        KeyType.char, KeyType.unknown => {},
    }
}

fn keypressCallback(_: idt.CpuState) void {
    const action = keyAction();

    switch (action) {
        .press => |key| {
            handleKeyPress(key);
        },
        .release => |key| {
            handleKeyRelease(key);
        },
    }
}

pub fn init() void {
    Serial.writeln("beginning keyboard initialization");
    defer Serial.writeln("finished with keyboard initialization");

    pic.clearMask(1);
    idt.setIrqCallback(1, keypressCallback);
}
