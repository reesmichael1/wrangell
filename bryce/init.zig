const std = @import("std");
const b = @import("blib");
const syscalls = b.syscalls;
const probes = @import("probes.zig");

pub const panic = std.debug.no_panic;

export fn _start() noreturn {
    const msg = "hello from blib!\n";
    b.write(.stdout, msg) catch unreachable;

    _ = syscalls.write(.stderr, 0xC0000000, 24) catch {
        b.write(.stderr, "printing kernel memory was rejected\n") catch unreachable;
    };

    _ = syscalls.write(.stderr, 0xC0008000, 24) catch {
        b.write(.stderr, "printing kernel memory was rejected\n") catch unreachable;
    };

    const res = probes.runAll();
    if (res) {
        syscalls.exit(0);
    } else {
        syscalls.exit(1);
    }
}
