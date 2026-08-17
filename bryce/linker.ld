ENTRY(_start)

SECTIONS {
    /* We currently map this init command to 0xB0000000 within main.zig */
    . = 0xB0000000;

    .text : {
        *(.text .text.*)
    }

    .rodata : { 
        *(.rodata)
    }
    .data : {
        *(.data)
    }
    .bss : { 
        *(.bss)
    }
}
