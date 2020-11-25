const std = @import("std");

pub const PrintHelper = struct {
    out: std.io.StreamSource.OutStream,
    indentation: usize,
    indent_next: bool,

    pub fn init(out: std.io.StreamSource.OutStream) PrintHelper {
        return .{
            .out = out,
            .indentation = 0,
            .indent_next = false,
        };
    }

    // this should only be called when no error has happened (an error might
    // leave the indentation at a positive value), so don't use it with defer
    pub fn finish(self: *PrintHelper) void {
        std.debug.assert(self.indentation == 0);
    }

    pub fn print(self: *PrintHelper, outer_self: anytype, comptime fmt: []const u8, args: anytype) !void {
        if (self.indent_next) {
            self.indent_next = false;
            if (fmt.len > 0 and fmt[0] == '}') {
                self.indentation -= 1;
            }
            if (fmt.len > 0 and fmt[0] == '\n') {
                // don't indent blank lines
            } else {
                var i: usize = 0;
                while (i < self.indentation) : (i += 1) {
                    try self.out.print("    ", .{});
                }
            }
        }
        comptime var arg_index: usize = 0;
        comptime var i: usize = 0;
        inline while (i < fmt.len) {
            if (fmt[i] == '}' and i + 1 < fmt.len and fmt[i + 1] == '}') {
                try self.out.writeByte('}');
                i += 2;
                continue;
            }
            if (fmt[i] == '{') {
                i += 1;

                if (i < fmt.len and fmt[i] == '{') {
                    try self.out.writeByte('{');
                    i += 1;
                    continue;
                }

                // find the closing brace
                const start = i;
                inline while (i < fmt.len) : (i += 1) {
                    if (fmt[i] == '}') break;
                }
                if (i == fmt.len) {
                    @compileError("`{` must be followed by `}`");
                }
                const arg_format = fmt[start..i];
                i += 1;

                const arg = args[arg_index];
                arg_index += 1;

                if (comptime std.mem.eql(u8, arg_format, "auto")) {
                    try self.out.print("{}", .{arg});
                } else if (comptime std.mem.eql(u8, arg_format, "bool")) {
                    try self.out.print("{}", .{@as(bool, arg)});
                } else if (comptime std.mem.eql(u8, arg_format, "usize")) {
                    try self.out.print("{}", .{@as(usize, arg)});
                } else if (comptime std.mem.eql(u8, arg_format, "str")) {
                    try self.out.writeAll(arg);
                } else if (comptime std.mem.eql(u8, arg_format, "number_literal")) {
                    try self.out.writeAll(arg.verbatim);
                    // ensure a decimal is present, so that in generated zig code it's interpreted as a float
                    // (otherwise expressions like '1 / 10' would mistakenly do integer division).
                    // first check if this is actually a number literal, because builtin constants go
                    // into `verbatim` by name (e.g. `std.math.pi`).
                    if (arg.verbatim[0] >= '0' and arg.verbatim[0] <= '9') {
                        if (std.mem.indexOfScalar(u8, arg.verbatim, '.') == null) {
                            try self.out.writeAll(".0");
                        }
                    }
                } else {
                    try outer_self.printArgValue(arg_format, arg);
                }
            } else {
                try self.out.writeByte(fmt[i]);
                i += 1;
            }
        }
        if (fmt.len >= 1 and fmt[fmt.len - 1] == '\n') {
            self.indent_next = true;
            if (fmt.len >= 2 and fmt[fmt.len - 2] == '{') {
                self.indentation += 1;
            }
        }
    }
};
