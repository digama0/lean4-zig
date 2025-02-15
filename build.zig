const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("lean4", .{
        .source_file = .{
            .path = "src/c.zig",
        },
    });
    lean4FFI(b);
    try runTest(b, target);
    try reverseFFI(b, .{ target, optimize });
}

fn lean4FFI(b: *std.Build) void {
    const lake = b.findProgram(&.{"lake"}, &.{}) catch @panic("lake not found!");
    const lakebuild = lakeBuild(b, "examples/ffi/app");
    const update = b.addSystemCommand(&.{
        lake,
        "--dir=examples/ffi/app",
        "update",
    });
    const run = b.addSystemCommand(&.{
        "examples/ffi/app/build/bin/app",
    });
    lakebuild.step.dependOn(&update.step);
    run.step.dependOn(&lakebuild.step);
    const run_cmd = b.step("zffi", "run zig-lib on lean4-app");
    run_cmd.dependOn(&run.step);
}

fn reverseFFI(b: *std.Build, info: struct { std.zig.CrossTarget, std.builtin.OptimizeMode }) !void {
    const exe = b.addExecutable(.{
        .name = "reverse-ffi",
        .root_source_file = .{ .path = "examples/reverse-ffi/app/app.zig" },
        .target = info[0],
        .optimize = info[1],
    });
    exe.addModule("lean4", b.modules.get("lean4").?);
    exe.addLibraryPath(.{ .path = "examples/reverse-ffi/lib/build/lib" });
    exe.addLibraryPath(.{ .path = try lean4LibDir(b) });

    if (exe.target.isDarwin()) {
        exe.addLibraryPath(.{ .path = "/usr/local/lib" });
    }
    exe.addIncludePath(.{
        .path = b.pathJoin(
            &.{
                try lean4Prefix(b),
                "include",
            },
        ),
    });
    exe.step.dependOn(&lakeBuild(b, "examples/reverse-ffi/lib").step);

    // static obj
    exe.addCSourceFile(.{ .file = .{ .path = "examples/reverse-ffi/lib/build/ir/RFFI.c" }, .flags = &.{} });
    if (exe.target.isWindows()) {
        //exe.linkSystemLibraryName("RFFI.dll"); // not found "libRFFI.dll.a"
        exe.linkSystemLibraryName("leanshared.dll");
    } else {
        // exe.linkSystemLibrary("RFFI"); // sharedlib
        exe.linkSystemLibrary("leanshared");
    }
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("rffi", b.fmt("Run the {s} app", .{exe.name}));
    run_step.dependOn(&run_cmd.step);
}

fn lakeBuild(b: *std.Build, path: []const u8) *std.Build.Step.Run {
    const lake = b.findProgram(&.{"lake"}, &.{}) catch @panic("lake not found!");
    const run = b.addSystemCommand(&.{
        lake,
        b.fmt("--dir={s}", .{path}),
        "build",
    });
    return run;
}

fn lean4LibDir(b: *std.Build) ![]const u8 {
    const lean = try b.findProgram(&.{"lean"}, &.{});
    const run = try std.ChildProcess.exec(.{
        .allocator = b.allocator,
        .argv = &.{
            lean,
            "--print-libdir",
        },
    });
    var out = std.mem.split(u8, run.stdout, "\n"); // remove newline
    return out.first();
}
fn lean4Prefix(b: *std.Build) ![]const u8 {
    const lean = try b.findProgram(&.{"lean"}, &.{});
    const run = try std.ChildProcess.exec(.{
        .allocator = b.allocator,
        .argv = &.{
            lean,
            "--print-prefix",
        },
    });
    var out = std.mem.split(u8, run.stdout, "\n"); // remove newline
    return out.first();
}

fn runTest(b: *std.build, target: std.zig.CrossTarget) !void {
    const main_tests = b.addTest(.{
        .name = "lean_test",
        .target = target,
        .optimize = .Debug,
        .root_source_file = .{ .path = "src/c.zig" },
    });
    main_tests.addLibraryPath(.{ .path = try lean4LibDir(b) });

    if (main_tests.target.isDarwin()) {
        main_tests.addLibraryPath(.{ .path = "/usr/local/lib" });
    }
    if (main_tests.target.isWindows()) {
        main_tests.linkSystemLibraryName("leanshared.dll");
    } else {
        main_tests.linkSystemLibrary("leanshared");
    }
    main_tests.linkLibC();
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
