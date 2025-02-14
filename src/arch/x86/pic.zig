const arch = @import("arch.zig");
const Serial = @import("serial.zig").Serial;

const ACKNOWLEDGE = 0x20;

const PIC1 = 0x20;
const PIC2 = 0xA0;
const PIC1_COMMAND = PIC1;
const PIC1_DATA = PIC1 + 1;
const PIC2_COMMAND = PIC2;
const PIC2_DATA = PIC2 + 1;

const ICW1_ICW4 = 0x01;
const ICW1_SINGLE = 0x02;
const ICW1_INTERVAL4 = 0x04;
const ICW1_LEVEL = 0x08;
const ICW1_INIT = 0x10;
const ICW4_8086 = 0x01;
const ICW4_AUTO = 0x02;
const ICW4_BUF_SLAVE = 0x08;
const ICW4_BUF_MASTER = 0x0C;
const ICW4_SFNM = 0x10;

pub const IRQ_OFFSET = 0x20;

pub fn mappedPort(port: u8) u8 {
    return port + IRQ_OFFSET;
}

pub fn acknowledge(line: u8) void {
    if (line >= 8) {
        arch.outb(PIC2_COMMAND, ACKNOWLEDGE);
    }

    arch.outb(PIC1_COMMAND, ACKNOWLEDGE);
}

pub fn clearMask(lineIn: u4) void {
    const port: u16 = if (lineIn < 8) PIC1_DATA else PIC2_DATA;
    const shift: u3 = @intCast(lineIn % 8);
    const value: u8 = arch.inb(port) & ~(@as(u8, 1) << shift);
    arch.outb(port, value);

    Serial.printf("cleared PIC mask 0x{x}\n", .{lineIn});

    arch.outb(port, value);
}

pub fn init() void {
    Serial.writeln("beginning PIC initialization");
    defer Serial.writeln("finished PIC initialization");

    // Start the initialization sequence in cascade mode
    arch.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    arch.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    // Remap the ports to start at 0x20 and 0x28
    arch.outb(PIC1_DATA, IRQ_OFFSET);
    arch.outb(PIC2_DATA, IRQ_OFFSET + 8);

    // Notify PIC1 of PIC2 at the 3rd pin
    arch.outb(PIC1_DATA, 0b00000100);
    // Tell PIC2 its cascade identity
    arch.outb(PIC2_DATA, 0b00000010);

    // Put the PICs into 8086 mode
    arch.outb(PIC1_DATA, ICW4_8086);
    arch.outb(PIC2_DATA, ICW4_8086);

    // Fully mask both PICs
    arch.outb(PIC1_DATA, 0xFF);
    arch.outb(PIC2_DATA, 0xFF);
}
