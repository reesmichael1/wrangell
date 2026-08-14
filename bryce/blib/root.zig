//! blib ("Bryce Library") is the (comparatively) high level wrapper
//! around the raw Wrangell syscalls.
//!
//! By convention, it is imported simply as "b".
//!
//! If needed, the syscalls are available through `b.syscalls`.

const abi = @import("syscall_abi");
pub const syscalls = @import("syscalls.zig");

pub fn write(fd: abi.FD, str: []const u8) syscalls.SysError!void {
    // TODO: catch buffering and, if needed, write until the end
    _ = try syscalls.write(fd, @intFromPtr(str.ptr), str.len);
}
