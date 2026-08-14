const syscall_abi = @import("syscall_abi");

pub const SysError = error{
    BadFd,
    BadSyscall,
    BadAddress,
    Overflow,
    OutOfRange,
    Unknown,
};

fn errorFromInt(code: i32) SysError {
    const err: syscall_abi.ErrorNumber = @enumFromInt(code);
    return switch (err) {
        .bad_fd => SysError.BadFd,
        .bad_syscall => SysError.BadSyscall,
        .bad_address => SysError.BadAddress,
        .overflow => SysError.Overflow,
        .out_of_range => SysError.OutOfRange,
        _ => SysError.Unknown,
    };
}

pub fn exit(code: u8) noreturn {
    _ = sys1(syscall_abi.Number.exit, code);
    unreachable;
}

pub fn write(fd: syscall_abi.FD, msg: usize, length: usize) SysError!usize {
    const ret = sys3(syscall_abi.Number.write, @intFromEnum(fd), msg, length);
    const code: i32 = @bitCast(ret.a);
    if (code <= syscall_abi.ERR_HIGH and code >= syscall_abi.ERR_LOW) {
        return errorFromInt(code);
    }

    return ret.a;
}

pub const ReturnVals = struct {
    a: u32,
    b: u32,

    const Self = @This();

    fn fromU64(n: u64) Self {
        const a: u32 = @truncate(n);
        const b: u32 = @truncate(n >> 32);

        return .{ .a = a, .b = b };
    }
};

// TODO: meta-ify these so that we don't have to repeat ad infinitum
fn sys1(call: syscall_abi.Number, a: u32) ReturnVals {
    const num = @intFromEnum(call);
    const r = asm volatile (
        \\ int %[int]
        : [ret] "=A" (-> u64),
        : [num] "{eax}" (num),
          [a] "{ebx}" (a),
          [int] "n" (syscall_abi.SYSCALL_INT_NO),
    );

    return ReturnVals.fromU64(r);
}

fn sys2(call: syscall_abi.Number, a: u32, b: u32) ReturnVals {
    const num = @intFromEnum(call);
    const r = asm volatile (
        \\ int %[int]
        : [ret] "=A" (-> u64),
        : [num] "{eax}" (num),
          [a] "{ebx}" (a),
          [b] "{ecx}" (b),
          [int] "n" (syscall_abi.SYSCALL_INT_NO),
    );

    return ReturnVals.fromU64(r);
}

fn sys3(call: syscall_abi.Number, a: u32, b: u32, c: u32) ReturnVals {
    const num = @intFromEnum(call);
    const r = asm volatile (
        \\ int %[int]
        : [ret] "=A" (-> u64),
        : [num] "{eax}" (num),
          [a] "{ebx}" (a),
          [b] "{ecx}" (b),
          [c] "{edx}" (c),
          [int] "n" (syscall_abi.SYSCALL_INT_NO),
    );

    return ReturnVals.fromU64(r);
}
