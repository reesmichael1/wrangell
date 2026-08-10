const std = @import("std");
const syscalls = @import("syscalls.zig");

pub const panic = std.debug.no_panic;

export fn _start() noreturn {
    _ = syscalls.sysWrite(1, 2) catch unreachable;
    syscalls.sysExit(10);
}
