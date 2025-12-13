const std = @import("std");

const arch = @import("arch.zig");
const gdt = @import("gdt.zig");
const pic = @import("pic.zig");
const Vga = @import("vga.zig").Vga;
const Serial = @import("serial.zig").Serial;

const INTERRUPT_GATE: u4 = 0xE;

const IdtError = error{
    IdtEntryExists,
};

const IdtEntry = packed struct(u64) {
    isr_low: u16,
    kernel_cs: u16,
    _: u8 = 0,
    gate_type: u4,
    // This should be 0 for interrupt and trap gates
    storage_segment: u1 = 0,
    privilege: arch.PrivilegeLevel,
    present: u1 = 1,
    isr_high: u16,

    fn make(gate_type: u4, privilege: arch.PrivilegeLevel, handler: *const InterruptHandler) IdtEntry {
        const base: u32 = @intFromPtr(handler);

        return IdtEntry{
            .isr_low = @truncate(base),
            .kernel_cs = gdt.KERNEL_CODE_SELECTOR,
            .gate_type = gate_type,
            .privilege = privilege,
            .isr_high = @truncate(base >> 16),
        };
    }
};

pub const IdtRegister = packed struct {
    limit: u16,
    base: *const IdtEntry,
};

var entries: [256]IdtEntry = [_]IdtEntry{IdtEntry{
    .isr_low = 0,
    .kernel_cs = 0,
    .gate_type = 0,
    .privilege = @enumFromInt(0),
    .present = 0,
    .isr_high = 0,
}} ** 256;

var interrupt_handlers: [256]?*const IsrHandler = [_]?*const IsrHandler{null} ** 256;

var idtr = IdtRegister{
    .limit = @sizeOf(IdtEntry) * entries.len - 1,
    .base = undefined,
};

fn exceptionHandler() noreturn {
    arch.halt();
    arch.iret();
}

pub const InterruptHandler = fn () callconv(.Naked) void;
pub const IsrHandler = fn (CpuState) void;

pub const CpuState = extern struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    int_no: u32,
    error_code: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
};

export fn isrHandler(cpu: CpuState) void {
    Vga.printf("ESP = 0x{x:08}, EIP = 0x{x:08}\n", .{ cpu.esp, cpu.eip });

    // Eventually we'll have more informative fault handling
    // where we can actually check if a fault is recoverable or not.
    switch (cpu.int_no) {
        else => {
            // The longest error name is 30 characters, and our message is 28
            var buf: [58]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "unrecoverable kernel fault: {s}", .{exceptions[cpu.int_no].name}) catch unreachable;
            @panic(msg);
        },
    }
}

export fn irqHandler(cpu: CpuState) void {
    const int_no: u8 = @intCast(cpu.int_no);
    const irq_no = int_no - pic.IRQ_OFFSET;
    if (interrupt_handlers[int_no]) |handler| {
        handler(cpu);
        pic.acknowledge(irq_no);
    } else {
        @panic("unmapped interrupt");
    }
}

fn getIrqStub(int_no: u8) InterruptHandler {
    // int_no is the mapped IRQ number (i.e., 32 for IRQ 0)
    return struct {
        fn func() callconv(.Naked) void {
            asm volatile (
                \\ cli
                \\ pushl $0
                \\ pushl %[nr]
                \\ pusha
                \\ call irqHandler
                \\ popa
                \\ addl $8, %%esp
                \\ iret
                :
                : [nr] "n" (int_no),
            );
        }
    }.func;
}

fn getInterruptStub(int_no: u8) InterruptHandler {
    return struct {
        fn func() callconv(.Naked) void {
            asm volatile ("cli");

            if (!exceptions[int_no].has_error) {
                asm volatile ("pushl $0");
            }

            asm volatile (
                \\ pushl %[nr]
                \\ pusha
                \\ call isrHandler
                \\ popa
                \\ addl $8, %%esp
                \\ iret
                :
                : [nr] "n" (int_no),
            );
        }
    }.func;
}

