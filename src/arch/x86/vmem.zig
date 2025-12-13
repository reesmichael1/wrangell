const std = @import("std");

const boot = @import("boot.zig");
const pmem = @import("pmem.zig");
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

const Flags = enum(u32) {
    present = 0b001,
};

pub const masks = struct {
    pub const address: u32 = 0xFFFFF000;
    pub const avl: u32 = 0xF00;
    pub const page_size: u32 = 0x80;
    pub const accessed: u32 = 0x20;
    pub const cache_disabled: u32 = 0x10;
    pub const write_through: u32 = 0x08;
    pub const user_supervisor: u32 = 0x04;
    pub const read_write: u32 = 0x02;
    pub const dirty: u32 = 0x40;
    pub const present: u32 = 0x01;
    pub const pat: u32 = 0x80;
    pub const global: u32 = 0x100;

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

pub const PageError = error{
    AlreadyMapped,
    AddrNotAligned,
    NotMapped,
    OutOfMemory,
};

fn pageDirectoryIndexToPhysAddr(index: u32) u32 {
    return 0xFFC00000 + 0x1000 * index;
}

pub fn virtToPhys(virt: u32) PageError!u32 {
    const pd_index = virt >> 22;
    const pt_index = (virt >> 12) & 0x03ff;

    const pd: *[1024]DirectoryEntry = @ptrFromInt(0xFFFFF000);
    if (pd[pd_index] & masks.present == 0) {
        return PageError.NotMapped;
    }

    const pt: *[1024]DirectoryEntry = @ptrFromInt(pageDirectoryIndexToPhysAddr(pd_index));
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
    var pt: *[1024]DirectoryEntry align(FOUR_KB_SIZE) = blk: {
        if (pd[pd_index] & masks.present != 0) {
            const pt: *[1024]DirectoryEntry align(FOUR_KB_SIZE) = @ptrFromInt(pageDirectoryIndexToPhysAddr(pd_index));
            break :blk pt;
        } else {
            // First we allocate a page from the physical memory manager
            // We can then update the page directory to point to this page,
            // which we also initialize as an empty page table.
            const page_phys = pmem.alloc() catch |err| {
                switch (err) {
                    pmem.PmemError.OutOfMemory => return PageError.OutOfMemory,
                }
            };

            // Set the PD entry to point to the new page table
            pd[pd_index] = page_phys | flags | masks.present;

            // Flush TLB so the CPU knows about the new PD entry
            asm volatile (
                \\ mov %%cr3, %%eax
                \\ mov %%eax, %%cr3
                ::: "eax", "cr3");

            const pt: *[1024]DirectoryEntry = @ptrFromInt(pageDirectoryIndexToPhysAddr(pd_index));
            for (pt) |*entry| {
                entry.* = 0;
            }

            break :blk pt;
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

    // Initialize all entries as not present
    for (&directory) |*num| {
        const entry = Entry{ .directory = num.* };
        // // Not present, supervisor mode, read/write
        num.* = masks.set(entry, masks.read_write).value();
    }

    // Keep the higher half mapping in our new page table
    if (boot.KERNEL_NUM_PAGES != 1) {
        @compileError("need to update to handle multiple pages");
    }

    directory[768] = 0x83; // | flags | (1 << 7); // 4 MiB page flag
    const phys_addr: u32 = @intFromPtr(&directory) - 0xC0000000;

    // Set up recursive mapping so that we can easily look up pages
    std.debug.assert(std.mem.isAligned(phys_addr, FOUR_KB_SIZE));
    directory[directory.len - 1] = phys_addr | 0x3;

    // Replace the original page table with the updated one
    asm volatile (
        \\ mov %[dir], %cr3
        :
        : [dir] "{eax}" (phys_addr),
        : "eax", "cr3"
    );
}
