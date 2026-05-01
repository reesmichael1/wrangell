// At least for now, let's copy i386 on Linux. From syscall(2):
//
//
// Arch/ABI    Instruction           System  Ret  Ret  Error    Notes
//                                   call #  val  val2
// ───────────────────────────────────────────────────────────────────
// i386        int $0x80             eax     eax  edx  -

// Linux provides 300-some syscalls, so we probably won't need more than that.
// Besides, we want to move to a microkernel architecture someday.
//
// In x86-32 parameters for Linux system call are passed using registers.
// %eax for syscall_number. %ebx, %ecx, %edx, %esi, %edi are used
// for passing 5 parameters to system calls.

pub const SYSCALL_INT_NO: u8 = 0x80;

pub const Number = enum(u16) {
    exit = 0,
};
