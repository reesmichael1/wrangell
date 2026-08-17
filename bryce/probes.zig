const b = @import("blib");
const sc = b.syscalls;
const abi = @import("syscall_abi");

const Outcome = enum { accept, reject };

const PAGE_SIZE = 4096;
const USER_STACK = 0xB0001000;

fn out(str: []const u8) void {
    b.write(.stdout, str) catch {};
}

fn raw(num: u32, x: u32, y: u32, z: u32) i32 {
    const r = asm volatile ("int $0x80"
        : [ret] "=A" (-> u64),
        : [n] "{eax}" (num),
          [x] "{ebx}" (x),
          [y] "{ecx}" (y),
          [z] "{edx}" (z),
    );
    return @bitCast(@as(u32, @truncate(r)));
}

fn rawOutcome(eax: i32) Outcome {
    return if (eax >= abi.ERR_LOW and eax <= abi.ERR_HIGH) .reject else .accept;
}

fn writeHex(v: usize) void {
    var buf: [8]u8 = undefined;
    const std = @import("std");
    const msg = std.fmt.bufPrint(&buf, "{x:08}", .{v}) catch unreachable;
    out(msg);
}

fn report(name: []const u8, passed: bool) bool {
    if (passed) {
        out("[pass] ");
    } else {
        out("[FAIL] ");
    }
    out(name);
    out("\n");
    return passed;
}

fn matchesOutcome(name: []const u8, expected: Outcome, result: anytype) bool {
    const actual: Outcome = if (result) |_| .accept else |_| .reject;
    return report(name, expected == actual);
}

fn matchesOutcomeRaw(name: []const u8, expected: Outcome, eax: i32) bool {
    return report(name, expected == rawOutcome(eax));
}

/// Assert that no page in a range is readable from ring 3
fn sweepRejected(name: []const u8, start: usize, pages: usize) bool {
    var leaked = false;
    var first: usize = 0;
    var i: usize = 0;
    while (i < pages) : (i += 1) {
        const addr = start + i * PAGE_SIZE;
        if (sc.write(.stdout, addr, 1)) |_| {
            if (!leaked) {
                first = addr;
                leaked = true;
            }
        } else |_| {}
    }

    const passed = report(name, !leaked);
    if (leaked) {
        out("       first leaking address: ");
        writeHex(first);
        out("\n");
    }
    return passed;
}

pub fn runAll() bool {
    var ok = true;
    out("\n--- syscall probes ---\n");

    // Things that should work normally
    ok = matchesOutcome("mapped user page", .accept, sc.write(.stdout, USER_STACK, 4)) and ok;
    ok = matchesOutcome("zero length, junk address", .accept, sc.write(.stdout, 0xDEADBEEF, 0)) and ok;

    // Check that nothing in kernel memory is readable
    ok = sweepRejected("kernel 4 MB window", 0xC0000000, 1024) and ok;
    ok = sweepRejected("recursive page tables", 0xFFC00000, 1024) and ok;

    // Various failure conditions
    ok = matchesOutcome("unmapped page", .reject, sc.write(.stdout, 0xB0002000, 8)) and ok;
    ok = matchesOutcome("range spans into unmapped page", .reject, sc.write(.stdout, USER_STACK, 0x2000)) and ok;
    ok = matchesOutcome("unknown fd", .reject, sc.write(@enumFromInt(5), USER_STACK, 4)) and ok;
    ok = matchesOutcome("length reaching top of address space", .reject, sc.write(.stdout, USER_STACK, 0x4FFFE001)) and ok;
    ok = matchesOutcome("length that overflows the range", .reject, sc.write(.stdout, USER_STACK, 0xFFFFFFFF)) and ok;
    ok = matchesOutcomeRaw("unknown syscall number", .reject, raw(99, 0, 0, 0)) and ok;
    ok = matchesOutcomeRaw("negative syscall number", .reject, raw(0xFFFFFFFF, 0, 0, 0)) and ok;
    ok = matchesOutcomeRaw("fd larger than the ABI tag type", .reject, raw(1, 70000, USER_STACK, 4)) and ok;
    ok = matchesOutcomeRaw("exit code out of range", .reject, raw(0, 999, 0, 0)) and ok;

    if (ok) {
        out("--- all probes passed ---\n");
    } else {
        out("--- PROBES FAILED ---\n");
    }
    return ok;
}
