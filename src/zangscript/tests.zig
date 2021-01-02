const std = @import("std");
const zangscript = @import("../zangscript.zig");

fn compileScript(allocator: *std.mem.Allocator, source: []const u8) ![]const u8 {
    const builtin_packages = &[_]zangscript.BuiltinPackage{
        zangscript.zang_builtin_package,
    };

    const errors_file = std.io.getStdErr();
    const context: zangscript.Context = .{
        .builtin_packages = builtin_packages,
        .source = .{ .filename = "script.txt", .contents = source },
        .errors_out = @as(std.io.StreamSource, .{ .file = errors_file }).writer(),
        .errors_color = false,
    };

    var parse_result = try zangscript.parse(context, allocator, null);
    defer parse_result.deinit();

    var codegen_result = try zangscript.codegen(context, parse_result, allocator, null);
    defer codegen_result.deinit();

    var script: zangscript.CompiledScript = .{
        .parse_arena = parse_result.arena,
        .codegen_arena = codegen_result.arena,
        .curves = parse_result.curves,
        .tracks = parse_result.tracks,
        .modules = parse_result.modules,
        .track_results = codegen_result.track_results,
        .module_results = codegen_result.module_results,
        .exported_modules = codegen_result.exported_modules,
    };
    // (don't use script.deinit() - we are already deiniting parse and codegen
    // results individually)

    var out_buf = std.ArrayList(u8).init(allocator);
    errdefer out_buf.deinit();

    try zangscript.generateZig(out_buf.writer(), builtin_packages, script);

    return out_buf.toOwnedSlice();
}

test "example test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const script =
        \\Instrument = defmodule
        \\    freq: cob,
        \\begin
        \\    out freq * 2
        \\end
    ;
    const expected =
        \\// THIS FILE WAS GENERATED BY THE ZANGC COMPILER
        \\
        \\const std = @import("std");
        \\const zang = @import("zang");
        \\
        \\pub const Instrument = _module12;
        \\
        \\const _module12 = struct {
        \\    pub const num_outputs = 1;
        \\    pub const num_temps = 1;
        \\    pub const Params = struct {
        \\        sample_rate: f32,
        \\        freq: zang.ConstantOrBuffer,
        \\    };
        \\    pub const NoteParams = struct {
        \\        freq: zang.ConstantOrBuffer,
        \\    };
        \\
        \\
        \\    pub fn init() _module12 {
        \\        return .{
        \\        };
        \\    }
        \\
        \\    pub fn paint(self: *_module12, span: zang.Span, outputs: [num_outputs][]f32, temps: [num_temps][]f32, note_id_changed: bool, params: Params) void {
        \\        switch (params.freq) {
        \\            .constant => |v| zang.set(span, temps[0], v),
        \\            .buffer => |v| zang.copy(span, temps[0], v),
        \\        }
        \\        zang.multiplyScalar(span, outputs[0], temps[0], 2.0);
        \\    }
        \\};
        \\
    ;
    const compiled = try compileScript(&gpa.allocator, script);
    defer gpa.allocator.free(compiled);
    std.testing.expectEqualSlices(u8, expected, compiled);
}