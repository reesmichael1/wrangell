pub const BOOTLOADER_MAGIC = 0x2BADB002;

const Header = packed struct {
    magic: i32,
    flags: i32,
    checksum: i32,
    padding: i32 = 0,
};

pub const MmapEntry = packed struct {
    size: u32,
    addr: u64,
    len: u64,
    type: u32,
};

export var multiboot align(4) linksection(".rodata.boot") = multiboot: {
    const ALIGN = 1 << 0;
    const MEMINFO = 1 << 1;
    // const MEMMAP = 0x00000040;
    // const FLAGS = ALIGN | MEMMAP | MEMINFO;
    const FLAGS = ALIGN | MEMINFO;
    const MAGIC = 0x1BADB002;
    break :multiboot Header{
        .magic = MAGIC,
        .flags = FLAGS,
        .checksum = -(MAGIC + FLAGS),
    };
};

pub const Info = packed struct {
    flags: u32,

    // Available if bit 0 in FLAGS is set
    mem_lower: u32,
    mem_upper: u32,

    // bit 1 in FLAGS
    boot_device: u32,

    // bit 2 in FLAGS
    cmdline: u32,

    // Boot-Module list
    mods_count: u32,
    mods_addr: u32,

    syms: packed union {
        // bit 4 in FLAGS
        aout: packed struct {
            tabsize: u32,
            strsize: u32,
            addr: u32,
            _: u32,
        },
        // bit 5 in FLAGS
        elf: packed struct {
            num: u32,
            size: u32,
            addr: u32,
            shndx: u32,
        },
    },

    // Memory mapping buffer, bit 6 in FLAGS
    mmap_length: u32,
    mmap_addr: u32,

    // Drive Info buffer
    drives_length: u32,
    drives_addr: u32,

    // ROM configuration table
    config_table: u32,

    // Boot loader name
    boot_loader_name: u32,

    // APM table
    apm_table: u32,

    // Video
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,

    // There are various other fields we can get to eventually,
    // but these are the ones that matter for now
};
