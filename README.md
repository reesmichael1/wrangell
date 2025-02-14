# wrangell

A simple (x86 only, for now, with eventual hopes for ARM and RISCV) kernel written in Zig.

## Supported Hardware

So far, `wrangell` has only been tested in QEMU and Bochs. 

## Attributions

I lifted a substantial amount of the initial design from [Pluto](https://github.com/ZystemOS/pluto), with other important mentions for [Loup](https://codeberg.org/loup-os/kernel) and [kernel-zig](https://github.com/jzck/kernel-zig.git).

## The name

The different OS layers will be named after U.S. National Parks. The kernel is named after Wrangell-St. Elias in Alaska, which is a fitting name because the kernel's job is to "wrangle" hardware.
