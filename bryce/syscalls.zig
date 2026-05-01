const syscall_abi = @import("syscall_abi");

pub fn sysExit(code: u32) noreturn {
    sys1(syscall_abi.Number.exit, code);
    unreachable;
}

fn sys1(call: syscall_abi.Number, a: u32) void {
    const num: u32 = @intCast(@intFromEnum(call));
    asm volatile (
        \\ int %[int]
        :
        : [num] "{eax}" (num),
          [a] "{ebx}" (a),
          [int] "n" (syscall_abi.SYSCALL_INT_NO),
    );
}
