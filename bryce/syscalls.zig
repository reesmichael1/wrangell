const syscall_abi = @import("syscall_abi");

pub const SysError = error{
    BadFd,
    BadSyscall,
};

fn errorFromInt(code: i32) SysError {
    const err: syscall_abi.ErrorNumber = @enumFromInt(code);
    return switch (err) {
        .bad_fd => SysError.BadFd,
        .bad_syscall => SysError.BadSyscall,
    };
}

pub fn sysExit(code: u32) noreturn {
    _ = sys1(syscall_abi.Number.exit, code);
    unreachable;
}

pub fn sysWrite(fd: u32, msg: u32) SysError!i32 {
    const code = sys2(syscall_abi.Number.write, fd, msg);
    if (code <= syscall_abi.ERR_HIGH and code >= syscall_abi.ERR_LOW) {
        return errorFromInt(code);
    }

    return code;
}

fn sys1(call: syscall_abi.Number, a: u32) i32 {
    const num: u32 = @intCast(@intFromEnum(call));
    return asm volatile (
        \\ int %[int]
        : [ret] "={eax}" (-> i32),
        : [num] "{eax}" (num),
          [a] "{ebx}" (a),
          [int] "n" (syscall_abi.SYSCALL_INT_NO),
    );
}

fn sys2(call: syscall_abi.Number, a: u32, b: u32) i32 {
    const num: u32 = @intCast(@intFromEnum(call));
    return asm volatile (
        \\ int %[int]
        : [ret] "={eax}" (-> i32),
        : [num] "{eax}" (num),
          [a] "{ebx}" (a),
          [b] "{ecx}" (b),
          [int] "n" (syscall_abi.SYSCALL_INT_NO),
    );
}
