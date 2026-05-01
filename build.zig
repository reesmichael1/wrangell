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
        .cpu_model = .{ .explicit = &std.Target.x86.cpu.i386 },
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    };

    const optimize = b.standardOptimizeOption(.{});

    const syscall_mod = b.createModule(.{ .root_source_file = b.path("src/syscalls/abi.zig") });

    // Some temporary shims to run bryce until we have a proper ELF loader
    const bryce_mod = b.createModule(.{
        .root_source_file = b.path("bryce/init.zig"),
        .target = b.resolveTargetQuery(kernel_query),
        .optimize = optimize,
        .code_model = .kernel,
    });
    bryce_mod.addImport("syscall_abi", syscall_mod);
    const bryce = b.addObject(.{
        .name = "init",
        .root_module = bryce_mod,
    });
    const ld_cmd = b.addSystemCommand(&.{ "ld", "-m", "elf_i386", "-T" });
    ld_cmd.addFileArg(b.path("bryce/linker.ld"));
    ld_cmd.addArg("-o");
    const bryce_elf = ld_cmd.addOutputFileArg("init.elf");
    ld_cmd.addFileArg(bryce.getEmittedBin());

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(kernel_query),
        .optimize = optimize,
        .code_model = .kernel,
    });
    const bryce_bin = b.addObjCopy(bryce_elf, .{
        .format = .bin,
        .basename = "init.bin",
    });
    exe_mod.addAnonymousImport("init_bin", .{ .root_source_file = bryce_bin.getOutput() });
    exe_mod.addImport("syscall_abi", syscall_mod);

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
        // "-d",
        // "int",
        "-no-reboot",
        "-monitor",
        "telnet:localhost:4444,server,nowait",
    });
    qemu_cmd.step.dependOn(b.getInstallStep());

    const qemu_step = b.step("qemu", "Run the OS in QEMU");
    qemu_step.dependOn(&qemu_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = b.resolveTargetQuery(.{}),
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}
