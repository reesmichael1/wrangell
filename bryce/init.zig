export fn _start() noreturn {
    var i: u32 = 0;

    while (true) {
        asm volatile ("movl %[i], %%eax"
            :
            : [i] "{edx}" (i),
        );

        if (i < 4_000_000_000) {
            i += 1;
        } else {
            i = 0;
        }
    }
}
