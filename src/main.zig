const std = @import("std");
const arch = @import("arch.zig").internals;
const multiboot = @import("multiboot.zig");
const kmalloc = @import("kmalloc.zig");

comptime {
    const builtin = @import("builtin");
    switch (builtin.cpu.arch) {
        .x86 => _ = @import("arch/x86/boot.zig"),
        else => unreachable,
    }
}

extern var KERNEL_ADDR_OFFSET: u32;
extern var KERNEL_PHYSADDR_START: u32;
extern var KERNEL_PHYSADDR_END: u32;
extern var KERNEL_VADDR_START: u32;
extern var KERNEL_STACK_START: u32;
extern var KERNEL_STACK_END: u32;

// Handy test for the interrupt handler
fn divideByZero() noreturn {
    const a = 10;
    const b = 0;
    const answer: u8 = asm volatile (
        \\ xor %%dx, %%dx
        \\ div %[b]
        : [_] "={ax}" (-> u8),
        : [a] "{ax}" (a),
          [b] "{cx}" (b),
        : "ax", "cx", "dx"
    );
    arch.Vga.printf("answer = {}\n", .{answer});

    unreachable;
}

fn pageFault() noreturn {
    const addr: *u8 = @ptrFromInt(0xDEADC0DE);
    addr.* = 42;

    arch.Vga.printf("got past the memory write\n", .{});
    unreachable;
}

export fn kmain(magic: u32, info: *const multiboot.Info) noreturn {
    std.debug.assert(magic == multiboot.BOOTLOADER_MAGIC);

    const kernel_bytes = @intFromPtr(&KERNEL_PHYSADDR_END) - @intFromPtr(&KERNEL_PHYSADDR_START);
    arch.Serial.printf("kernel stack = {*} to {*}\n", .{ &KERNEL_STACK_START, &KERNEL_STACK_END });
    arch.Serial.printf("kernel = {*} to {*} [{} KiB]\n", .{ &KERNEL_PHYSADDR_START, &KERNEL_PHYSADDR_END, kernel_bytes / 1024 });

    arch.Serial.printf("mem_lower = 0x{x:08}\n", .{info.mem_lower});
    arch.Serial.printf("mem_upper = 0x{x:08}\n", .{info.mem_upper});

    arch.init(info) catch @panic("error during architecture initialization");

    arch.Vga.writeln("wrangell 0.0.1\n\n");

    const addr2 = kmalloc.kmalloc(32) orelse @panic("allocation failed");
    // const addr2 = 0xC0400000;
    const vmem: *u32 = @ptrFromInt(addr2);
    arch.Serial.printf("writing to 0x{x}\n", .{addr2});
    vmem.* = 100;

    while (true) {
        arch.halt();
    }
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    const writers: [2]*const fn ([]const u8) void = .{ arch.Vga.writeln, arch.Serial.writeln };
    for (writers) |writeln| {
        writeln("!!! KERNEL PANIC !!!");
        writeln(msg);
    }

    // arch.haltNoInterrupts();
    arch.spinWait();
}
