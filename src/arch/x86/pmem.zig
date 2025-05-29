const std = @import("std");
const multiboot = @import("../../multiboot.zig");
const Serial = @import("serial.zig").Serial;

const PAGE_SIZE = 4096;
const STACK_SIZE = 1024 * 1024 / 8;

var bitmap: [STACK_SIZE]u8 = .{0} ** STACK_SIZE;

const PmemError = error{OutOfMemory};

/// Find the next free page
pub fn alloc() PmemError!u32 {
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

pub fn init(info: *const multiboot.Info) void {
    Serial.printf("mmap_addr is at 0x{x:08}\n", .{info.mmap_addr});

    if (multiboot.Flags.hasFlag(.name, info.flags)) {
        Serial.printf("boot loader name at 0x{x}\n", .{info.boot_loader_name});

        const name: [*:0]u8 = @ptrFromInt(info.boot_loader_name + 0xC0000000);
        var buf: [100]u8 = undefined;
        const display = std.fmt.bufPrint(&buf, "{s}", .{name}) catch unreachable;

        Serial.printf("boot loader name = {s}\n", .{display});
    }

    if (!multiboot.Flags.hasFlag(.memmap, info.flags)) {
        @panic("no memory map in multiboot header");
    }

    Serial.writeln("reading memory map from multiboot header");
    var offset: usize = 0;
    while (offset < info.mmap_length) {
        const entry: *align(1) multiboot.MmapEntry = @ptrFromInt(info.mmap_addr + offset + 0xC0000000);
        Serial.printf("type = {d}, base_addr = 0x{x}, len = 0x{x}\n", .{ entry.type, entry.addr, entry.len });
        offset += entry.size + 4;
    }
}
