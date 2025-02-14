const builtin = @import("builtin");

pub const internals = switch (builtin.cpu.arch) {
    .x86 => @import("arch/x86/arch.zig"),
    else => unreachable,
};
