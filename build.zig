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
    "script",
    "vibrato",
    "fmsynth",
};

const examples_to_build = [_][]const u8{
    "script_runtime_mono",
    "script_runtime_poly",
};

pub fn build(b: *std.build.Builder) void {
    b.step("test", "Run all tests").dependOn(&b.addTest("test.zig").step);
    inline for (examples_to_run) |name| {
        b.step(name, "Run example '" ++ name ++ "'").dependOn(&example(b, name).run().step);
    }
    b.step("write_wav", "Run example 'write_wav'").dependOn(&writeWav(b).run().step);
    inline for (examples_to_build) |name| {
        b.step(name, "Build example '" ++ name ++ "'").dependOn(&example(b, name).step);
    }
    b.step("zangc", "Build zangscript compiler").dependOn(&zangc(b).step);

    {
        const step = b.step("all", "Build everything");
        inline for (examples_to_run) |name| {
            step.dependOn(&example(b, name).step);
        }
        inline for (examples_to_build) |name| {
            step.dependOn(&example(b, name).step);
        }
        step.dependOn(&writeWav(b).step);
        step.dependOn(&zangc(b).step);
    }
}

fn example(
    b: *std.build.Builder,
    comptime name: []const u8,
) *std.build.LibExeObjStep {
    var o = b.addExecutable(name, "examples/example.zig");
    o.setBuildMode(b.standardReleaseOptions());
    o.setOutputDir("zig-cache");
    o.addPackagePath("zig-wav", "examples/zig-wav/wav.zig");
    o.addPackagePath("zang", "src/zang.zig");
    o.addPackagePath("zang-12tet", "src/zang-12tet.zig");
    o.addPackagePath("modules", "src/modules.zig");
    o.addPackagePath("zangscript", "src/zangscript.zig");
    o.addBuildOption([]const u8, "example", "example_" ++ name ++ ".zig");
    o.linkSystemLibrary("SDL2");
    o.linkSystemLibrary("c");
    return o;
}

fn writeWav(b: *std.build.Builder) *std.build.LibExeObjStep {
    var o = b.addExecutable("write_wav", "examples/write_wav.zig");
    o.setBuildMode(b.standardReleaseOptions());
    o.setOutputDir("zig-cache");
    o.addPackagePath("zig-wav", "examples/zig-wav/wav.zig");
    o.addPackagePath("zang", "src/zang.zig");
    o.addPackagePath("zang-12tet", "src/zang-12tet.zig");
    o.addPackagePath("modules", "src/modules.zig");
    return o;
}

fn zangc(b: *std.build.Builder) *std.build.LibExeObjStep {
    var o = b.addExecutable("zangc", "tools/zangc.zig");
    o.setBuildMode(b.standardReleaseOptions());
    o.setOutputDir("zig-cache");
    o.addPackagePath("zangscript", "src/zangscript.zig");
    return o;
}
