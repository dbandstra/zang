const std = @import("std");
const PrintHelper = @import("print_helper.zig").PrintHelper;
const BuiltinPackage = @import("builtins.zig").BuiltinPackage;
const ParseResult = @import("parse.zig").ParseResult;
const Module = @import("parse.zig").Module;
const ModuleParam = @import("parse.zig").ModuleParam;
const ModuleCodeGen = @import("codegen.zig").ModuleCodeGen;
const CodeGenResult = @import("codegen.zig").CodeGenResult;
const ExpressionResult = @import("codegen.zig").ExpressionResult;
const BufferValue = @import("codegen.zig").BufferValue;
const FloatValue = @import("codegen.zig").FloatValue;
const BufferDest = @import("codegen.zig").BufferDest;
const Instruction = @import("codegen.zig").Instruction;
const CodeGenCustomModuleInner = @import("codegen.zig").CodeGenCustomModuleInner;
const CompiledScript = @import("compile.zig").CompiledScript;

fn State(comptime Writer: type) type {
    return struct {
        script: CompiledScript,
        module: ?Module,
        helper: PrintHelper(Writer),

        pub fn print(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
            try self.helper.print(self, fmt, args);
        }

        pub fn printArgValue(self: *@This(), comptime arg_format: []const u8, arg: anytype) !void {
            if (comptime std.mem.eql(u8, arg_format, "identifier")) {
                try self.printIdentifier(arg);
            } else if (comptime std.mem.eql(u8, arg_format, "module_name")) {
                try self.printModuleName(arg);
            } else if (comptime std.mem.eql(u8, arg_format, "buffer_dest")) {
                try self.printBufferDest(arg);
            } else if (comptime std.mem.eql(u8, arg_format, "expression_result")) {
                try self.printExpressionResult(arg);
            } else {
                @compileError("unknown arg_format: \"" ++ arg_format ++ "\"");
            }
        }

        fn printIdentifier(self: *@This(), string: []const u8) !void {
            if (std.zig.Token.getKeyword(string) != null) {
                try self.print("@\"{str}\"", .{string});
            } else {
                try self.print("{str}", .{string});
            }
        }

        fn printModuleName(self: *@This(), module_index: usize) !void {
            const module = self.script.modules[module_index];
            if (module.zig_package_name) |pkg_name| {
                try self.print("{identifier}.{identifier}", .{ pkg_name, module.builtin_name.? });
            } else {
                try self.print("_module{usize}", .{module_index});
            }
        }

        fn printExpressionResult(self: *@This(), result: ExpressionResult) (error{NoModule} || Writer.Error)!void {
            switch (result) {
                .nothing => unreachable,
                .temp_buffer => |temp_ref| try self.print("temps[{usize}]", .{temp_ref.index}),
                .temp_float => |temp_ref| try self.print("temp_float{usize}", .{temp_ref.index}),
                .literal_boolean => |value| try self.print("{bool}", .{value}),
                .literal_number => |value| try self.print("{number_literal}", .{value}),
                .literal_enum_value => |v| {
                    if (v.payload) |payload| {
                        try self.print(".{{ .{identifier} = {expression_result} }}", .{ v.label, payload.* });
                    } else {
                        try self.print(".{identifier}", .{v.label});
                    }
                },
                .literal_curve => |curve_index| try self.print("&_curve{usize}", .{curve_index}),
                .literal_track => |track_index| try self.print("_track{usize}", .{track_index}),
                .literal_module => |module_index| try self.print("{module_name}", .{module_index}),
                .self_param => |i| {
                    const module = self.module orelse return error.NoModule;
                    try self.print("params.{identifier}", .{module.params[i].name});
                },
                .track_param => |x| {
                    try self.print("_result.params.{identifier}", .{self.script.tracks[x.track_index].params[x.param_index].name});
                },
            }
        }

        fn printBufferDest(self: *@This(), value: BufferDest) !void {
            switch (value) {
                .temp_buffer_index => |i| try self.print("temps[{usize}]", .{i}),
                .output_index => |i| try self.print("outputs[{usize}]", .{i}),
            }
        }

        fn printParamDecls(
            self: *@This(),
            params: []const ModuleParam,
            skip_sample_rate: bool,
        ) !void {
            for (params) |param| {
                if (skip_sample_rate and std.mem.eql(u8, param.name, "sample_rate")) {
                    continue;
                }
                const type_name = switch (param.param_type) {
                    .boolean => "bool",
                    .buffer => "[]const f32",
                    .constant => "f32",
                    .constant_or_buffer => "zang.ConstantOrBuffer",
                    .curve => "[]const zang.CurveNode",
                    .one_of => |e| e.zig_name,
                };
                try self.print("{identifier}: {str},\n", .{ param.name, type_name });
            }
        }

        fn genInstruction(
            self: *@This(),
            module: Module,
            inner: CodeGenCustomModuleInner,
            instr: Instruction,
            span: []const u8,
            note_id_changed: []const u8,
        ) (error{NoModule} || Writer.Error)!void {
            switch (instr) {
                .copy_buffer => |x| {
                    const func: []const u8 = switch (x.out) {
                        .output_index => "addInto",
                        else => "copy",
                    };
                    try self.print("zang.{str}({str}, {buffer_dest}, {expression_result});\n", .{ func, span, x.out, x.in });
                },
                .float_to_buffer => |x| {
                    const func: []const u8 = switch (x.out) {
                        .output_index => "addScalarInto",
                        else => "set",
                    };
                    try self.print("zang.{str}({str}, {buffer_dest}, {expression_result});\n", .{ func, span, x.out, x.in });
                },
                .cob_to_buffer => |x| {
                    try self.print("switch (params.{identifier}) {{\n", .{module.params[x.in_self_param].name});
                    switch (x.out) {
                        .output_index => {
                            try self.print(".constant => |v| zang.addScalarInto({str}, {buffer_dest}, v),\n", .{ span, x.out });
                            try self.print(".buffer => |v| zang.addInto({str}, {buffer_dest}, v),\n", .{ span, x.out });
                        },
                        else => {
                            try self.print(".constant => |v| zang.set({str}, {buffer_dest}, v),\n", .{ span, x.out });
                            try self.print(".buffer => |v| zang.copy({str}, {buffer_dest}, v),\n", .{ span, x.out });
                        },
                    }
                    try self.print("}}\n", {});
                },
                .arith_float => |x| {
                    try self.print("const temp_float{usize} = ", .{x.out.temp_float_index});
                    switch (x.op) {
                        .abs => try self.print("std.math.fabs({expression_result});\n", .{x.a}),
                        .cos => try self.print("std.math.cos({expression_result});\n", .{x.a}),
                        .neg => try self.print("-{expression_result};\n", .{x.a}),
                        .sin => try self.print("std.math.sin({expression_result});\n", .{x.a}),
                        .sqrt => try self.print("std.math.sqrt({expression_result});\n", .{x.a}),
                    }
                },
                .arith_buffer => |x| {
                    try self.print("{{\n", .{});
                    try self.print("var i = {str}.start;\n", .{span});
                    try self.print("while (i < {str}.end) : (i += 1) {{\n", .{span});
                    try self.print("{buffer_dest}[i] ", .{x.out});
                    switch (x.out) {
                        .output_index => try self.print("+= ", .{}),
                        else => try self.print("= ", .{}),
                    }
                    switch (x.op) {
                        .abs => try self.print("std.math.fabs({expression_result}[i]);\n", .{x.a}),
                        .cos => try self.print("std.math.cos({expression_result}[i]);\n", .{x.a}),
                        .neg => try self.print("-{expression_result}[i];\n", .{x.a}),
                        .sin => try self.print("std.math.sin({expression_result}[i]);\n", .{x.a}),
                        .sqrt => try self.print("std.math.sqrt({expression_result}[i]);\n", .{x.a}),
                    }
                    try self.print("}}\n", .{});
                    try self.print("}}\n", .{});
                },
                .arith_float_float => |x| {
                    try self.print("const temp_float{usize} = ", .{x.out.temp_float_index});
                    switch (x.op) {
                        .add => try self.print("{expression_result} + {expression_result};\n", .{ x.a, x.b }),
                        .sub => try self.print("{expression_result} - {expression_result};\n", .{ x.a, x.b }),
                        .mul => try self.print("{expression_result} * {expression_result};\n", .{ x.a, x.b }),
                        .div => try self.print("{expression_result} / {expression_result};\n", .{ x.a, x.b }),
                        .pow => try self.print("std.math.pow(f32, {expression_result}, {expression_result});\n", .{ x.a, x.b }),
                        .max => try self.print("std.math.max({expression_result}, {expression_result});\n", .{ x.a, x.b }),
                        .min => try self.print("std.math.min({expression_result}, {expression_result});\n", .{ x.a, x.b }),
                    }
                },
                .arith_float_buffer => |x| {
                    switch (x.op) {
                        .sub, .div, .pow, .max, .min => {
                            try self.print("{{\n", .{});
                            try self.print("var i = {str}.start;\n", .{span});
                            try self.print("while (i < {str}.end) : (i += 1) {{\n", .{span});
                            try self.print("{buffer_dest}[i] ", .{x.out});
                            switch (x.out) {
                                .output_index => try self.print("+= ", .{}),
                                else => try self.print("= ", .{}),
                            }
                            switch (x.op) {
                                .sub => try self.print("{expression_result} - {expression_result}[i];\n", .{ x.a, x.b }),
                                .div => try self.print("{expression_result} / {expression_result}[i];\n", .{ x.a, x.b }),
                                .pow => try self.print("std.math.pow(f32, {expression_result}, {expression_result}[i]);\n", .{ x.a, x.b }),
                                .max => try self.print("std.math.max({expression_result}, {expression_result}[i]);\n", .{ x.a, x.b }),
                                .min => try self.print("std.math.min({expression_result}, {expression_result}[i]);\n", .{ x.a, x.b }),
                                else => unreachable,
                            }
                            try self.print("}}\n", .{});
                            try self.print("}}\n", .{});
                        },
                        .add, .mul => {
                            switch (x.out) {
                                .output_index => {},
                                else => try self.print("zang.zero({str}, {buffer_dest});\n", .{ span, x.out }),
                            }
                            switch (x.op) {
                                .add => try self.print("zang.addScalar", .{}),
                                .mul => try self.print("zang.multiplyScalar", .{}),
                                else => unreachable,
                            }
                            // swap order, since the supported operators are commutative
                            try self.print("({str}, {buffer_dest}, {expression_result}, {expression_result});\n", .{ span, x.out, x.b, x.a });
                        },
                    }
                },
                .arith_buffer_float => |x| {
                    switch (x.op) {
                        .sub, .div, .pow, .max, .min => {
                            try self.print("{{\n", .{});
                            try self.print("var i = {str}.start;\n", .{span});
                            try self.print("while (i < {str}.end) : (i += 1) {{\n", .{span});
                            try self.print("{buffer_dest}[i] ", .{x.out});
                            switch (x.out) {
                                .output_index => try self.print("+= ", .{}),
                                else => try self.print("= ", .{}),
                            }
                            switch (x.op) {
                                .sub => try self.print("{expression_result}[i] - {expression_result};\n", .{ x.a, x.b }),
                                .div => try self.print("{expression_result}[i] / {expression_result};\n", .{ x.a, x.b }),
                                .pow => try self.print("std.math.pow(f32, {expression_result}[i], {expression_result});\n", .{ x.a, x.b }),
                                .max => try self.print("std.math.max({expression_result}[i], {expression_result});\n", .{ x.a, x.b }),
                                .min => try self.print("std.math.min({expression_result}[i], {expression_result});\n", .{ x.a, x.b }),
                                else => unreachable,
                            }
                            try self.print("}}\n", .{});
                            try self.print("}}\n", .{});
                        },
                        else => {
                            switch (x.out) {
                                .output_index => {},
                                else => try self.print("zang.zero({str}, {buffer_dest});\n", .{ span, x.out }),
                            }
                            switch (x.op) {
                                .add => try self.print("zang.addScalar", .{}),
                                .mul => try self.print("zang.multiplyScalar", .{}),
                                else => unreachable,
                            }
                            try self.print("({str}, {buffer_dest}, {expression_result}, {expression_result});\n", .{ span, x.out, x.a, x.b });
                        },
                    }
                },
                .arith_buffer_buffer => |x| {
                    switch (x.op) {
                        .sub, .div, .pow, .max, .min => {
                            try self.print("{{\n", .{});
                            try self.print("var i = {str}.start;\n", .{span});
                            try self.print("while (i < {str}.end) : (i += 1) {{\n", .{span});
                            try self.print("{buffer_dest}[i] ", .{x.out});
                            switch (x.out) {
                                .output_index => try self.print("+= ", .{}),
                                else => try self.print("= ", .{}),
                            }
                            switch (x.op) {
                                .sub => try self.print("{expression_result}[i] - {expression_result}[i];\n", .{ x.a, x.b }),
                                .div => try self.print("{expression_result}[i] / {expression_result}[i];\n", .{ x.a, x.b }),
                                .pow => try self.print("std.math.pow(f32, {expression_result}[i], {expression_result}[i]);\n", .{ x.a, x.b }),
                                .max => try self.print("std.math.max({expression_result}[i], {expression_result}[i]);\n", .{ x.a, x.b }),
                                .min => try self.print("std.math.min({expression_result}[i], {expression_result}[i]);\n", .{ x.a, x.b }),
                                else => unreachable,
                            }
                            try self.print("}}\n", .{});
                            try self.print("}}\n", .{});
                        },
                        else => {
                            switch (x.out) {
                                .output_index => {},
                                else => try self.print("zang.zero({str}, {buffer_dest});\n", .{ span, x.out }),
                            }
                            switch (x.op) {
                                .add => try self.print("zang.add", .{}),
                                .mul => try self.print("zang.multiply", .{}),
                                else => unreachable,
                            }
                            try self.print("({str}, {buffer_dest}, {expression_result}, {expression_result});\n", .{ span, x.out, x.a, x.b });
                        },
                    }
                },
                .call => |call| {
                    const field_module_index = inner.fields[call.field_index].module_index;
                    const callee_module = self.script.modules[field_module_index];
                    switch (call.out) {
                        .output_index => {},
                        else => try self.print("zang.zero({str}, {buffer_dest});\n", .{ span, call.out }),
                    }
                    try self.print("self.field{usize}.paint({str}, .{{", .{ call.field_index, span });
                    try self.print("{buffer_dest}}}, .{{", .{call.out});
                    // callee temps
                    for (call.temps) |n, j| {
                        if (j > 0) {
                            try self.print(", ", .{});
                        }
                        try self.print("temps[{usize}]", .{n});
                    }
                    // callee params
                    try self.print("}}, {identifier}, .{{\n", .{note_id_changed});
                    for (call.args) |arg, j| {
                        const callee_param = callee_module.params[j];
                        try self.print(".{identifier} = ", .{callee_param.name});
                        if (callee_param.param_type == .constant_or_buffer) {
                            // coerce to ConstantOrBuffer?
                            switch (arg) {
                                .nothing => {},
                                .temp_buffer => |temp_ref| try self.print("zang.buffer(temps[{usize}])", .{temp_ref.index}),
                                .temp_float => |temp_ref| try self.print("zang.constant(temp_float{usize})", .{temp_ref.index}),
                                .literal_boolean => unreachable,
                                .literal_number => |value| try self.print("zang.constant({number_literal})", .{value}),
                                .literal_enum_value => unreachable,
                                .literal_curve => unreachable,
                                .literal_track => unreachable,
                                .literal_module => unreachable,
                                .self_param => |index| {
                                    const param = module.params[index];
                                    switch (param.param_type) {
                                        .boolean => unreachable,
                                        .buffer => try self.print("zang.buffer(params.{identifier})", .{param.name}),
                                        .constant => try self.print("zang.constant(params.{identifier})", .{param.name}),
                                        .constant_or_buffer => try self.print("params.{identifier}", .{param.name}),
                                        .curve => unreachable,
                                        .one_of => unreachable,
                                    }
                                },
                                .track_param => |x| {
                                    const param = self.script.tracks[x.track_index].params[x.param_index];
                                    switch (param.param_type) {
                                        .boolean => unreachable,
                                        .buffer => try self.print("zang.buffer(_result.params.{identifier})", .{param.name}),
                                        .constant => try self.print("zang.constant(_result.params.{identifier})", .{param.name}),
                                        .constant_or_buffer => try self.print("_result.params.{identifier}", .{param.name}),
                                        .curve => unreachable,
                                        .one_of => unreachable,
                                    }
                                },
                            }
                        } else {
                            try self.print("{expression_result}", .{arg});
                        }
                        try self.print(",\n", .{});
                    }
                    try self.print("}});\n", .{});
                },
                .track_call => |track_call| {
                    // FIXME hacked in support for params.note_on.
                    // i really need to rethink how note_on works and whether it belongs in "user land" (params) or not.
                    const has_note_on = for (module.params) |param| {
                        if (std.mem.eql(u8, param.name, "note_on")) break true;
                    } else false;

                    if (has_note_on) {
                        try self.print("if (params.note_on and {identifier}) {{\n", .{note_id_changed});
                    } else {
                        try self.print("if ({identifier}) {{\n", .{note_id_changed});
                    }
                    try self.print("self.tracker{usize}.reset();\n", .{track_call.note_tracker_index});
                    try self.print("self.trigger{usize}.reset();\n", .{track_call.trigger_index});
                    try self.print("}}\n", .{});

                    // FIXME protect against division by zero?
                    try self.print("const _iap{usize} = self.tracker{usize}.consume(params.sample_rate / {expression_result}, {str});\n", .{ track_call.note_tracker_index, track_call.note_tracker_index, track_call.speed, span });
                    try self.print("var _ctr{usize} = self.trigger{usize}.counter({str}, _iap{usize});\n", .{ track_call.trigger_index, track_call.trigger_index, span, track_call.note_tracker_index });
                    try self.print("while (self.trigger{usize}.next(&_ctr{usize})) |_result| {{\n", .{ track_call.trigger_index, track_call.trigger_index });

                    if (has_note_on) {
                        try self.print("const _new_note = (params.note_on and {identifier}) or _result.note_id_changed;\n", .{note_id_changed});
                    } else {
                        try self.print("const _new_note = {identifier} or _result.note_id_changed;\n", .{note_id_changed});
                    }

                    for (track_call.instructions) |sub_instr| {
                        try self.genInstruction(module, inner, sub_instr, "_result.span", "_new_note");
                    }

                    try self.print("}}\n", .{});
                },
                .delay => |delay| {
                    // this next line kind of sucks, if the delay loop iterates more than once,
                    // we'll have done some overlapping zeroing.
                    // maybe readDelayBuffer should do the zeroing internally.
                    switch (delay.out) {
                        .output_index => {},
                        else => try self.print("zang.zero({str}, {buffer_dest});\n", .{ span, delay.out }),
                    }
                    try self.print("{{\n", .{});
                    try self.print("var start = span.start;\n", .{});
                    try self.print("const end = span.end;\n", .{});
                    try self.print("while (start < end) {{\n", .{});
                    try self.print("// temps[{usize}] will be the destination for writing into the feedback buffer\n", .{
                        delay.feedback_out_temp_buffer_index,
                    });
                    try self.print("zang.zero(zang.Span.init(start, end), temps[{usize}]);\n", .{
                        delay.feedback_out_temp_buffer_index,
                    });
                    try self.print("// temps[{usize}] will contain the delay buffer's previous contents\n", .{
                        delay.feedback_temp_buffer_index,
                    });
                    try self.print("zang.zero(zang.Span.init(start, end), temps[{usize}]);\n", .{
                        delay.feedback_temp_buffer_index,
                    });
                    try self.print("const samples_read = self.delay{usize}.readDelayBuffer(temps[{usize}][start..end]);\n", .{
                        delay.delay_index,
                        delay.feedback_temp_buffer_index,
                    });
                    try self.print("const inner_span = zang.Span.init(start, start + samples_read);\n", .{});
                    // FIXME script should be able to output separately into the delay buffer, and the final result.
                    // for now, i'm hardcoding it so that delay buffer is copied to final result, and the delay expression
                    // is sent to the delay buffer. i need some new syntax in the language before i can implement
                    // this properly
                    try self.print("\n", .{});

                    //try indent(out, indentation);
                    //try out.print("// copy the old delay buffer contents into the result (hardcoded for now)\n", .{});

                    //try indent(out, indentation);
                    //try out.print("zang.addInto({str}, ", .{span});
                    //try printBufferDest(out, delay_begin.out);
                    //try out.print(", temps[{usize}]);\n", .{delay_begin.feedback_temp_buffer_index});
                    //try out.print("\n", .{});

                    try self.print("// inner expression\n", .{});
                    for (delay.instructions) |sub_instr| {
                        try self.genInstruction(module, inner, sub_instr, "inner_span", note_id_changed);
                    }

                    // end
                    try self.print("\n", .{});
                    try self.print("// write expression result into the delay buffer\n", .{});
                    try self.print("self.delay{usize}.writeDelayBuffer(temps[{usize}][start..start + samples_read]);\n", .{
                        delay.delay_index,
                        delay.feedback_out_temp_buffer_index,
                    });
                    try self.print("start += samples_read;\n", .{});
                    try self.print("}}\n", .{});
                    try self.print("}}\n", .{});
                },
            }
        }
    };
}

