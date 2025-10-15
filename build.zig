const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Detect assembly file based on target architecture
    const assembly_file = switch (target.result.cpu.arch) {
        .aarch64 => "src/asm/aarch64.s",
        .x86_64 => switch (target.result.os.tag) {
            .windows => "src/asm/x86_64_windows.s",
            else => "src/asm/x86_64.s",
        },
        .riscv64 => "src/asm/riscv64.s",
        else => {
            @panic("Unsupported cpu architecture");
        },
    };

    // Module WITH assembly for external users
    const concurrency_module_with_asm = b.addModule("ZigConcurrency", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    concurrency_module_with_asm.addAssemblyFile(b.path(assembly_file));

    // Module WITHOUT assembly for internal test imports (to avoid duplicates)
    const concurrency_module_no_asm = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Test step
    const test_step = b.step("test", "Run all tests");

    // Tests for the main library file
    const lib_test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_test_module.addAssemblyFile(b.path(assembly_file));

    const lib_tests = b.addTest(.{
        .root_module = lib_test_module,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);

    var testDir: std.fs.Dir = b.build_root.handle.openDir("src/test/", .{ .iterate = true }) catch |e| {
        std.debug.print("there is a error in opening the dir, and it is {any}\n", .{e});
        @panic("\n");
    };
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    defer testDir.close();

    var testDirIter = testDir.iterate();
    var index: u16 = 0;
    while (testDirIter.next() catch unreachable) |entry| {
        if (entry.kind == .file) {
            index = index + 1;
        }
    }

    var test_files = std.ArrayList([]const u8){};
    defer {
        for (test_files.items) |file| {
            allocator.free(file);
        }
        test_files.deinit(allocator);
    }

    listFilesRecursive(testDir, "src/test", allocator, &test_files) catch unreachable;

    for (test_files.items) |test_file| {
        const test_module = b.createModule(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
        });

        // Add assembly file to the test module itself
        test_module.addAssemblyFile(b.path(assembly_file));

        // Import the version WITHOUT assembly to avoid duplicates
        test_module.addImport("ZigConcurrency", concurrency_module_no_asm);

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
