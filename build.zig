const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zeroDep = b.dependency("ziro", .{});
    const ziro = zeroDep.module("ziro");
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
    // const ziro_dep = b.dependency("ziro", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    exe.linkLibrary(zeroDep.*.artifact("ziro"));
    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
