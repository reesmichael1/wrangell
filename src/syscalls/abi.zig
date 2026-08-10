// At least for now, let's copy i386 on Linux. From syscall(2):
//
//
// Arch/ABI    Instruction           System  Ret  Ret  Error    Notes
//                                   call #  val  val2
// ───────────────────────────────────────────────────────────────────
// i386        int $0x80             eax     eax  edx  -
//
// In x86-32 parameters for Linux system call are passed using registers.
// %eax for syscall_number. %ebx, %ecx, %edx, %esi, %edi are used
// for passing 5 parameters to system calls.

pub const SYSCALL_INT_NO: u8 = 0x80;
pub const ERR_LOW = -4095;
pub const ERR_HIGH = -1;

// Linux provides 300-some syscalls, so we probably won't need more than that.
// Besides, we want to move to a microkernel architecture someday.
pub const Number = enum(i32) {
    exit = 0,
    write = 1,
};

pub const ErrorNumber = enum(i32) {
    bad_syscall = -1,
    bad_fd = -2,
};
