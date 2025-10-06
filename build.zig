const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // const zeroDep = b.dependency("ziro", .{});
    // const ziro = zeroDep.module("ziro");
    const ziro = b.dependency("ziro", .{}).module("ziro");
    const mod = b.addModule("zigConcurrency", .{
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{
            .{ .name = "ziro", .module = ziro },
        },
        .target = target,
    });
    const exe = b.addExecutable(.{
        .name = "zigConcurrency",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigConcurrency", .module = mod },
                .{ .name = "ziro", .module = ziro }, // Add this line
            },
        }),
    });
    const assembly_file = switch (target.result.cpu.arch) {
        .aarch64 => "src/asm/aarch64.s",
        .x86_64 => switch (builtin.os.tag) {
            .windows => "src/asm/x86_64_windows.s",
            else => "src/asm/x86_64.s",
        },
        .riscv64 => "src/asm/riscv64.s",
        else => {
            @panic("Unsupported cpu architecture");
        },
    };

    exe.addAssemblyFile(b.path(assembly_file));

    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // -------new
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
