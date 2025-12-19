const std = @import("std");
const Allocator = std.mem.Allocator;
const kmalloc = @import("kmalloc.zig");

const Kvotigi = @This();

pub fn init() Kvotigi {
    return .{};
}

pub fn allocator(self: *Kvotigi) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

pub fn alloc(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
    _ = ctx;
    _ = alignment;
    _ = ra;

    const addr = kmalloc.kmalloc(n) orelse return null;
    const mem: [*]u8 = @ptrFromInt(addr);
    return mem;
}

pub fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_size: usize, return_address: usize) bool {
    _ = ctx;
    _ = buf;
    _ = alignment;
    _ = new_size;
    _ = return_address;
    return false;
}

pub fn remap(
    ctx: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    return_address: usize,
) ?[*]u8 {
    _ = ctx;
    _ = memory;
    _ = alignment;
    _ = new_len;
    _ = return_address;

    return null;
}

pub fn free(
    ctx: *anyopaque,
    buf: []u8,
    alignment: std.mem.Alignment,
    return_address: usize,
) void {
    _ = ctx;
    _ = alignment;
    _ = buf;
    _ = return_address;
}