pub fn generateZig(
    out: anytype,
    builtin_packages: []const BuiltinPackage,
    script: CompiledScript,
) !void {
    const Writer = @TypeOf(out);
    var self: State(Writer) = .{
        .script = script,
        .module = null,
        .helper = PrintHelper(Writer).init(out),
    };

    try self.print("// THIS FILE WAS GENERATED BY THE ZANGC COMPILER\n\n", .{});
    try self.print("const std = @import(\"std\");\n", .{});
    try self.print("const zang = @import(\"zang\");\n", .{});
    for (builtin_packages) |pkg| {
        if (std.mem.eql(u8, pkg.zig_package_name, "zang")) continue;
        try self.print("const {str} = @import(\"{str}\");\n", .{ pkg.zig_package_name, pkg.zig_import_path });
    }

    if (script.exported_modules.len > 0) try self.print("\n", .{});
    for (script.exported_modules) |em| {
        try self.print("pub const {identifier} = {module_name};\n", .{ em.name, em.module_index });
    }

    const num_builtins = blk: {
        var n: usize = 0;
        for (builtin_packages) |pkg| {
            n += pkg.builtins.len;
        }
        break :blk n;
    };

    for (script.curves) |curve, curve_index| {
        try self.print("\n", .{});
        try self.print("const _curve{usize} = [_]zang.CurveNode{{\n", .{curve_index});
        for (curve.points) |point| {
            try self.print(".{{ .t = {number_literal}, .value = {number_literal} }},\n", .{ point.t, point.value });
        }
        try self.print("}};\n", .{});
    }

    for (script.tracks) |track, track_index| {
        try self.print("\n", .{});
        try self.print("const _track{usize} = struct {{\n", .{track_index});
        try self.print("const Params = struct {{\n", .{});
        try self.printParamDecls(track.params, false);
        try self.print("}};\n", .{});
        try self.print("const notes = [_]zang.Notes(Params).SongEvent{{\n", .{});
        for (track.notes) |note, note_index| {
            try self.print(".{{ .t = {number_literal}, .note_id = {usize}, .params = .{{", .{ note.t, note_index + 1 });
            for (track.params) |param, param_index| {
                if (param_index > 0) {
                    try self.print(",", .{});
                }
                try self.print(" .{str} = {expression_result}", .{ param.name, script.track_results[track_index].note_values[note_index][param_index] });
            }
            try self.print(" }} }},\n", .{});
        }
        try self.print("}};\n", .{});
        try self.print("}};\n", .{});
    }

    for (script.modules) |module, i| {
        const module_result = script.module_results[i];
        const inner = switch (module_result.inner) {
            .builtin => continue,
            .custom => |x| x,
        };

        self.module = module;

        try self.print("\n", .{});
        try self.print("const _module{usize} = struct {{\n", .{i});
        try self.print("pub const num_outputs = {usize};\n", .{module_result.num_outputs});
        try self.print("pub const num_temps = {usize};\n", .{module_result.num_temps});
        try self.print("pub const Params = struct {{\n", .{});
        try self.printParamDecls(module.params, false);
        try self.print("}};\n", .{});
        // this is for oxid. it wants a version of the params without sample_rate, which can be used with impulse queues.
        try self.print("pub const NoteParams = struct {{\n", .{});
        try self.printParamDecls(module.params, true);
        try self.print("}};\n", .{});
        try self.print("\n", .{});

        for (inner.fields) |field, j| {
            const field_module = script.modules[field.module_index];
            try self.print("field{usize}: {module_name},\n", .{ j, field.module_index });
        }
        for (inner.delays) |delay_decl, j| {
            try self.print("delay{usize}: zang.Delay({usize}),\n", .{ j, delay_decl.num_samples });
        }
        for (inner.note_trackers) |note_tracker_decl, j| {
            try self.print("tracker{usize}: zang.Notes(_track{usize}.Params).NoteTracker,\n", .{ j, note_tracker_decl.track_index });
        }
        for (inner.triggers) |trigger_decl, j| {
            try self.print("trigger{usize}: zang.Trigger(_track{usize}.Params),\n", .{ j, trigger_decl.track_index });
        }
        try self.print("\n", .{});
        try self.print("pub fn init() _module{usize} {{\n", .{i});
        try self.print("return .{{\n", .{});
        for (inner.fields) |field, j| {
            const field_module = script.modules[field.module_index];
            try self.print(".field{usize} = {module_name}.init(),\n", .{ j, field.module_index });
        }
        for (inner.delays) |delay_decl, j| {
            try self.print(".delay{usize} = zang.Delay({usize}).init(),\n", .{ j, delay_decl.num_samples });
        }
        for (inner.note_trackers) |note_tracker_decl, j| {
            try self.print(".tracker{usize} = zang.Notes(_track{usize}.Params).NoteTracker.init(&_track{usize}.notes),\n", .{ j, note_tracker_decl.track_index, note_tracker_decl.track_index });
        }
        for (inner.triggers) |trigger_decl, j| {
            try self.print(".trigger{usize} = zang.Trigger(_track{usize}.Params).init(),\n", .{ j, trigger_decl.track_index });
        }
        try self.print("}};\n", .{});
        try self.print("}}\n", .{});
        try self.print("\n", .{});
        try self.print("pub fn paint(self: *_module{usize}, span: zang.Span, outputs: [num_outputs][]f32, temps: [num_temps][]f32, note_id_changed: bool, params: Params) void {{\n", .{i});
        for (inner.instructions) |instr| {
            try self.genInstruction(module, inner, instr, "span", "note_id_changed");
        }
        try self.print("}}\n", .{});
        try self.print("}};\n", .{});
    }

    self.helper.finish();
}
