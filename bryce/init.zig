const syscalls = @import("syscalls.zig");

export fn _start() noreturn {
    syscalls.sysExit(10);
}