fn openGate(int_no: u8, handler: InterruptHandler) IdtError!void {
    if (entries[int_no].present == 1) {
        return IdtError.IdtEntryExists;
    }
    entries[int_no] = IdtEntry.make(INTERRUPT_GATE, arch.PrivilegeLevel.ring0, handler);
}

const Exception = struct {
    name: []const u8,
    index: u8,
    has_error: bool,
};

const exceptions = [32]Exception{
    Exception{ .name = "Division Error", .index = 0, .has_error = false },
    Exception{ .name = "Debug", .index = 1, .has_error = false },
    Exception{ .name = "Non-Maskable Interrupt", .index = 2, .has_error = false },
    Exception{ .name = "Breakpoint", .index = 3, .has_error = false },
    Exception{ .name = "Overflow", .index = 4, .has_error = false },
    Exception{ .name = "Bound Range Exceeded", .index = 5, .has_error = false },
    Exception{ .name = "Invalid Opcode", .index = 6, .has_error = false },
    Exception{ .name = "Device Not Available", .index = 7, .has_error = false },
    Exception{ .name = "Double Fault", .index = 8, .has_error = true },
    Exception{ .name = "Coprocessor Segment Overrun", .index = 9, .has_error = false },
    Exception{ .name = "Invalid TSS", .index = 10, .has_error = true },
    Exception{ .name = "Segment Not Present", .index = 11, .has_error = true },
    Exception{ .name = "Stack Segment Fault", .index = 12, .has_error = true },
    Exception{ .name = "General Protection Fault", .index = 13, .has_error = true },
    Exception{ .name = "Page Fault", .index = 14, .has_error = true },
    Exception{ .name = "Reserved", .index = 15, .has_error = false },
    Exception{ .name = "x87 Floating Point Exception", .index = 16, .has_error = false },
    Exception{ .name = "Alignment Check", .index = 17, .has_error = true },
    Exception{ .name = "Machine Check", .index = 18, .has_error = false },
    Exception{ .name = "SIMD Floating Point Exception", .index = 19, .has_error = false },
    Exception{ .name = "Virtualization Exception", .index = 20, .has_error = false },
    Exception{ .name = "Control Protection Exception", .index = 21, .has_error = true },
    Exception{ .name = "Reserved", .index = 22, .has_error = false },
    Exception{ .name = "Reserved", .index = 23, .has_error = false },
    Exception{ .name = "Reserved", .index = 24, .has_error = false },
    Exception{ .name = "Reserved", .index = 25, .has_error = false },
    Exception{ .name = "Reserved", .index = 26, .has_error = false },
    Exception{ .name = "Reserved", .index = 27, .has_error = false },
    Exception{ .name = "Hypervisor Injection Exception", .index = 28, .has_error = false },
    Exception{ .name = "VMM Communication Exception", .index = 29, .has_error = true },
    Exception{ .name = "Security Exception", .index = 30, .has_error = true },
    Exception{ .name = "Reserved", .index = 31, .has_error = false },
};

const irqs = [_]u8{ 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47 };

pub fn init() void {
    Serial.writeln("beginning IDT initialization");
    defer Serial.printf("initialized IDT: {*}\n", .{idtr.base});

    inline for (0.., exceptions) |i, _| {
        openGate(i, getInterruptStub(i)) catch {
            @panic("tried to open duplicate IDT gate");
        };
    }

    pic.init();

    inline for (irqs) |irq| {
        openGate(irq, getIrqStub(irq)) catch {
            @panic("tried to open duplicate IRQ gate");
        };
    }

    idtr.base = &entries[0];
    arch.lidt(&idtr);
}

pub fn setIrqCallback(irq_line: u8, callback: *const IsrHandler) void {
    const ix = pic.mappedPort(irq_line);

    if (entries[ix].present != 1) {
        @panic("tried to set callback for closed gate");
    }

    Serial.printf("mapping IRQ port 0x{x} to 0x{x}\n", .{ irq_line, ix });
    interrupt_handlers[ix] = callback;
}

pub fn isGateOpen(ix: u8) bool {
    return entries[ix].present == 1;
}
