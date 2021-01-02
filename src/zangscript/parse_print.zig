const std = @import("std");
const Source = @import("context.zig").Source;
const PrintHelper = @import("print_helper.zig").PrintHelper;
const Module = @import("parse.zig").Module;
const Expression = @import("parse.zig").Expression;
const Statement = @import("parse.zig").Statement;
const Local = @import("parse.zig").Local;
const Scope = @import("parse.zig").Scope;

const State = struct {
    source: Source,
    modules: []const Module,
    module: Module,
    helper: PrintHelper(std.io.StreamSource.OutStream),

    pub fn print(self: *State, comptime fmt: []const u8, args: anytype) !void {
        try self.helper.print(self, fmt, args);
    }

    pub fn printArgValue(self: *State, comptime arg_format: []const u8, arg: anytype) !void {
        @compileError("unknown arg_format: \"" ++ arg_format ++ "\"");
    }

    fn indent(self: *State, indentation: usize) !void {
        var i: usize = 0;
        while (i < indentation) : (i += 1) {
            try self.print("    ", .{});
        }
    }

    fn printStatement(self: *State, statement: Statement, indentation: usize) !void {
        try self.indent(indentation);
        switch (statement) {
            .let_assignment => |x| {
                try self.print("LET {str} =\n", .{self.module.info.?.locals[x.local_index].name});
                try self.printExpression(x.expression, indentation + 1);
            },
            .output => |expression| {
                try self.print("OUT\n", .{});
                try self.printExpression(expression, indentation + 1);
            },
            .feedback => |expression| {
                try self.print("FEEDBACK\n", .{});
                try self.printExpression(expression, indentation + 1);
            },
        }
    }

    fn printExpression(self: *State, expression: *const Expression, indentation: usize) std.os.WriteError!void {
        try self.indent(indentation);
        switch (expression.inner) {
            .call => |call| {
                try self.print("call (\n", .{});
                try self.printExpression(call.field_expr, indentation + 1);
                try self.indent(indentation);
                try self.print(") (\n", .{});
                for (call.args) |arg| {
                    try self.indent(indentation + 1);
                    try self.print("{str}:\n", .{arg.param_name});
                    try self.printExpression(arg.value, indentation + 2);
                }
                try self.indent(indentation);
                try self.print(")\n", .{});
            },
            .local => |local_index| try self.print("{str}\n", .{self.module.info.?.locals[local_index].name}),
            .track_call => |track_call| {
                try self.print("track_call (\n", .{});
                try self.printExpression(track_call.track_expr, indentation + 1);
                try self.printExpression(track_call.speed, indentation + 1);
                try self.print(") (\n", .{});
                for (track_call.scope.statements.items) |statement| {
                    try self.printStatement(statement, indentation + 1);
                }
                try self.indent(indentation);
                try self.print(")\n", .{});
            },
            .delay => |delay| {
                try self.print("delay {usize} (\n", .{delay.num_samples});
                for (delay.scope.statements.items) |statement| {
                    try self.printStatement(statement, indentation + 1);
                }
                try self.indent(indentation);
                try self.print(")\n", .{});
            },
            .feedback => try self.print("feedback\n", .{}),
            .literal_boolean => |v| try self.print("{bool}\n", .{v}),
            .literal_number => |v| try self.print("{number_literal}\n", .{v}),
            .literal_enum_value => |v| {
                try self.print("'{str}'\n", .{v.label});
                if (v.payload) |payload| {
                    try self.printExpression(payload, indentation + 1);
                }
            },
            .literal_curve => |curve_index| try self.print("(curve {usize})\n", .{curve_index}),
            .literal_track => |track_index| try self.print("(track {usize})\n", .{track_index}),
            .literal_module => |module_index| try self.print("(module {usize})\n", .{module_index}),
            .name => |token| try self.print("(name){str}\n", .{self.source.getString(token.source_range)}),
            .un_arith => |m| {
                try self.print("{auto}\n", .{m.op});
                try self.printExpression(m.a, indentation + 1);
            },
            .bin_arith => |m| {
                try self.print("{auto}\n", .{m.op});
                try self.printExpression(m.a, indentation + 1);
                try self.printExpression(m.b, indentation + 1);
            },
        }
    }
};

pub fn parsePrintModule(
    out: std.io.StreamSource.OutStream,
    source: Source,
    modules: []const Module,
    module_index: usize,
    module: Module,
) !void {
    var self: State = .{
        .source = source,
        .modules = modules,
        .module = module,
        .helper = PrintHelper(std.io.StreamSource.OutStream).init(out),
    };

    if (module.info) |info| {
        try self.print("module {usize}\n", .{module_index});
        for (info.scope.statements.items) |statement| {
            try self.printStatement(statement, 1);
        }
    } else {
        try self.print("module {usize} (builtin {str}.{str})\n", .{ module_index, module.zig_package_name.?, module.builtin_name.? });
    }
    try self.print("\n", .{});

    self.helper.finish();
}
