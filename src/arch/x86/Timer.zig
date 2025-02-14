const idt = @import("idt.zig");
const arch = @import("arch.zig");
const pic = @import("pic.zig");
const Vga = @import("vga.zig").Vga;
const Serial = @import("serial.zig").Serial;

var ticks: u32 = 0;

const COMMAND_PORT: u16 = 0x43;

fn timerCallback(_: idt.CpuState) void {
    ticks += 1;
}

pub fn init(freq: u32) void {
    Serial.writeln("beginning PIT initialization");
    defer Serial.writeln("finished PIT initialization");

    idt.setIrqCallback(0, timerCallback);

    pic.clearMask(0);

    const divisor: u16 = @truncate(1193182 / freq);
    const low_byte: u8 = @truncate(divisor);
    const high_byte: u8 = @truncate(divisor >> 8);

    arch.outb(COMMAND_PORT, 0x36);
    arch.outb(0x40, low_byte);
    arch.outb(0x40, high_byte);
}
