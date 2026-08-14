const Abi = @import("syscall_abi");
const arch = @import("../arch.zig").internals;
const std = @import("std");

pub const SysError = error{
    BadSyscall,
    BadFd,
    BadAddress,
    Overflow,
    OutOfRange,
};

pub fn intFromError(err: SysError) Abi.ErrorNumber {
    switch (err) {
        error.BadSyscall => return .bad_syscall,
        error.BadFd => return .bad_fd,
        error.BadAddress => return .bad_address,
        error.Overflow => return .overflow,
        error.OutOfRange => return .out_of_range,
    }
}

// ebx, ecx, edx, esi, edi
pub fn dispatch(num: Abi.Number, a: u32, b: u32, c: u32, d: u32, e: u32) SysError!struct { u32, u32 } {
    _ = d;
    _ = e;
    switch (num) {
        .exit => {
            if (a > std.math.maxInt(u8)) {
                return SysError.OutOfRange;
            }
            sysExit(@truncate(a));
            unreachable;
        },
        .write => {
            if (a > std.math.maxInt(@typeInfo(Abi.FD).@"enum".tag_type)) {
                return SysError.BadFd;
            }

            const fd: Abi.FD = @enumFromInt(a);
            const addr = UserAddress.fromUser(b);
            const ret = try sysWrite(fd, addr, c);
            return .{ ret, 0 };
        },
    }
}

pub fn sysExit(code: u8) noreturn {
    arch.Serial.printf("user exited with code {}\n", .{code});
    while (true) {
        arch.halt();
    }
}

fn validateUserAddress(addr: usize) SysError!void {
    // Once we have multiple processes, we'll also need to check
    // that the calling process has access to this memory
    _ = arch.vmem.virtToPhys(addr) catch return SysError.BadAddress;
    if (!arch.vmem.isUserMappedRead(addr)) {
        return SysError.BadAddress;
    }
}

const UserAddress = struct {
    addr: usize,

    const Self = @This();

    /// Create a `UserAddress` from an address provided by the user.
    ///
    /// This does not perform any validation. To safely access user bytes,
    /// use `validateRange` on the created `UserAddress`.
    fn fromUser(addr: usize) Self {
        return .{ .addr = addr };
    }

    // TODO: deal with TOCTOU
    fn validateRange(self: Self, len: usize) SysError![]const u8 {
        if (len == 0) return &.{};

        const end_addr = std.math.add(usize, self.addr, len) catch return SysError.Overflow;
        // TODO: make PAGE_SIZE an arch-available constant
        const page_size = 4096;
        const end_page = std.mem.alignBackward(usize, end_addr - 1, page_size);
        var cur = std.mem.alignBackward(usize, self.addr, page_size);
        while (cur <= end_page) : (cur += page_size) {
            try validateUserAddress(cur);
            if (cur == end_page) {
                break;
            }
        }

        const buf: [*]const u8 = @ptrFromInt(self.addr);
        return buf[0..len];
    }
};

pub fn sysWrite(fd: Abi.FD, msg_addr: UserAddress, msg_len: usize) SysError!usize {
    const msg = try msg_addr.validateRange(msg_len);
    switch (fd) {
        .stdout => arch.Serial.printf("{s}", .{msg}),
        .stderr => arch.Serial.printf("{s}", .{msg}),
        .stdin => return SysError.BadFd,
        _ => return SysError.BadFd,
    }

    // TODO: actually buffer when needed
    return msg_len;
}
