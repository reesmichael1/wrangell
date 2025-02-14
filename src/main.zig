const std = @import("std");
const arch = @import("arch.zig").internals;

const MultiBoot = packed struct {
    magic: i32,
    flags: i32,
    checksum: i32,
    padding: i32 = 0,
};

const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const FLAGS = ALIGN | MEMINFO;
const MAGIC = 0x1BADB002;

const STACK_SIZE = 16 * 1024;
export var stack_bytes: [STACK_SIZE]u8 align(16) linksection(".bss") = undefined;

export var multiboot align(4) linksection(".multiboot") = MultiBoot{
    .magic = MAGIC,
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

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

export fn kmain() noreturn {
    arch.init();

    arch.Vga.writeln("wrangell 0.0.1\n\n");

    while (true) {
        arch.halt();
    }
}

export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ mov $stack_bytes, %%esp
        \\ add %[stack_size], %%esp
        \\ call kmain
        :
        : [stack_size] "n" (STACK_SIZE),
    );
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    const writers: [2]*const fn ([]const u8) void = .{ arch.Vga.writeln, arch.Serial.writeln };
    for (writers) |writeln| {
        writeln("!!! KERNEL PANIC !!!");
        writeln(msg);
    }

    arch.spinWait();
}
