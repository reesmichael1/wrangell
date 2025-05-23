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

    if (info.flags & 0x00000040 == 0) {
        @panic("uh-oh");
    }

    // const name: [*:0]u8 = @ptrFromInt(info.boot_loader_name + 0xC0000000);
    // var buf: [100]u8 = undefined;
    // const display = std.fmt.bufPrint(&buf, "{s}", .{name}) catch unreachable;
    // Serial.printf("{d}", .{display.len});

    // _ = name;
    // Serial.printf("name = {*}\n", .{name});

    const entries_base: [*]multiboot.MmapEntry align(1) = @ptrFromInt(info.mmap_addr + 0xC0000000);
    const count = info.mmap_length / @sizeOf(multiboot.MmapEntry);
    const entries: []multiboot.MmapEntry = entries_base[0..count];

    for (entries) |entry| {
        // _ = entry;
        // const l = entry.len;
        // std.debug.assert(l == 0x9fc00);
        // const s = entry.size;
        // const t = entry.type;
        Serial.printf("type = {x}, base_addr = 0x{X}\n", .{ entry.type, entry.addr });
        // Serial.printf("size = {x}\n", .{s});
        // Serial.printf("len = {x}\n", .{0x9fc00});
        // Serial.printf("len = {x}\n", .{l >> 63});
        // Serial.printf("mmap entry of type {x} and size {x} and len {x}\n", .{ t, s, x });
        // Serial.printf("entry {}", .{ entry. } );
    }

    // var map: u32 = info.mmap_addr;

    // while (map < info.mmap_addr + info.mmap_length) {
    //     const entry: *multiboot.MmapEntry align(1) = @ptrFromInt(map + 0xC0000000);
    //     Serial.printf("mmap entry of type 0x{x} and size 0x{x:08}\n", .{ entry.type, entry.size });
    //
    //     // Serial.printf("entry.size = 0x{x:08}\n", .{entry.size });
    //
    //     // map += entry.size + @sizeOf(u32);
    //     // map += entry.size;
    //     map += entry.size + @sizeOf(@TypeOf(entry.size));
    //     Serial.printf("map = 0x{x:08}\n", .{map});
    // }

    // const mmap: [*]multiboot.MmapEntry = @ptrFromInt(info.mmap_addr + 0xC0000000);
    // var i: usize = 0;
    // while (i < info.mmap_length) : (i += @sizeOf(multiboot.MmapEntry)) {
    //     const entry = mmap[i];
    //     Serial.printf("mmap entry of type 0x{x} and size 0x{x:08}\n", .{ entry.type, entry.size });
    // }
}
