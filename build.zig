// const std = @import("std");
// const builtin = @import("builtin");
//
// pub fn build(b: *std.Build) void {
//     const target = b.standardTargetOptions(.{});
//     const optimize = b.standardOptimizeOption(.{});
//     // const zeroDep = b.dependency("ziro", .{});
//     // const ziro = zeroDep.module("ziro");
//     const ziro = b.dependency("ziro", .{}).module("ziro");
//     const mod = b.addModule("zigConcurrency", .{
//         .root_source_file = b.path("src/root.zig"),
//         .imports = &.{
//             .{ .name = "ziro", .module = ziro },
//         },
//         .target = target,
//     });
//     const exe = b.addExecutable(.{
//         .name = "zigConcurrency",
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("src/main.zig"),
//             .target = target,
//             .optimize = optimize,
//             .imports = &.{
//                 .{ .name = "zigConcurrency", .module = mod },
//                 .{ .name = "ziro", .module = ziro }, // Add this line
//             },
//         }),
//     });
//     const assembly_file = switch (target.result.cpu.arch) {
//         .aarch64 => "src/asm/aarch64.s",
//         .x86_64 => switch (builtin.os.tag) {
//             .windows => "src/asm/x86_64_windows.s",
//             else => "src/asm/x86_64.s",
//         },
//         .riscv64 => "src/asm/riscv64.s",
//         else => {
//             @panic("Unsupported cpu architecture");
//         },
//     };
//
//     exe.addAssemblyFile(b.path(assembly_file));
//
//     b.installArtifact(exe);
//     const run_step = b.step("run", "Run the app");
//     const run_cmd = b.addRunArtifact(exe);
//     run_step.dependOn(&run_cmd.step);
//     run_cmd.step.dependOn(b.getInstallStep());
//
//     // -------new
//     if (b.args) |args| {
//         run_cmd.addArgs(args);
//     }
//     const mod_tests = b.addTest(.{
//         .root_module = mod,
//     });
//
//     const run_mod_tests = b.addRunArtifact(mod_tests);
//     const exe_tests = b.addTest(.{
//         .root_module = exe.root_module,
//     });
//
//     const run_exe_tests = b.addRunArtifact(exe_tests);
//
//     const test_step = b.step("test", "Run tests");
//     test_step.dependOn(&run_mod_tests.step);
//     test_step.dependOn(&run_exe_tests.step);
// }
//

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // This is the main library module that other packages will import
    const Concurrency_module = b.addModule("ZigConcurrency", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Test step
    const test_step = b.step("test", "Run all tests");

    // Tests for the main library file
    const lib_tests = b.addTest(.{
        .root_module = Concurrency_module,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);
    std.debug.print("in main\n", .{});
    // const cwd = std.fs.cwd();

    var testDir: std.fs.Dir = b.build_root.handle.openDir("src/test/", .{ .iterate = true }) catch |e| {
        std.debug.print("there is a error in openeing the dir, and it is {any}", .{e});
        @panic("\n");
    };
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    defer testDir.close();
    // var testFiles = std.ArrayList([]const u8){};
    // defer testFiles.deinit(allocator);
    var testDirIter = testDir.iterate();
    var index: u16 = 0;
    while (testDirIter.next() catch unreachable) |entry| {
        if (entry.kind == .file) {
            std.debug.print("the name of the entry at {d} -> {s}\n", .{ index, entry.name });
            index = index + 1;
        } else if (entry.kind == .directory) {}
    }

    var test_files = std.ArrayList([]const u8){};
    defer {
        for (test_files.items) |file| {
            allocator.free(file);
        }
        test_files.deinit(allocator);
    }

    listFilesRecursive(testDir, "src/test", allocator, &test_files) catch unreachable;
    for (test_files.items, 0..) |value, i| {
        std.debug.print("in the arraylist at {d} ->{s}\n", .{ i, value });
    }

    for (test_files.items) |test_file| {
        // Create a module for each test file
        const test_module = b.createModule(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
        });

        // Make the interface module available to the test
        test_module.addImport("ZigConcurrency", Concurrency_module);

        const t = b.addTest(.{
            .root_module = test_module,
        });

        const run_t = b.addRunArtifact(t);
        test_step.dependOn(&run_t.step);
    }
}

fn listFilesRecursive(
    dir: std.fs.Dir,
    base_path: []const u8,
    allocator: std.mem.Allocator,
    files: *std.ArrayList([]const u8),
) !void {
    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            // Create full path: base_path/filename
            const full_path = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}",
                .{ base_path, entry.name },
            );
            try files.append(allocator, full_path);
            std.debug.print("File: {s}\n", .{full_path});
        } else if (entry.kind == .directory) {
            // Open subdirectory and recurse
            var sub_dir = dir.openDir(entry.name, .{ .iterate = true }) catch |e| {
                std.debug.print("Error opening subdirectory {s}: {any}\n", .{ entry.name, e });
                continue;
            };
            defer sub_dir.close();

            const sub_path = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}",
                .{ base_path, entry.name },
            );
            defer allocator.free(sub_path);

            try listFilesRecursive(sub_dir, sub_path, allocator, files);
        }
    }
}
