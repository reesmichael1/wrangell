const Abi = @import("syscall_abi");
const arch = @import("../arch.zig").internals;

pub const SysError = error{
    BadSyscallNum,
    BadFd,
};

pub fn intFromError(err: SysError) i32 {
    switch (err) {
        error.BadSyscallNum => return -1,
        error.BadFd => return -2,
    }
}

pub fn errorFromInt(code: i32) SysError!i32 {
    if (code >= 0) {
        return code;
    }

    switch (code) {
        .bad_syscall => return SysError.BadSyscallNum,
        .bad_fd => return SysError.BadFd,
    }
}

// ebx, ecx, edx, esi, edi
pub fn dispatch(num: Abi.Number, a: i32, b: i32, c: i32, d: i32, e: i32) SysError!struct { i32, i32 } {
    _ = c;
    _ = d;
    _ = e;
    arch.Serial.printf("got to the dispatch, code = {}\n", .{num});
    switch (num) {
        .exit => {
            sysExit(a);
            unreachable;
        },
        .write => {
            try sysWrite(a, b);
            return .{ 0, 0 };
        },
    }
}

pub fn sysExit(code: i32) noreturn {
    arch.Serial.printf("user exited with code {}\n", .{code});
    while (true) {
        arch.halt();
    }
}

pub fn sysWrite(fd: i32, msg: i32) SysError!void {
    if (fd == 1) {
        arch.Serial.printf("[write] msg = {}\n", .{msg});
    } else if (fd == 2) {
        arch.Vga.printf("[write] msg = {}\n", .{msg});
    } else {
        arch.Serial.printf("[write] bad file descriptor!\n", .{});
        return SysError.BadFd;
    }
}
