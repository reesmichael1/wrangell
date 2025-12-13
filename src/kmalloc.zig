const arch = @import("arch.zig").internals;

const PAGE_SIZE = 4096;

const HEAP_START = 0xC0400000;
const HEAP_END = 0xC0800000;

var heap_top: u32 = HEAP_START;

pub fn kmalloc(bytes: usize) ?u32 {
    const num_pages = (bytes + PAGE_SIZE - 1) / PAGE_SIZE;

    if (heap_top + num_pages * PAGE_SIZE > HEAP_END) {
        return null;
    }

    const base_virt = heap_top;

    var i: usize = 0;
    while (i < num_pages) : (i += 1) {
        const addr = arch.pmem.alloc() catch return null;
        const virt = heap_top;

        arch.vmem.mapSinglePage(addr, virt, arch.vmem.masks.present | arch.vmem.masks.read_write, .four_kb) catch return null;

        heap_top += PAGE_SIZE;
    }

    return base_virt;
}
