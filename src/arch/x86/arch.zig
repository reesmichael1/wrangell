const multiboot = @import("../../multiboot.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
pub const vmem = @import("vmem.zig");
pub const pmem = @import("pmem.zig");
const pic = @import("pic.zig");
const serial = @import("serial.zig");
const vga = @import("vga.zig");
const Keyboard = @import("Keyboard.zig");
const Timer = @import("Timer.zig");

pub const Vga = vga.Vga;
pub const Serial = serial.Serial;

pub const PrivilegeLevel = enum(u2) {
    ring0 = 0,
    ring1 = 1,
    ring2 = 2,
    ring3 = 3,
};

pub fn disableInterrupts() void {
    asm volatile ("cli");
}

pub fn enableInterrupts() void {
    asm volatile ("sti");
}

pub fn lidt(idtr: *const idt.IdtRegister) void {
    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "r" (@intFromPtr(idtr)),
    );
}

pub fn lgdt(ptr: *const gdt.GdtPtr) void {
    asm volatile ("lgdt (%%eax)"
        :
        : [gdt_ptr] "{eax}" (ptr),
    );

    // Our bootloader (currently GRUB) has already put us into protected mode
    // This is important to remember if we write our own bootloader eventually!

    // Load the kernel data segment into (most of) the segment registers
    asm volatile (
        \\ mov %[ds], %%bx
        \\ mov %%bx, %%ds
        \\ mov %%bx, %%es
        \\ mov %%bx, %%fs
        \\ mov %%bx, %%gs
        \\ mov %%bx, %%ss
        :
        : [ds] "n" (gdt.KERNEL_DATA_SELECTOR),
    );

    // Load the kernel code segment into the CS register via a far jump
    asm volatile (
        \\ljmp %[cs], $1f
        \\1:
        :
        : [cs] "n" (gdt.KERNEL_CODE_SELECTOR),
    );
}

pub fn halt() void {
    asm volatile ("hlt");
}

pub fn haltNoInterrupts() noreturn {
    while (true) {
        disableInterrupts();
        halt();
    }
}

pub fn spinWait() noreturn {
    enableInterrupts();
    while (true) {
        halt();
    }
}

pub fn iret() noreturn {
    asm volatile ("iret");
}

pub fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (val),
          [port] "N{dx}" (port),
    );
}

pub fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

pub fn init(info: *const multiboot.Info) !void {
    serial.init();
    Serial.writeln("beginning x86 hardware initialization");
    defer Serial.writeln("finished x86 hardware initialization");

    vga.init();

    disableInterrupts();
    gdt.init();
    idt.init();
    enableInterrupts();

    vmem.init() catch |err| switch (err) {
        vmem.PageError.OutOfMemory => {
            Serial.writeln("out of memory");
            return err;
        },
        else => return err,
    };
    pmem.init(info);

    Timer.init(50);
    Keyboard.init();

    _ = pmem.alloc() catch unreachable;
    const addr2 = pmem.alloc() catch unreachable;
    Serial.printf("allocated memory at 0x{x}\n", .{addr2});
}
