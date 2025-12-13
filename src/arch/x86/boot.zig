const std = @import("std");
const builtin = @import("builtin");
const arch = @import("arch.zig");
const multiboot = @import("../../multiboot.zig");

const STACK_SIZE = if (builtin.mode == .Debug) 128 * 1024 else 16 * 1024;
pub export var stack_bytes: [STACK_SIZE]u8 align(16) linksection(".bss.stack") = undefined;
extern var KERNEL_ADDR_OFFSET: u32;
pub const KERNEL_PAGE_NUMBER = 0xC0200000 >> 22;
pub const KERNEL_NUM_PAGES = 1;

export var boot_page_directory align(4096) linksection(".text.boot") = init: {
    var dir: [1024]u32 = .{0} ** 1024;

    // Identity map the lowest MB of memory
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

extern fn kmain(magic: u32, info: *const multiboot.Info) void;

export fn _start() linksection(".text.boot") callconv(.Naked) noreturn {
    asm volatile (
    // Enable paging with higher half mapping
        \\ .extern boot_page_directory
        \\ mov $boot_page_directory, %%ecx
        \\ mov %%ecx, %%cr3

        // Enable 4MB pages (for now, the only place we use them is in the kernel mapping above)
        \\ mov %%cr4, %%ecx
        \\ or $0x00000010, %%ecx
        \\ mov %%ecx, %%cr4

        // Actually enable the paging bit in cr0
        \\ mov %%cr0, %%ecx
        \\ or $0x80000000, %%ecx
        \\ mov %%ecx, %%cr0

        // Enter the kernel at a higher half address
        \\ jmp start_higher_half
        ::: "ecx", "cr3", "cr0");
}

export fn start_higher_half() callconv(.Naked) noreturn {
    // Now we are mapped so that we can operate in the higher half

    asm volatile (
        \\ mov $stack_bytes, %%esp
        \\ add %[stack_size], %%esp
        // Increase the boot info address by the kernel offset (since we're now higher halved)
        \\ add $0xC0000000, %%ebx
        \\ push %%ebx
        \\ push %%eax
        \\ call kmain
        :
        : [stack_size] "n" (STACK_SIZE),
    );
}
