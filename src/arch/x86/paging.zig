const Serial = @import("serial.zig").Serial;

// Page Directory Table = list of 1024 PDEs
// Each page directory entry is a list of 1024 page tables
// Each page table points to 4kb of memory

const DirectoryEntry = u32;

// const EntryKind = enum {
//     directory,
//     table,
// };

const Entry = union(enum) {
    directory: DirectoryEntry,
    table: DirectoryEntry,

    fn value(self: Entry) DirectoryEntry {
        switch (self) {
            .directory, .table => |n| return n,
        }
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

var directory: [1024]DirectoryEntry align(4096) = .{0} ** 1024;
var first_page_table: [1024]DirectoryEntry align(4096) = .{0} ** 1024;

fn virtToPhys(ptr: *anyopaque) u32 {
    const addr: u32 = @intFromPtr(ptr);
    return addr - 0xC0000000;
}

pub fn init() void {
    Serial.writeln("initializing page directory");
    defer Serial.printf("initialized paging with page directory: {*}\n", .{&directory});

    for (&directory) |*num| {
        const entry = Entry{ .directory = num.* };
        // Not present, supervisor mode, read/write
        num.* = masks.set(entry, masks.read_write).value();
    }

    for (0.., &first_page_table) |ix, *num| {
        // Set bits for address in top 20, then 3 = supervisor, read/write, present
        num.* |= (ix << 12) | 3;
    }

    directory[0] = @intFromPtr(&first_page_table) | 3;
    const phys_addr = virtToPhys(&directory);
    Serial.printf("phys_addr = 0x{x}\n", .{phys_addr});

    // asm volatile (
    //     \\ mov %[dir], %cr3
    //     // \\ mov %%cr0, %%eax
    //     // \\ or $0x80000000, %%eax
    //     // \\ mov %%eax, %%cr0
    //     :
    //     : [dir] "{eax}" (phys_addr),
    //       // : [dir] "{eax}" (@intFromPtr(&directory)),
    //     : "eax", "cr3"
    // );
}
