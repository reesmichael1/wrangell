build-bryce name:
    nasm -f bin bryce/{{ name }}.asm -o bryce/{{ name }}.bin
