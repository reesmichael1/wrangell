ENTRY(_start)

KERNEL_ADDR_OFFSET = 0xC0000000;
/*KERNEL_ADDR_OFFSET = 0;*/
KERNEL_VADDR_START = 0xC0200000;

SECTIONS {
  . = 2M;
  KERNEL_PHYSADDR_START = .;

  /* Section for the multiboot header */
  .rodata.boot : {
    KEEP(*(.rodata.boot))
  }

  /* Identity mapping for kernel boot */
  .text.boot : {
    KEEP(*(.text.boot))
  }

  . += KERNEL_ADDR_OFFSET;

  .text ALIGN(4K) : AT (ADDR(.text) - KERNEL_ADDR_OFFSET) {
    *(.text)
  }

  .rodata ALIGN(4K) : AT (ADDR(.rodata) - KERNEL_ADDR_OFFSET) {
    *(.rodata)
  }

  .data ALIGN(4K) : AT (ADDR(.data) - KERNEL_ADDR_OFFSET) {
    *(.data)
  }

  .bss ALIGN(4K) : AT (ADDR(.bss) - KERNEL_ADDR_OFFSET) {
    *(COMMON)
    *(.bss)
  }

  .bss.stack ALIGN(4K) : AT (ADDR(.bss.stack) - KERNEL_ADDR_OFFSET) {
    KERNEL_STACK_START = .;
    KEEP(*(.bss.stack))
    KERNEL_STACK_END = .;
  }

  KERNEL_VADDR_END = .;
  KERNEL_PHYSADDR_END = . - KERNEL_ADDR_OFFSET;
}
