const std = @import("std");
const arch = @import("arch.zig").internals;
const multiboot = @import("multiboot.zig");

// pub const std_options: std.Options = .{
//     .page_size_min = 4 * 1024,
//     .page_size_max = 4 * 1024 * 1024,
// };

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

    arch.init(info) catch @panic("error during architecture initialization");

    arch.Serial.printf("kernel stack = {*} to {*}\n", .{ &KERNEL_STACK_START, &KERNEL_STACK_END });
    arch.Serial.printf("kernel = {*} to {*}\n", .{ &KERNEL_PHYSADDR_START, &KERNEL_PHYSADDR_END });
    arch.Serial.printf("mem_lower = 0x{x:08}\n", .{info.mem_lower});
    arch.Serial.printf("mem_upper = 0x{x:08}\n", .{info.mem_upper});

    arch.Vga.writeln("wrangell 0.0.1\n\n");

    // pageFault();
    // Demonstrate that paging is working (we mapped 0xA0000000 + 0x1000 in paging.zig)
    const addr: *u8 = @ptrFromInt(0xA0000100);
    addr.* = 100;

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
