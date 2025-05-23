const std = @import("std");

pub fn build(b: *std.Build) void {
    // For a while, I didn't have these features copied from the OSDEV bare bones wiki.
    // That caused lots of problems, which I only finally tracked down after looking
    // at the specific instructions that were causing an invalid opcode exception.
    // I've also had to track down some other ones that weren't in the bare bones set.
    var disabled_features = std.Target.Cpu.Feature.Set.empty;
    var enabled_features = std.Target.Cpu.Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.mmx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse2));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx2));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.bmi));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.bmi2));
    enabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.soft_float));

    const kernel_query = std.Target.Query{
        .cpu_arch = .x86,
        .cpu_model = .native,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    };

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(kernel_query),
        .optimize = optimize,
        .code_model = .kernel,
    });

    const kernel = b.addExecutable(.{
        .name = "wrangell",
        .root_module = exe_mod,
    });
    kernel.pie = false;
    kernel.setLinkerScript(b.path("src/arch/x86/linker.ld"));
    b.installArtifact(kernel);

    const kernel_path = std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ b.exe_dir, kernel.out_filename }) catch unreachable;
    const qemu_cmd = b.addSystemCommand(&.{
        "qemu-system-i386",
        "-kernel",
        kernel_path,
        "-serial",
        "stdio",
        "-m",
        "4G",
        "-no-reboot",
        // "-display",
        // "sdl",
    });
    qemu_cmd.step.dependOn(b.getInstallStep());

    const qemu_step = b.step("qemu", "Run the OS in QEMU");
    qemu_step.dependOn(&qemu_cmd.step);
}
