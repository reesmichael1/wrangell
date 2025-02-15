const arch = @import("arch.zig");

const MultiBoot = packed struct {
    magic: i32,
    flags: i32,
    checksum: i32,
    padding: i32 = 0,
};

const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const FLAGS = ALIGN | MEMINFO;
const MAGIC = 0x1BADB002;

const STACK_SIZE = 16 * 1024;
export var stack_bytes: [STACK_SIZE]u8 align(16) linksection(".bss.stack") = undefined;
extern var KERNEL_ADDR_OFFSET: u32;
const KERNEL_PAGE_NUMBER = 0xC0200000 >> 22;
const KERNEL_NUM_PAGES = 1;

export var multiboot align(4) linksection(".rodata.boot") = MultiBoot{
    .magic = MAGIC,
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

export var boot_page_directory align(4096) linksection(".text.boot") = init: {
    var dir: [1024]u32 = .{0} ** 1024;

    // Bits set: 7, 1, 0 -> this page is present, 4MB, read/write, supervisor
    // The memory address bits are all 0, so this maps 0-4M -> 0-4M
    dir[0] = 0x83;

    if (KERNEL_NUM_PAGES != 1) {
        @compileError("need to update kernel mapping for multiple pages");
    }

    // Map the single higher half page to the lower address space
    dir[KERNEL_PAGE_NUMBER] = 0x83;

    break :init dir;
};

extern fn kmain() void;

export fn _start() linksection(".text.boot") callconv(.Naked) noreturn {
    // asm volatile (
    //     \\ mov $stack_bytes, %%esp
    //     \\ add %[stack_size], %%esp
    //     \\ call kmain
    //     :
    //     : [stack_size] "n" (STACK_SIZE),
    // );
    //
    //     :
    //     : [dir] "r" (@intFromPtr(&directory)),
    //     : "eax", "cr0"

    asm volatile (
    // Enable paging with higher half mapping
        \\ .extern boot_page_directory
        \\ mov $boot_page_directory, %%ecx
        // \\ mov (%[boot_dir]), %%ecx
        \\ mov %%ecx, %%cr3

        // Enable 4MB pages (for now, the only place we use them is in the kernel mapping above)
        \\ mov %%cr4, %%eax
        \\ or $0x00000010, %%eax
        \\ mov %%eax, %%cr4

        // Actually enable the paging bit in cr0
        \\ mov %%cr0, %%eax
        \\ or $0x80000000, %%eax
        \\ mov %%eax, %%cr0

        // Enter the kernel at a higher half address
        \\ jmp start_higher_half
        ::
        // : [boot_dir] "r" (@intFromPtr(&boot_page_directory)),
        : "ecx", "cr3", "cr0");
}

export fn start_higher_half() callconv(.Naked) noreturn {
    // Now we are mapped so that we can operate in the higher half
    // arch.invalidatePage(0);

    boot_page_directory[0] = 0;

    asm volatile (
        \\ invlpg (0)
        \\ mov %%cr3, %%ecx
        \\ mov %%ecx, %%cr3
        \\ mov $stack_bytes, %%esp
        \\ add %[stack_size], %%esp
        \\ call kmain
        :
        : [stack_size] "n" (STACK_SIZE),
    );
}
