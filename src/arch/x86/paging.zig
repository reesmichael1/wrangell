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
    // address = 0xFFFFF000,
    // avl = 0xF00,
    // page_size = 0x80,
    // accessed = 0x20,
    // cache_disabled = 0x10,
    // write_through = 0x08,
    // user_supervisor = 0x04,
    // read_write = 0x02,
    // dirty = 0x40,
    // present = 0x01,
    // pat = 0x80,
    // global = 0x100,

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
    // Serial.printf("virt = 0x{x:08}\n", .{virt});
    // return virt;

    // return PD[PT[virt >> 22]][virt >> 12];
    // const pt_index = PD[virt >> 22];
    // return PT[pt_index][virt >> 12];

    const pd_index = virt >> 22;
    const pt_index = (virt >> 12) & 0x03ff;

    // const pd: *[1024]DirectoryEntry = @ptrFromInt(0xFFFFF000);
    // const pts: *[1024]*[1024]DirectoryEntry = @ptrFromInt(0xFFC00000);
    //
    // const pt = pts[pd_index];
    // return pt[pt_index];

    // _ = pd_index;
    // _ = pt_index;
    //
    // _ = pd;
    // _ = pt;

    // return PageError.NotMapped;

    const pd: *[1024]DirectoryEntry = @ptrFromInt(0xFFFFF000);
    Serial.writeln("loaded pd");
    if (pd[pd_index] & masks.present == 0) {
        return PageError.NotMapped;
    }

    // const pt: *[1024]DirectoryEntry = @ptrFromInt(pd[pd_index] & 0xFFFFF000);
    const pt: *[1024]DirectoryEntry = @ptrFromInt(0xFFC00000 + 0x4 * pd_index);
    // + (0x400 * pd_index));
    Serial.writeln("loaded pt");
    Serial.printf("pd = {*}\n", .{pd});
    Serial.printf("pt = {*}\n", .{pt});
    Serial.printf("pt_index = 0x{x:08}\n", .{pt_index});
    if (pt[pt_index] & masks.present == 0) {
        return PageError.NotMapped;
    }

    Serial.writeln("actually used pt");
    return (pt[pt_index] & 0xFFFFF000) + (virt & 0xFFF);
}

pub fn virtToPhysOld(addr: u32) PageError!u32 {
    // Most significant 10 bits of the address are the PDE index
    const pde_index = addr >> 22;

    Serial.printf("pde_index = 0x{x:08}\n", .{pde_index});
    const pde_entry = directory[pde_index];
    Serial.printf("pde_entry = 0x{x:08}\n", .{pde_entry});

    if (!masks.is_set(Entry{ .directory = pde_entry }, masks.present)) {
        return PageError.NotMapped;
    }

    if (masks.is_set(Entry{ .directory = pde_entry }, masks.page_size)) {
        @panic("todo!");
    }

    const pte_addr = (pde_entry >> 12) & 0x03ff;

    // Aha! This is the problem: pte_addr is the physical address of the page table,
    // but need to be able to translate that into a virtual address.
    // For now, we'll use our known mapping to fix this, but we'll switch to recursive mapping soon.
    const page_table: *[1024]DirectoryEntry align(FOUR_KB_SIZE) = @ptrFromInt(pte_addr + 0xC0000000);
    // const page_table = tables[

    const pte_index = (addr >> 12) & 0x03ff;
    Serial.printf("pte_index = 0x{x:08}\n", .{pte_index});

    // const page_table: Table = tables[pte_index].?.*;

    const pte = page_table[pte_index];
    if (!masks.is_set(Entry{ .table = pte }, masks.present)) {
        return PageError.NotMapped;
    }

    // const base_addr = pte >> 22;
    const base_addr = pte & 0xFFFFF000;

    const page_offset = addr & 0x00000FFF;
    Serial.printf("base_addr = 0x{x:08}\n", .{base_addr});
    Serial.printf("page_offset = 0x{x:08}\n", .{page_offset});

    return base_addr + page_offset;
}

pub fn mapSinglePageOld(phys: u32, virt: u32, flags: u32, size: Size) PageError!void {
    // if (!size.isAligned(phys) or !size.isAligned(virt)) return PageError.AddrNotAligned;

    if (size == .four_mb) {
        // 4 MB pages are just a pointer to a page (so we don't need a page table)
        const pd_index = virt >> 22;
        // If we're here, then phys is already 4 MB aligned, so...
        directory[pd_index] = phys | masks.page_size | flags;
        return;
    }

    // pd_index adjusts the offset in the *virtual* address space
    // in 4 MB chunks: 0 = 0 to 4MB, 1 = 4 to 8 MB, and so on.
    // Take the top 10 bits of my target virtual offset as the table index.
    const pd_index = virt >> 22;
    var table: Table align(FOUR_KB_SIZE) = blk: {
        // In theory, we should be able to just switch on whether directory[pd_index] is null
        // I chose this way because what the actual in-memory PDE says should be law,
        // and then if tables[pd_index] is null, we can have a crash to track down.
        if (directory[pd_index] & masks.present != 0) {
            break :blk tables[pd_index].?.*;
        } else {
            directory[pd_index] |= masks.present;
            break :blk Table{ .entries = .{0} ** 1024 };
        }
    };

    const pt_index = (virt >> 12) & 0x03ff;
    if (table.entries[pt_index] & masks.present != 0) {
        return PageError.AlreadyMapped;
    }

    // Serial.printf("in mapping, pd_index = 0x{x:08}\n", .{pd_index});
    // Serial.printf("in mapping, pt_index = 0x{x:08}\n", .{pt_index});

    // Set bits for address in top 20, then add the flags
    // Adjust the address by my base physical offset
    table.entries[pt_index] = ((pt_index << 12) + phys) | flags;
    tables[pd_index] = &table;

    // Serial.printf("in mapping, pd_index = 0x{x:08}\n", .{pd_index});

    // @intFromPtr returns a virtual address since we're already mapped into the higher half.
    directory[pd_index] = (@intFromPtr(&table) - 0xC0000000) | flags;
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

pub fn init() void {
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
    // mapSinglePageOld(0x0, 0xC0000000, 3, .four_mb) catch unreachable;

    // var i: usize = 0;
    // while (i < 1024) : (i += 1) {
    //     mapSinglePageOld(i * FOUR_KB_SIZE, 0xC0200000 + i * FOUR_KB_SIZE, 3, .four_kb) catch unreachable;
    // }

    mapSinglePage(0x0000000, 0xC0000000, 3, .four_mb) catch unreachable;

    // Serial.printf("actual value = 0x{x:08}\n", .{directory[boot.KERNEL_PAGE_NUMBER]});

    // mapSinglePage(0x000C1000, 0xA0001000, 3, .four_kb) catch unreachable;
    // mapSinglePage(0x000C2000, 0xA0002000, 3, .four_kb) catch unreachable;
    // mapSinglePage(0x000C3000, 0xA0003000, 3, .four_kb) catch unreachable;

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

    mapSinglePage(0x0000b000, 0xA0000000, 3, .four_kb) catch unreachable;

    // asm volatile (
    //     \\ mov %%cr3, %%eax
    //     \\ mov %%eax, %%cr3
    //     ::: "eax", "cr3");

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
