const std = @import("std");
const arch = @import("arch.zig").internals;
const Serial = arch.Serial;

const PAGE_SIZE = 4096;

const HEAP_START = 0xC0400000;
const HEAP_SIZE = 4 * 1024 * 1024; // 4 MB
const HEAP_END = HEAP_START + HEAP_SIZE;

var heap_top: u32 = HEAP_START;
var next_page_start: u32 = HEAP_START;

pub fn kmalloc(bytes: usize) ?u32 {
    const aligned_bytes = std.mem.alignForward(u32, bytes, 8);
    const room_in_page = next_page_start - heap_top;

    if (aligned_bytes <= room_in_page) {
        // In this case, there is no need to allocate a new page
        // Instead, we can use the bytes from the previously allocated page
        const region = heap_top;
        heap_top += aligned_bytes;
        return region;
    }

    const overflow = aligned_bytes - room_in_page;
    const num_pages = (overflow + PAGE_SIZE - 1) / PAGE_SIZE;

    if (next_page_start + num_pages * PAGE_SIZE > HEAP_END) {
        Serial.writeln("cannot allocate enough pages to satisfy request");
        return null;
    }

    const base_virt = heap_top;
    heap_top = next_page_start;
    var remaining = overflow;

    std.debug.assert(num_pages >= 1);

    var i: usize = 1;
    while (i <= num_pages) : (i += 1) {
        const addr = arch.pmem.alloc() catch |err| {
            Serial.printf("error while allocating page: {}\n", .{err});
            return null;
        };

        arch.vmem.mapSinglePage(addr, next_page_start, arch.vmem.masks.present | arch.vmem.masks.read_write, .four_kb) catch |err| {
            Serial.printf("error while mapping 0x{x:08} to 0x{x:08}: {}\n", .{ addr, next_page_start, err });
            return null;
        };
        next_page_start += PAGE_SIZE;

        if (remaining >= PAGE_SIZE) {
            heap_top += PAGE_SIZE;
            remaining -= PAGE_SIZE;
        } else {
            heap_top += remaining;
        }
    }

    return base_virt;
}
