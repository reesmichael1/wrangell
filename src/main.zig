const std = @import("std");
const arch = @import("arch.zig").internals;

comptime {
    const builtin = @import("builtin");
    switch (builtin.cpu.arch) {
        .x86 => _ = @import("arch/x86/boot.zig"),
        else => unreachable,
    }
}

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

export fn kmain() noreturn {
    arch.init();

    arch.Vga.writeln("wrangell 0.0.1\n\n");

    pageFault();

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

    arch.spinWait();
}
