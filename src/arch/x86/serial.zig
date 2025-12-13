const arch = @import("arch.zig");
const std = @import("std");

const COM1_PORT: u16 = 0x3f8;

const Writer = @import("writer.zig").Writer;
const SerialError = error{};

pub const Serial = struct {
    const WriterType = Writer(void, SerialError, putln);

    // private instance
    var writer_instance: WriterType = undefined;

    pub fn init() void {
        writer_instance = WriterType.init({});
    }

    pub fn printf(comptime fmt: []const u8, args: anytype) void {
        // No 'self' required on API
        writer_instance.printf(fmt, args);
    }

    pub fn writeln(msg: []const u8) void {
        printf("{s}\n", .{msg});
    }
};

fn putln(_: void, msg: []const u8) SerialError!usize {
    for (msg) |ch| {
        writeByte(ch);
    }

    return msg.len;
}

fn writeByte(char: u8) void {
    while ((arch.inb(COM1_PORT + 5) & 0x20) == 0) {}
    arch.outb(COM1_PORT, char);
}

pub fn init() void {
    arch.outb(COM1_PORT + 1, 0x00); // Disable all interrupts
    arch.outb(COM1_PORT + 3, 0x80); // Enable DLAB (set baud rate divisor)
    arch.outb(COM1_PORT + 0, 0x03); // Set divisor to 3 (lo byte) 38400 baud
    arch.outb(COM1_PORT + 1, 0x00); //                  (hi byte)
    arch.outb(COM1_PORT + 3, 0x03); // 8 bits, no parity, one stop bit
    arch.outb(COM1_PORT + 2, 0xC7); // Enable FIFO, clear them, with 14-byte threshold
    arch.outb(COM1_PORT + 4, 0x0B); // IRQs enabled, RTS/DSR set

    Serial.writeln("initialized serial port");
}
