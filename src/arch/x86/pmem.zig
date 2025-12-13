const std = @import("std");
const multiboot = @import("../../multiboot.zig");
const Serial = @import("serial.zig").Serial;

const ONE_MB = 1024 * 1024;
const MAX_PHYS_ADDR = 0xFFFFFFFF; // 4 GB of RAM
const PAGE_TABLE_START = 0xFFC00000;
const PAGE_TABLE_END = MAX_PHYS_ADDR;

const PAGE_SIZE = 4096;
const PAGE_COUNT = (MAX_PHYS_ADDR + 1) / PAGE_SIZE;
const BITMAP_SIZE = PAGE_COUNT / 8; // 8 pages in one byte

var bitmap: [BITMAP_SIZE]u8 = [_]u8{0xFF} ** BITMAP_SIZE;

extern var KERNEL_PHYSADDR_START: u32;
extern var KERNEL_PHYSADDR_END: u32;
extern var KERNEL_ADDR_OFFSET: *const u32;
extern var KERNEL_STACK_START: u32;
extern var KERNEL_STACK_END: u32;

pub const PmemError = error{OutOfMemory};

fn getByteAndBit(addr: usize) struct { usize, u3 } {
    return .{ addr / 8, @intCast(addr % 8) };
}

fn markPageUsed(addr: usize) void {
    std.debug.assert(std.mem.isAligned(addr, PAGE_SIZE));
    const byte, const bit = getByteAndBit(addr / PAGE_SIZE);
    bitmap[byte] |= @as(u8, 1) << bit;
}

fn freePage(addr: usize) void {
    std.debug.assert(std.mem.isAligned(addr, PAGE_SIZE));
    const byte, const bit = getByteAndBit(addr / PAGE_SIZE);
    bitmap[byte] &= ~(@as(u8, 1) << bit);
}

fn isPageFree(addr: usize) bool {
    std.debug.assert(std.mem.isAligned(addr, PAGE_SIZE));
    const byte, const bit = getByteAndBit(addr / PAGE_SIZE);
    return (bitmap[byte] & (@as(u8, 1) << bit)) == 0;
}

fn manipulateRegion(start: usize, end: usize, manipulator: fn (usize) void) void {
    // Use u64 instead of usize/u32 because we need to handle MAX_PHYS_ADDR,
    // which is also the max u32 value. If we use u32, then in the loop iteration
    // where current = end, we trigger an overflow.
    // We should never exceed u32 inside of the loop body, so the cast below is safe.
    var current: u64 = start;
    while (current < std.mem.alignBackward(usize, end, PAGE_SIZE)) : (current += PAGE_SIZE) {
        manipulator(@intCast(current));
    }
}

fn freeRegion(start: usize, end: usize) void {
    manipulateRegion(start, end, freePage);
}

fn reserveRegion(start: usize, end: usize) void {
    manipulateRegion(start, end, markPageUsed);
}

/// Find the next free page
/// Returns a *physical* address.
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
    Serial.writeln("begining pmem initialization");
    defer Serial.writeln("done with pmem initialization");

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

    var offset: usize = 0;
    Serial.writeln("parsing memmap from multiboot info");

    while (offset < info.mmap_length) {
        const entry: *align(4) multiboot.MmapEntry = @ptrFromInt(info.mmap_addr + offset + 0xC0000000);
        Serial.printf("type = {}, base_addr = 0x{x}, len = 0x{x}\n", .{ entry.type, entry.addr, entry.len });
        if (entry.type == .available) {
            if (entry.addr + entry.len < 0x100000000) {
                freeRegion(@intCast(entry.addr), @intCast(entry.addr + entry.len));
            } else if (entry.addr < 0x10000000) {
                freeRegion(@intCast(entry.addr), 0xFFFFFFFF);
            }
        }
        offset += entry.size + 4;
    }

    // Reserve lowest megabyte
    Serial.writeln("reserving lowest megabyte of kernel");
    reserveRegion(0, ONE_MB);
    Serial.printf("reserving kernel: 0x{x:08} to 0x{x:08}\n", .{ @intFromPtr(&KERNEL_PHYSADDR_START), @intFromPtr(&KERNEL_PHYSADDR_END) });
    reserveRegion(@intFromPtr(&KERNEL_PHYSADDR_START), @intFromPtr(&KERNEL_PHYSADDR_END));
    Serial.printf("reserving stack: 0x{x:08} to 0x{x:08}\n", .{ @intFromPtr(&KERNEL_STACK_START), @intFromPtr(&KERNEL_STACK_END) });
    reserveRegion(@intFromPtr(&KERNEL_STACK_START) - 0xC0000000, @intFromPtr(&KERNEL_STACK_END) - 0xC0000000);

    var total_free_pages: usize = 0;
    for (bitmap) |entry| {
        total_free_pages += 8 - @popCount(entry);
    }

    Serial.printf("total free pages: {}\n", .{total_free_pages});
}
