const std = @import("std");

const examples_to_run = [_][]const u8{
    "play",
    "song",
    "subsong",
    "envelope",
    "stereo",
    "curve",
    "detuned",
    "laser",
    "portamento",
    "arpeggiator",
    "sampler",
    "polyphony",
    "polyphony2",
    "delay",
    "mouse",
    "two",
    // "script",
    "vibrato",
    "fmsynth",
};

// const examples_to_build = [_][]const u8{
//     "script_runtime_mono",
//     "script_runtime_poly",
// };

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    {
        const step = b.step("test", "Run all tests");
        const test_ = b.addTest(.{
            .name = "test",
            .root_source_file = .{ .path = "test.zig" },
            .optimize = optimize,
            .target = target,
        });
        step.dependOn(&test_.step);
    }

    inline for (examples_to_run) |name| {
        const exe = example(b, name, optimize, target);
        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step(name, "Run example '" ++ name ++ "'");
        run_step.dependOn(&run_cmd.step);
    }

    {
        const exe = writeWav(b, optimize, target);
        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step("write_wav", "Run example 'write_wav'");
        run_step.dependOn(&run_cmd.step);
    }

    // inline for (examples_to_build) |name| {
    //     b.step(name, "Build example '" ++ name ++ "'").dependOn(&example(b, name).step);
    // }
    // b.step("zangc", "Build zangscript compiler").dependOn(&zangc(b).step);
}

fn example(b: *std.Build, comptime name: []const u8, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) *std.build.CompileStep {
    const zig_wav_module = b.createModule(.{
        .source_file = .{ .path = "examples/zig-wav/wav.zig" },
    });
    const zang_module = b.createModule(.{
        .source_file = .{ .path = "src/zang.zig" },
    });
    const zang_12tet_module = b.createModule(.{
        .source_file = .{ .path = "src/zang-12tet.zig" },
    });
    const modules_module = b.createModule(.{
        .source_file = .{ .path = "src/modules.zig" },
        .dependencies = &.{
            .{ .name = "zang", .module = zang_module },
        },
    });
    const common_module = b.createModule(.{
        .source_file = .{ .path = "examples/common.zig" },
        .dependencies = &.{
            .{ .name = "zang-12tet", .module = zang_12tet_module },
        },
    });
    const example_module = b.createModule(.{
        .source_file = .{ .path = "examples/example_" ++ name ++ ".zig" },
        .dependencies = &.{
            .{ .name = "zig-wav", .module = zig_wav_module },
            .{ .name = "zang", .module = zang_module },
            .{ .name = "zang-12tet", .module = zang_12tet_module },
            .{ .name = "modules", .module = modules_module },
            .{ .name = "common", .module = common_module },
        },
    });
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = "examples/example.zig" },
        .optimize = optimize,
        .target = target,
    });
    exe.addModule("zang", zang_module);
    exe.addModule("common", common_module);
    exe.addModule("example", example_module);
    // exe.addAnonymousModule("zangscript", .{
    //     .source_file = .{ .path = "src/zangscript.zig" },
    // });
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("c");
    return exe;
}

fn writeWav(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) *std.build.CompileStep {
    const zig_wav_module = b.createModule(.{
        .source_file = .{ .path = "examples/zig-wav/wav.zig" },
    });
    const zang_module = b.createModule(.{
        .source_file = .{ .path = "src/zang.zig" },
    });
    const zang_12tet_module = b.createModule(.{
        .source_file = .{ .path = "src/zang-12tet.zig" },
    });
    const modules_module = b.createModule(.{
        .source_file = .{ .path = "src/modules.zig" },
        .dependencies = &.{
            .{ .name = "zang", .module = zang_module },
        },
    });
    const exe = b.addExecutable(.{
        .name = "write_wav",
        .root_source_file = .{ .path = "examples/write_wav.zig" },
        .optimize = optimize,
        .target = target,
    });
    exe.addModule("zig-wav", zig_wav_module);
    exe.addModule("zang-12tet", zang_12tet_module);
    exe.addModule("modules", modules_module);
    return exe;
}

// fn zangc(b: *std.Build) *std.build.CompileStep {
//     var exe = b.addExecutable("zangc", "tools/zangc.zig");
//     exe.setBuildMode(b.standardReleaseOptions());
//     exe.setOutputDir("zig-cache");
//     exe.addAnonymousModule("zangscript", "src/zangscript.zig");
//     return exe;
// }
