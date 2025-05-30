const std = @import("std");

const boot = @import("boot.zig");
const Serial = @import("serial.zig").Serial;

const PD: *[1024]DirectoryEntry = @ptrFromInt(0xFFFFF000);
const PT: *[1024]DirectoryEntry = @ptrFromInt(0xFFC00000);

// Page Directory Table = list of 1024 PDEs
// Each page directory entry is a list of 1024 page tables
// Each page table points to 4kb of memory

const DirectoryEntry = u32;

const FOUR_KB_SIZE = 4 * 1024;
const FOUR_MB_SIZE = 4 * 1024 * 1024;

const Entry = union(enum) {
    directory: DirectoryEntry,
    table: DirectoryEntry,

    fn value(self: Entry) DirectoryEntry {
        switch (self) {
            .directory, .table => |n| return n,
        }
    }
};

const Table = struct {
    entries: [1024]DirectoryEntry,
};

const Size = enum {
    four_kb,
    four_mb,

    fn isAligned(self: Size, addr: u32) bool {
        return switch (self) {
            .four_kb => std.mem.isAligned(addr, FOUR_KB_SIZE),
            .four_mb => std.mem.isAligned(addr, FOUR_MB_SIZE),
        };
    }
};

const masks = struct {
    const address: u32 = 0xFFFFF000;
    const avl: u32 = 0xF00;
    const page_size: u32 = 0x80;
    const accessed: u32 = 0x20;
    const cache_disabled: u32 = 0x10;
    const write_through: u32 = 0x08;
    const user_supervisor: u32 = 0x04;
    const read_write: u32 = 0x02;
    const dirty: u32 = 0x40;
    const present: u32 = 0x01;
    const pat: u32 = 0x80;
    const global: u32 = 0x100;

    fn is_set(entry: Entry, mask: u32) bool {
        return entry.value() & mask != 0;
    }

    fn set(entry: Entry, mask: u32) Entry {
        // TODO: successfully make this a compile error
        switch (entry) {
            .directory => |_| {
                if (mask == global or mask == dirty) {
                    @panic("invalid mask used for page directory entry");
                }
            },
            .table => |_| {},
        }

        return switch (entry) {
            .directory => |n| Entry{ .directory = n | mask },
            .table => |n| Entry{ .table = n | mask },
        };
    }
};

const empty_table = Table{
    .entries = .{0} ** 1024,
};

var directory: [1024]DirectoryEntry align(FOUR_KB_SIZE) = .{0} ** 1024;
var tables: [1024]?*Table align(FOUR_KB_SIZE) = .{null} ** 1024;
var new_table: [1024]DirectoryEntry align(FOUR_KB_SIZE) = .{2} ** 1024;

pub const PageError = error{
    AlreadyMapped,
    AddrNotAligned,
    NotMapped,
};

pub fn virtToPhys(virt: u32) PageError!u32 {
    const pd_index = virt >> 22;
    const pt_index = (virt >> 12) & 0x03ff;

    const pd: *[1024]DirectoryEntry = @ptrFromInt(0xFFFFF000);
    if (pd[pd_index] & masks.present == 0) {
        return PageError.NotMapped;
    }

    const pt: *[1024]DirectoryEntry = @ptrFromInt(0xFFC00000 + 0x1000 * pd_index);
    if (pt[pt_index] & masks.present == 0) {
        return PageError.NotMapped;
    }

    return (pt[pt_index] & 0xFFFFF000) + (virt & 0xFFF);
}

pub fn mapSinglePage(phys: u32, virt: u32, flags: u32, size: Size) PageError!void {
    if (!size.isAligned(phys) or !size.isAligned(virt)) return PageError.AddrNotAligned;

    if (size == .four_mb) {
        // 4 MB pages are just a pointer to a page (so we don't need a page table)
        const pd_index = virt >> 22;
        // If we're here, then phys is already 4 MB aligned, so...
        directory[pd_index] = phys | masks.page_size | flags;
        return;
    }

    const pd_index = virt >> 22;
    const pt_index = virt >> 12 & 0x03ff;

    var pd: *[1024]DirectoryEntry align(FOUR_KB_SIZE) = @ptrFromInt(0xFFFFF000);

    Serial.printf("old directory addr = 0x{x:08}\n", .{@intFromPtr(&directory)});
    Serial.printf("new directory addr = 0x{x:08}\n", .{@intFromPtr(pd)});

    var pt: *[1024]DirectoryEntry align(FOUR_KB_SIZE) = blk: {
        if (pd[pd_index] & masks.present != 0) {
            const pt: *[1024]DirectoryEntry align(FOUR_KB_SIZE) = @ptrFromInt(0xFFC00000 + 0x400 * pd_index);
            break :blk pt;
        } else {
            // This is it! When we initialize, we need to specify the address
            pd[pd_index] |= ((@intFromPtr(&new_table) - 0xC0000000) | flags | masks.present);
            break :blk &new_table;
        }
    };

    if (pt[pt_index] & masks.present != 0) {
        return PageError.AlreadyMapped;
    }

    pt[pt_index] = phys | flags | masks.present;
}

pub fn init() !void {
    Serial.writeln("initializing page directory");
    defer Serial.printf("initialized paging with page directory: {*}\n", .{&directory});

    for (&directory) |*num| {
        const entry = Entry{ .directory = num.* };
        // Not present, supervisor mode, read/write
        num.* = masks.set(entry, masks.read_write).value();
    }

    // Keep the higher half mapping in our new page table
    if (boot.KERNEL_NUM_PAGES != 1) {
        @compileError("need to update to handle multiple pages");
    }
    try mapSinglePage(0x0000000, 0xC0000000, 3, .four_mb);

    const phys_addr: u32 = @intFromPtr(&directory) - 0xC0000000;

    // Set up recursive mapping so that we can easily look up pages
    std.debug.assert(std.mem.isAligned(phys_addr, FOUR_KB_SIZE));
    directory[directory.len - 1] = phys_addr | 0x3;

    asm volatile (
        \\ mov %[dir], %cr3
        :
        : [dir] "{eax}" (phys_addr),
        : "eax", "cr3"
    );

    try mapSinglePage(0x0800b000, 0xA0000000, 3, .four_kb);

    asm volatile (
        \\ mov %%cr3, %%eax
        \\ mov %%eax, %%cr3
        ::: "eax", "cr3");

    const test_addr = 0xA0000823;
    const addr = virtToPhys(test_addr) catch |err| blk: {
        switch (err) {
            PageError.NotMapped => {
                Serial.printf("0x{x:08} was not mapped\n", .{test_addr});
                break :blk 0;
            },
            else => @panic("error while translating memory"),
        }
    };
    Serial.printf("addr = 0x{x:08}\n", .{addr});
}
