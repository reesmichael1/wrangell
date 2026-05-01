const Abi = @import("syscall_abi");
const arch = @import("../arch.zig").internals;

// ebx, ecx, edx, esi, edi
pub fn dispatch(num: Abi.Number, a: u32, b: u32, c: u32, d: u32, e: u32) void {
    _ = b;
    _ = c;
    _ = d;
    _ = e;
    switch (num) {
        .exit => {
            sysExit(a);
        },
    }
}

pub fn sysExit(code: u32) noreturn {
    arch.Serial.printf("user exited with code {}\n", .{code});
    while (true) {
        arch.halt();
    }
}
