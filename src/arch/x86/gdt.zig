const arch = @import("arch.zig");
const Serial = @import("serial.zig").Serial;

const DescriptorType = enum(u1) {
    system,
    code_data,
};

const Executable = enum(u1) {
    data,
    executable,
};

const ReadWriteable = enum(u1) {
    forbidden,
    allowed,
};

const AccessByte = packed struct {
    accessed: u1,
    rw: ReadWriteable,
    direction_conforming: u1,
    executable: Executable,
    descriptor: DescriptorType,
    privilege: arch.PrivilegeLevel,
    present: u1 = 1,
};

const Granularity = enum(u1) {
    one_byte,
    four_kbyte,
};

const Size = enum(u1) {
    // 16-bit protected mode segment
    bit16,
    // 32-bit protected mode segment
    bit32,
};

const Long = enum(u1) {
    other,
    code64,
};

const Flags = packed struct {
    reserved: u1 = 0,
    long_mode: Long,
    size: Size,
    granularity: Granularity,
};

const GdtEntry = packed struct {
    base: u32,
    limit: u20,
    access: AccessByte,
    flags: Flags,

    fn to_int(comptime self: GdtEntry) u64 {
        comptime {
            const base_high: u64 = @as(u64, self.base & 0xFF000000) << 32;
            const base_low: u24 = @truncate(self.base);
            const limit_high: u52 = @as(u64, self.limit & 0xF0000) << 32;
            const limit_low: u16 = @truncate(self.limit);
            const flags_bits: u4 = @bitCast(self.flags);
            const access_bits: u8 = @bitCast(self.access);

            const flags: u56 = @as(u56, flags_bits) << 52;
            const access: u48 = @as(u48, access_bits) << 40;

            return base_high | flags | limit_high | access | base_low | limit_low;
        }
    }
};

const kernel_null_segment = AccessByte{
    .present = 0,
    .privilege = .ring0,
    .descriptor = @enumFromInt(0),
    .executable = .data,
    .direction_conforming = 0,
    .rw = .forbidden,
    .accessed = 0,
};

const kernel_code_segment = AccessByte{
    .accessed = 0,
    .rw = .allowed,
    .direction_conforming = 0,
    .executable = .executable,
    .descriptor = .code_data,
    .privilege = .ring0,
};

const kernel_data_segment = AccessByte{
    .accessed = 0,
    .rw = .allowed,
    .direction_conforming = 0,
    .executable = .data,
    .descriptor = .code_data,
    .privilege = .ring0,
};

const user_code_segment = AccessByte{
    .accessed = 0,
    .rw = .allowed,
    .direction_conforming = 0,
    .executable = .executable,
    .descriptor = .code_data,
    .privilege = .ring3,
};

const user_data_segment = AccessByte{
    .accessed = 0,
    .rw = .allowed,
    .direction_conforming = 0,
    .executable = .data,
    .descriptor = .code_data,
    .privilege = .ring3,
};

const paging_32_bit = Flags{
    .granularity = .four_kbyte,
    .size = .bit32,
    .long_mode = .other,
};

const null_flags = Flags{
    .granularity = @enumFromInt(0),
    .size = @enumFromInt(0),
    .long_mode = @enumFromInt(0),
};

const null_entry = GdtEntry{
    .base = 0,
    .limit = 0,
    .access = kernel_null_segment,
    .flags = null_flags,
};

const kernel_mode_code_entry = GdtEntry{
    .base = 0,
    .limit = 0xFFFFF,
    .access = kernel_code_segment,
    .flags = paging_32_bit,
};
const kernel_mode_data_entry = GdtEntry{
    .base = 0,
    .limit = 0xFFFFF,
    .access = kernel_data_segment,
    .flags = paging_32_bit,
};
const user_mode_code_entry = GdtEntry{
    .base = 0,
    .limit = 0xFFFFF,
    .access = user_code_segment,
    .flags = paging_32_bit,
};
const user_mode_data_entry = GdtEntry{
    .base = 0,
    .limit = 0xFFFFF,
    .access = user_data_segment,
    .flags = paging_32_bit,
};

pub const NULL_SELECTOR = 0x0;
pub const KERNEL_CODE_SELECTOR = 0x08;
pub const KERNEL_DATA_SELECTOR = 0x10;
pub const USER_CODE_SELECTOR = 0x18;
pub const USER_DATA_SELECTOR = 0x20;

// Store entires as u64s instead of GdtEntries because we need to convert into the weird data format
// in memory (instead of the sane version the packed u64 would give us)
pub const entries: [5]u64 = .{ null_entry.to_int(), kernel_mode_code_entry.to_int(), kernel_mode_data_entry.to_int(), user_mode_code_entry.to_int(), user_mode_data_entry.to_int() };

pub const GdtPtr = packed struct {
    limit: u16,
    base: *const u64,
};

var ptr = GdtPtr{
    .limit = @sizeOf(GdtEntry) * entries.len - 1,
    .base = undefined,
};

pub fn init() void {
    Serial.writeln("beginning GDT initialization");
    defer Serial.printf("initialized GDT: {*}\n", .{ptr.base});

    ptr.base = &entries[0];
    arch.lgdt(&ptr);
}
