const Serial = @import("serial.zig").Serial;

const PAGE_SIZE = 4096;
const STACK_SIZE = 1024 * 1024 / 8;

var bitmap: [STACK_SIZE]u8 = .{0} ** STACK_SIZE;

const MemError = error{OutOfMemory};

/// Find the next free page
pub fn alloc() MemError!u32 {
    if (false) {
        return error.OutOfMemory;
    }

    for (0.., &bitmap) |i, *entry| {
        if (entry.* != 0xFF) {
            // There is an unset bit in this entry
            const first: u3 = @truncate(@clz(~entry.*));
            entry.* |= @as(u8, 1) << first;
            return (i * 8 + (7 - first)) * PAGE_SIZE;
        }
    }

    return error.OutOfMemory;
}
