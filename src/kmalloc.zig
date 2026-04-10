const std = @import("std");

const PAGE_SIZE = 4096;

const HEAP_START = 0xC0400000;
const HEAP_SIZE = 4 * 1024 * 1024; // 4 MB
const HEAP_END = HEAP_START + HEAP_SIZE;

const RealBackend = struct {
    const arch = @import("arch.zig").internals;
    const Serial = arch.Serial;
    const Self = @This();

    fn log(_: *Self, comptime msg: []const u8, args: anytype) void {
        Serial.printf(msg, args);
    }

    fn mapSinglePage(_: *Self, phys: u32, virt: u32) arch.vmem.PageError!void {
        return arch.vmem.mapSinglePage(phys, virt, arch.vmem.masks.present | arch.vmem.masks.read_write, .four_kb);
    }

    fn allocPage(_: *Self) arch.pmem.PmemError!u32 {
        return arch.pmem.alloc();
    }
};

var real_backend = RealBackend{};
pub var allocator = Kmalloc(RealBackend){ .backend = &real_backend };

/// Allocate the requested number of bytes and return the address
/// of the allocated range.
pub fn kmalloc(bytes: usize) ?u32 {
    return allocator.kmalloc(bytes);
}

fn Kmalloc(comptime Backend: type) type {
    return struct {
        heap_top: u32 = HEAP_START,
        next_page_start: u32 = HEAP_START,
        backend: *Backend,

        const Self = @This();

        pub fn kmalloc(self: *Self, bytes: u32) ?u32 {
            const aligned_bytes = std.mem.alignForward(u32, bytes, 8);
            const room_in_page = self.next_page_start - self.heap_top;

            if (aligned_bytes <= room_in_page) {
                // In this case, there is no need to allocate a new page
                // Instead, we can use the bytes from the previously allocated page
                const region = self.heap_top;
                self.heap_top += aligned_bytes;
                return region;
            }

            const overflow = aligned_bytes - room_in_page;
            const num_pages = (overflow + PAGE_SIZE - 1) / PAGE_SIZE;

            if (self.next_page_start + num_pages * PAGE_SIZE > HEAP_END) {
                self.backend.log("cannot allocate enough pages to satisfy request", .{});
                return null;
            }

            const base_virt = self.heap_top;
            self.heap_top = self.next_page_start;
            var remaining = overflow;

            std.debug.assert(num_pages >= 1);

            var i: usize = 1;
            while (i <= num_pages) : (i += 1) {
                const addr = self.backend.allocPage() catch |err| {
                    self.backend.log("error while allocating page: {}\n", .{err});
                    return null;
                };

                self.backend.mapSinglePage(addr, self.next_page_start) catch |err| {
                    self.backend.log("error while mapping 0x{x:08} to 0x{x:08}: {}\n", .{ addr, self.next_page_start, err });
                    return null;
                };
                self.next_page_start += PAGE_SIZE;

                if (remaining >= PAGE_SIZE) {
                    self.heap_top += PAGE_SIZE;
                    remaining -= PAGE_SIZE;
                } else {
                    self.heap_top += remaining;
                }
            }

            return base_virt;
        }
    };
}

const expect = std.testing.expect;

const TestBackend = struct {
    const Mapping = struct { virt: u32, phys: u32 };
    const Self = @This();

    mappings: std.ArrayListUnmanaged(Mapping),
    next_phys: u32 = 0x1000,

    fn init(alloc: std.mem.Allocator) !Self {
        return .{ .mappings = try std.ArrayListUnmanaged(Mapping).initCapacity(alloc, 64) };
    }

    fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        self.mappings.deinit(alloc);
    }

    fn log(_: *Self, comptime msg: []const u8, args: anytype) void {
        _ = msg;
        _ = args;
    }

    fn mapSinglePage(self: *Self, phys: u32, virt: u32) anyerror!void {
        try self.mappings.append(std.testing.allocator, .{ .phys = phys, .virt = virt });
    }

    fn allocPage(self: *Self) anyerror!u32 {
        const addr = self.next_phys;
        self.next_phys += PAGE_SIZE;
        return addr;
    }
};

test "basic allocation" {
    var backend = try TestBackend.init(std.testing.allocator);
    defer backend.deinit(std.testing.allocator);
    var test_allocator = Kmalloc(TestBackend){ .backend = &backend };
    const addr = test_allocator.kmalloc(1024).?;
    // The first allocated memory should be at the start of the heap
    try std.testing.expectEqual(HEAP_START, addr);
    // The heap start should be mapped to the start of the physical range
    try std.testing.expectEqualSlices(TestBackend.Mapping, &[1]TestBackend.Mapping{.{ .phys = 0x1000, .virt = HEAP_START }}, backend.mappings.items);
}

test "allocating two pages" {
    var backend = try TestBackend.init(std.testing.allocator);
    defer backend.deinit(std.testing.allocator);
    var test_allocator = Kmalloc(TestBackend){ .backend = &backend };
    _ = test_allocator.kmalloc(1024).?;
    const addr = test_allocator.kmalloc(PAGE_SIZE).?;
    // The newly allocated memory should start at this address
    try std.testing.expectEqual(HEAP_START + 1024, addr);
    // There should now be two mapped pages, spanning the first two pages of virtual (and physical) memory
    try std.testing.expectEqualSlices(TestBackend.Mapping, &[2]TestBackend.Mapping{ .{ .phys = 0x1000, .virt = HEAP_START }, .{ .phys = 0x2000, .virt = HEAP_START + PAGE_SIZE } }, backend.mappings.items);
}
